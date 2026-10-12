// Makes Bluetooth DualSense pads look like ForceFeedback devices to the game's
// statically linked SDL 2.0.7, which predates any DualSense support, and turns
// the force-feedback effects it creates into DualSense HID output reports.
//
// Injected with DYLD_INSERT_LIBRARIES alongside BO3MacFix.dylib. Every
// ForceFeedback entry point the game imports is a dynamic symbol, so dyld
// interposing reaches all of them.
//
// Up to DS_MAX_PADS controllers are tracked independently, each with its own
// open HID handle and report sequence counter, so split screen rumbles the
// right pad.

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <ForceFeedback/ForceFeedback.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <sys/mman.h>
#include <zlib.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#define DS_VENDOR_ID   0x054C
#define DS_PRODUCT_ID  0x0CE6

#define DS_MAX_PADS 4

// Bluetooth output report: 0x31, 78 bytes, trailing CRC32 over a 0xA2 seed.
#define DS_BT_REPORT_ID    0x31
#define DS_BT_REPORT_SIZE  78
#define DS_BT_TAG          0x10
#define DS_CRC_SEED        0xA2

#define DS_FLAG0_COMPATIBLE_VIBRATION 0x01
#define DS_FLAG0_HAPTICS_SELECT       0x02

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

// ---------------------------------------------------------------- logging

static FILE *g_log;
static pthread_mutex_t g_log_lock = PTHREAD_MUTEX_INITIALIZER;

static void ds_log(const char *fmt, ...) {
    pthread_mutex_lock(&g_log_lock);
    if (!g_log) {
        char path[1024];
        const char *home = getenv("HOME");
        snprintf(path, sizeof(path), "%s/Library/Logs/bo3-rumble.log", home ? home : "/tmp");
        g_log = fopen(path, "a");
        if (g_log) setvbuf(g_log, NULL, _IOLBF, 0);
    }
    if (g_log) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        fprintf(g_log, "[%ld.%03ld] ", (long)ts.tv_sec, ts.tv_nsec / 1000000);
        va_list ap;
        va_start(ap, fmt);
        vfprintf(g_log, fmt, ap);
        va_end(ap);
        fputc('\n', g_log);
    }
    pthread_mutex_unlock(&g_log_lock);
}

// ------------------------------------------------------- IOKit properties

static int service_string(io_service_t s, CFStringRef key, char *out, size_t sz) {
    if (sz) out[0] = 0;
    if (!s) return 0;
    CFTypeRef v = IORegistryEntrySearchCFProperty(s, kIOServicePlane, key, kCFAllocatorDefault,
                                                  kIORegistryIterateRecursively | kIORegistryIterateParents);
    int ok = 0;
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID())
            ok = CFStringGetCString(v, out, (CFIndex)sz, kCFStringEncodingUTF8);
        CFRelease(v);
    }
    return ok;
}

static int service_number(io_service_t s, CFStringRef key) {
    int n = 0;
    if (!s) return 0;
    CFTypeRef v = IORegistryEntrySearchCFProperty(s, kIOServicePlane, key, kCFAllocatorDefault,
                                                  kIORegistryIterateRecursively | kIORegistryIterateParents);
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, &n);
        CFRelease(v);
    }
    return n;
}

static int service_is_dualsense(io_service_t service) {
    return service_number(service, CFSTR(kIOHIDVendorIDKey)) == DS_VENDOR_ID &&
           service_number(service, CFSTR(kIOHIDProductIDKey)) == DS_PRODUCT_ID;
}

static void device_ids(IOHIDDeviceRef d, int *vid, int *pid, char *serial, size_t serial_sz) {
    CFTypeRef v = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDVendorIDKey));
    CFTypeRef p = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductIDKey));
    CFTypeRef s = IOHIDDeviceGetProperty(d, CFSTR(kIOHIDSerialNumberKey));
    *vid = *pid = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, vid);
    if (p && CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue(p, kCFNumberIntType, pid);
    if (serial_sz) {
        serial[0] = 0;
        if (s && CFGetTypeID(s) == CFStringGetTypeID())
            CFStringGetCString(s, serial, (CFIndex)serial_sz, kCFStringEncodingUTF8);
    }
}

// ---------------------------------------------------------- DualSense I/O

typedef struct {
    IOHIDDeviceRef hid;
    char serial[64];   // Bluetooth MAC, stable across reconnects
    uint8_t seq;
} DsPad;

static DsPad g_pads[DS_MAX_PADS];
static int g_pad_n;
static time_t g_last_scan;
static IOHIDManagerRef g_mgr;  // held for the process lifetime; releasing it closes the devices
static pthread_mutex_t g_hid_lock = PTHREAD_MUTEX_INITIALIZER;

static int pad_index_for_serial(const char *serial) {
    if (!serial || !*serial) return -1;
    for (int i = 0; i < g_pad_n; i++)
        if (strcasecmp(g_pads[i].serial, serial) == 0) return i;
    return -1;
}

// Bluetooth enumeration order is arbitrary, so the pads found in the first scan
// are sorted by serial to make slot assignment the same on every run. Pads that
// connect later keep arriving at the end, matching the order Steam hands out
// player indexes. DS_PAD_ORDER overrides both.
static void sort_pads_by_serial(void) {
    for (int i = 1; i < g_pad_n; i++) {
        DsPad key = g_pads[i];
        int j = i - 1;
        while (j >= 0 && strcasecmp(g_pads[j].serial, key.serial) > 0) {
            g_pads[j + 1] = g_pads[j];
            j--;
        }
        g_pads[j + 1] = key;
    }
}

// DS_PAD_ORDER is a comma-separated list of serial fragments. Any pad matching
// an entry moves to that slot, so a backwards split-screen pairing is fixed
// without a rebuild.
static void apply_pad_order(void) {
    const char *spec = getenv("DS_PAD_ORDER");
    if (!spec || !*spec) return;

    char buf[512];
    snprintf(buf, sizeof(buf), "%s", spec);
    int slot = 0;
    char *save = NULL;
    for (char *tok = strtok_r(buf, ",", &save); tok && slot < g_pad_n; tok = strtok_r(NULL, ",", &save)) {
        while (*tok == ' ') tok++;
        if (!*tok) continue;
        for (int i = slot; i < g_pad_n; i++) {
            if (strcasestr(g_pads[i].serial, tok)) {
                DsPad tmp = g_pads[slot];
                g_pads[slot] = g_pads[i];
                g_pads[i] = tmp;
                slot++;
                break;
            }
        }
    }
    ds_log("DS_PAD_ORDER applied: %s", spec);
}

// Opens every DualSense non-exclusively so the game keeps reading input from
// them. Rescans are throttled, which is how a pad plugged in mid-game is picked
// up without polling IOKit every frame.
static int ds_pads_scan(void) {
    pthread_mutex_lock(&g_hid_lock);

    time_t now = time(NULL);
    if (g_last_scan == now) { pthread_mutex_unlock(&g_hid_lock); return g_pad_n; }
    int first_scan = (g_last_scan == 0);
    g_last_scan = now;

    if (!g_mgr) {
        IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (!mgr) { pthread_mutex_unlock(&g_hid_lock); return g_pad_n; }
        IOHIDManagerSetDeviceMatching(mgr, NULL);
        IOReturn mr = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
        if (mr != kIOReturnSuccess) {
            ds_log("IOHIDManagerOpen failed 0x%08x", mr);
            CFRelease(mgr);
            pthread_mutex_unlock(&g_hid_lock);
            return g_pad_n;
        }
        g_mgr = mgr;
    }

    CFSetRef devices = IOHIDManagerCopyDevices(g_mgr);
    if (devices) {
        CFIndex n = CFSetGetCount(devices);
        IOHIDDeviceRef *list = calloc(n, sizeof(IOHIDDeviceRef));
        CFSetGetValues(devices, (const void **)list);
        for (CFIndex i = 0; i < n && g_pad_n < DS_MAX_PADS; i++) {
            int vid, pid;
            char serial[64];
            device_ids(list[i], &vid, &pid, serial, sizeof(serial));
            if (vid != DS_VENDOR_ID || pid != DS_PRODUCT_ID) continue;
            if (pad_index_for_serial(serial) >= 0) continue;

            DsPad *pad = &g_pads[g_pad_n++];
            pad->hid = (IOHIDDeviceRef)CFRetain(list[i]);
            snprintf(pad->serial, sizeof(pad->serial), "%s", serial);
            IOReturn dr = IOHIDDeviceOpen(pad->hid, kIOHIDOptionsTypeNone);
            IOHIDDeviceScheduleWithRunLoop(pad->hid, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
            ds_log("acquired DualSense %04x:%04x serial=%s open=0x%08x", vid, pid,
                   serial[0] ? serial : "?", dr);
        }
        free(list);
        CFRelease(devices);
    }

    if (first_scan && g_pad_n > 1) sort_pads_by_serial();
    if (first_scan && g_pad_n > 1) apply_pad_order();
    if (first_scan) {
        for (int i = 0; i < g_pad_n; i++)
            ds_log("pad slot %d -> %s", i, g_pads[i].serial[0] ? g_pads[i].serial : "?");
    }

    pthread_mutex_unlock(&g_hid_lock);
    return g_pad_n;
}

static DsPad *ds_pad(int slot) {
    if (slot < 0 || slot >= DS_MAX_PADS) return NULL;
    if (slot >= g_pad_n) ds_pads_scan();
    if (slot >= g_pad_n) return NULL;
    return &g_pads[slot];
}

// left = low-frequency (strong) motor, right = high-frequency (weak) motor.
static void dualsense_rumble(int slot, uint8_t left, uint8_t right) {
    DsPad *pad = ds_pad(slot);
    if (!pad || !pad->hid) return;

    uint8_t buf[DS_BT_REPORT_SIZE];
    memset(buf, 0, sizeof(buf));
    buf[0] = DS_BT_REPORT_ID;
    buf[2] = DS_BT_TAG;
    buf[3] = DS_FLAG0_COMPATIBLE_VIBRATION | DS_FLAG0_HAPTICS_SELECT; // valid_flag0
    buf[5] = right;  // motor_right
    buf[6] = left;   // motor_left

    pthread_mutex_lock(&g_hid_lock);
    buf[1] = (uint8_t)((pad->seq++ & 0x0F) << 4);

    uint8_t crc_input[1 + DS_BT_REPORT_SIZE - 4];
    crc_input[0] = DS_CRC_SEED;
    memcpy(crc_input + 1, buf, DS_BT_REPORT_SIZE - 4);
    uint32_t crc = (uint32_t)crc32(0L, crc_input, sizeof(crc_input));
    buf[74] = (uint8_t)(crc & 0xFF);
    buf[75] = (uint8_t)((crc >> 8) & 0xFF);
    buf[76] = (uint8_t)((crc >> 16) & 0xFF);
    buf[77] = (uint8_t)((crc >> 24) & 0xFF);

    IOReturn r = IOHIDDeviceSetReport(pad->hid, kIOHIDReportTypeOutput, DS_BT_REPORT_ID, buf, sizeof(buf));
    pthread_mutex_unlock(&g_hid_lock);

    if (r != kIOReturnSuccess)
        ds_log("SetReport failed 0x%08x (slot=%d l=%u r=%u)", r, slot, left, right);
}

// ------------------------------------------------------- fake FF objects

#define FAKE_DEVICE_MAGIC 0x44533544u  // 'DS5D'
#define FAKE_EFFECT_MAGIC 0x44533545u  // 'DS5E'

typedef struct { uint32_t magic; UInt32 gain; int slot; } FakeDevice;
typedef struct { uint32_t magic; CFUUIDRef type; uint8_t left, right; int playing; int slot; } FakeEffect;

static int is_fake_device(FFDeviceObjectReference r) {
    return r && ((FakeDevice *)r)->magic == FAKE_DEVICE_MAGIC;
}
static int is_fake_effect(FFEffectObjectReference r) {
    return r && ((FakeEffect *)r)->magic == FAKE_EFFECT_MAGIC;
}

// SDL asks for a sine or constant-force effect; both carry one magnitude we can
// map onto both motors. 0..10000 is the ForceFeedback magnitude scale.
static void effect_magnitudes(FakeEffect *fx, const FFEFFECT *def) {
    if (!def || !def->lpvTypeSpecificParams) return;

    long magnitude = 0;
    if (def->cbTypeSpecificParams >= sizeof(FFPERIODIC)) {
        const FFPERIODIC *p = def->lpvTypeSpecificParams;
        magnitude = p->dwMagnitude;
    } else if (def->cbTypeSpecificParams >= sizeof(FFCONSTANTFORCE)) {
        const FFCONSTANTFORCE *c = def->lpvTypeSpecificParams;
        magnitude = c->lMagnitude;
    }
    if (magnitude < 0) magnitude = -magnitude;
    if (magnitude > 10000) magnitude = 10000;

    long gain = def->dwGain ? (long)def->dwGain : 10000;
    if (gain > 10000) gain = 10000;
    long scaled = magnitude * gain / 10000;

    fx->left = fx->right = (uint8_t)(scaled * 255 / 10000);
}

static void push_active(FakeEffect *fx) {
    if (fx->playing) dualsense_rumble(fx->slot, fx->left, fx->right);
    else dualsense_rumble(fx->slot, 0, 0);
}

// The game pushes a vibration update every frame, so logging each one is
// useless. Dump the full structure about once a second instead.
static void dump_effect(const FFEFFECT *def) {
    static time_t last;
    time_t now = time(NULL);
    if (now == last || !def) return;
    last = now;

    char hex[128] = "";
    if (def->lpvTypeSpecificParams) {
        const unsigned char *b = def->lpvTypeSpecificParams;
        size_t n = def->cbTypeSpecificParams < 24 ? def->cbTypeSpecificParams : 24;
        for (size_t i = 0; i < n; i++) snprintf(hex + i * 3, 4, "%02x ", b[i]);
    }
    ds_log("  raw: gain=%u dur=%u cAxes=%u cbParams=%u params=[%s]",
           def->dwGain, def->dwDuration, def->cAxes, def->cbTypeSpecificParams, hex);
}

// Fires once shortly after the game attaches, pulsing each pad in slot order
// with slot+1 buzzes. Counting the buzzes tells you which physical controller
// landed in which slot, which is what DS_PAD_ORDER corrects.
static void *selftest_thread(void *arg) {
    (void)arg;
    sleep(20);
    int n = ds_pads_scan();
    ds_log(">>> SELF-TEST: %d pad(s)", n);
    for (int slot = 0; slot < n; slot++) {
        for (int pulse = 0; pulse <= slot; pulse++) {
            dualsense_rumble(slot, 160, 160);
            usleep(350000);
            dualsense_rumble(slot, 0, 0);
            usleep(250000);
        }
        ds_log(">>> SELF-TEST: slot %d (%s) pulsed %d time(s)", slot, g_pads[slot].serial, slot + 1);
        usleep(700000);
    }
    ds_log(">>> SELF-TEST: done");
    return NULL;
}

// ------------------------------------------------------ PlayStation glyphs

// The executable carries both glyph sets. __DATA holds 16 rows of
//     { uint64_t buttonId; const char *ps3; const char *xenon; const char *ps4; }
// and the Mac build renders the xenon column, which is why an Xbox prompt shows
// on a DualSense. Pointing that column at the ps3 strings swaps every prompt.
//
// The address is from this build of CoDBlkOps3_Exe (CODBUILD9-764). Every row is
// checked against its expected button id and a "^BPS3Button" prefix before
// anything is written, so a different build is left alone rather than corrupted.

#define GLYPH_TABLE_VMADDR 0x102103180ULL
#define GLYPH_TABLE_ROWS   16

typedef struct {
    uint64_t id;
    const char *ps3;
    const char *xenon;
    const char *ps4;
} GlyphRow;

static const uint64_t g_glyph_ids[GLYPH_TABLE_ROWS] = {
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x0e, 0x0f,
    0x10, 0x11, 0x13, 0x12, 0x16, 0x17, 0x18, 0x19,
};

// Confirms the table really lies inside a writable segment of this image before
// anything dereferences it, so a build with a different layout, or the test
// binary, fails the check instead of touching an unmapped address.
static int spans_segment(const struct mach_header_64 *mh, uint64_t unslid, uint64_t len, vm_prot_t prot) {
    if (mh->magic != MH_MAGIC_64) return 0;
    const struct load_command *lc = (const struct load_command *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sc = (const struct segment_command_64 *)lc;
            if ((sc->initprot & prot) && unslid >= sc->vmaddr &&
                unslid + len <= sc->vmaddr + sc->vmsize)
                return 1;
        }
        lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
    }
    return 0;
}

#define spans_writable_segment(mh, a, n)   spans_segment((mh), (a), (n), VM_PROT_WRITE)
#define spans_executable_segment(mh, a, n) spans_segment((mh), (a), (n), VM_PROT_EXECUTE)

static void patch_playstation_glyphs(void) {
    if (getenv("DS_XBOX_GLYPHS")) {
        ds_log("glyphs: DS_XBOX_GLYPHS set, leaving Xbox prompts alone");
        return;
    }

    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *h = _dyld_get_image_header(i);
        if (h && h->filetype == MH_EXECUTE) {
            mh = (const struct mach_header_64 *)h;
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!mh) { ds_log("glyphs: main executable not in the image list"); return; }

    if (!spans_writable_segment(mh, GLYPH_TABLE_VMADDR, sizeof(GlyphRow) * GLYPH_TABLE_ROWS)) {
        ds_log("glyphs: 0x%llx is not in a writable segment of this executable; not patching",
               GLYPH_TABLE_VMADDR);
        return;
    }

    GlyphRow *rows = (GlyphRow *)(uintptr_t)(GLYPH_TABLE_VMADDR + slide);

    for (int i = 0; i < GLYPH_TABLE_ROWS; i++) {
        if (rows[i].id != g_glyph_ids[i] || !rows[i].ps3 || !rows[i].xenon ||
            strncmp(rows[i].ps3, "^BPS3Button", 11) != 0) {
            ds_log("glyphs: table does not match at row %d (slide 0x%lx); not patching", i, (long)slide);
            return;
        }
    }

    for (int i = 0; i < GLYPH_TABLE_ROWS; i++) rows[i].xenon = rows[i].ps3;

    ds_log("glyphs: swapped %d Xbox prompts for PlayStation (e.g. %s)",
           GLYPH_TABLE_ROWS, rows[0].xenon);
}

// -------------------------------------------------- menu glyph discovery

// The keybind screen and HUD prompts go through the glyph table above, but the
// LUI menus ask the asset system for a material by name, and those names live in
// Lua inside the encrypted fastfiles where we cannot read them. So hook the
// lookup and record what the menus actually request.
//
// DB_FindXAssetHeader(int type, const char *name, int createDefault, int waitTime)
// has 151 call sites and a 17-byte prologue of pushes and a sub, none of it
// RIP-relative, so it relocates into a trampoline unchanged.

#define DB_FIND_VMADDR      0x101345b12ULL
#define DB_FIND_PROLOGUE    17
#define ASSET_TYPE_MATERIAL 6
#define ASSET_TYPE_IMAGE    9

static int g_swap_glyphs = 1;  // the reason the hook exists
static int g_log_assets;       // DS_MENU_PROBE, for discovering new names

static const uint8_t g_db_find_prologue[DB_FIND_PROLOGUE] = {
    0x55,                               // push rbp
    0x48, 0x89, 0xe5,                   // mov  rbp, rsp
    0x41, 0x57,                         // push r15
    0x41, 0x56,                         // push r14
    0x41, 0x55,                         // push r13
    0x41, 0x54,                         // push r12
    0x53,                               // push rbx
    0x48, 0x83, 0xec, 0x28,             // sub  rsp, 0x28
};

static void *(*g_db_find_orig)(int, const char *, int, int);

#define SEEN_MAX 4096
static char *g_seen[SEEN_MAX];
static int g_seen_n;
static pthread_mutex_t g_seen_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned char g_type_seen[256];

// The asset-type enum is unknown beyond material, and the menu icons are not
// materials, so match on the name instead and let the type fall out of the log.
static int looks_like_a_button(const char *n) {
    static const char *const pat[] = { "button", "btn", "prompt", "xenon", "ps3", "ps4",
                                       "dpad", "glyph", "trig", "shoulder", "stick",
                                       "icon", "key", NULL };
    for (int i = 0; pat[i]; i++)
        if (strcasestr(n, pat[i])) return 1;
    return 0;
}

static void note_asset(int type, const char *name) {
    pthread_mutex_lock(&g_seen_lock);
    int first_of_type = (type >= 0 && type < 256 && !g_type_seen[type]);
    if (first_of_type) g_type_seen[type] = 1;
    for (int i = 0; i < g_seen_n; i++) {
        if (strcmp(g_seen[i], name) == 0) {
            pthread_mutex_unlock(&g_seen_lock);
            if (first_of_type) ds_log("asset type %d first seen: %s", type, name);
            return;
        }
    }
    int room = g_seen_n < SEEN_MAX;
    if (room) g_seen[g_seen_n++] = strdup(name);
    pthread_mutex_unlock(&g_seen_lock);
    if (room) ds_log("asset[%d]: %s", type, name);
}

// Reads through a pointer the engine owns without risking a fault on a bad guess.
static int safe_read(const void *addr, void *out, size_t len) {
    vm_size_t got = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)addr, len,
                             (vm_address_t)out, &got) == KERN_SUCCESS && got == len;
}

// The LUI sources come through as rawfiles. Their struct layout is a guess, so
// log the header words and let whichever one turns out to be {len, buffer}
// identify itself, then spill the payload for offline reading.
#define ASSET_TYPE_RAWFILE 47

static void dump_rawfile(const char *name, const void *hdr) {
    if (!hdr) return;

    // The same file is requested repeatedly; one copy on disk is enough.
    static char *dumped[2048];
    static int dumped_n;
    static pthread_mutex_t dumped_lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&dumped_lock);
    for (int i = 0; i < dumped_n; i++) {
        if (strcmp(dumped[i], name) == 0) { pthread_mutex_unlock(&dumped_lock); return; }
    }
    if (dumped_n >= (int)(sizeof(dumped) / sizeof(dumped[0]))) {
        pthread_mutex_unlock(&dumped_lock);
        return;
    }
    dumped[dumped_n++] = strdup(name);
    pthread_mutex_unlock(&dumped_lock);

    uint64_t w[8];
    if (!safe_read(hdr, w, sizeof(w))) { ds_log("rawfile %s: header unreadable", name); return; }

    char line[256] = "";
    for (int i = 0; i < 8; i++)
        snprintf(line + strlen(line), sizeof(line) - strlen(line), "%016llx ", w[i]);
    ds_log("rawfile %s hdr: %s", name, line);

    for (int i = 0; i < 7; i++) {
        uint64_t len = w[i] & 0xFFFFFFFF;
        uint64_t buf = w[i + 1];
        if (len < 16 || len > (8u << 20) || buf < 0x1000) continue;
        void *tmp = malloc(len);
        if (!tmp) continue;
        if (safe_read((const void *)(uintptr_t)buf, tmp, len)) {
            char path[512];
            char safe[256];
            snprintf(safe, sizeof(safe), "%s", name);
            for (char *c = safe; *c; c++) if (*c == '/') *c = '_';
            snprintf(path, sizeof(path), "/tmp/bo3-raw/%s", safe);
            FILE *f = fopen(path, "wb");
            if (f) { fwrite(tmp, 1, len, f); fclose(f); }
        }
        free(tmp);
        break;
    }
}

// The menus ask for their button icons as images, and the fastfiles carry a
// PlayStation image beside every Xbox one. Swapping the name at the lookup is
// enough; nothing else in LUI cares which art came back.
static const char *playstation_image_for(const char *name) {
    static const struct { const char *xenon, *ps; } map[] = {
        { "xenonbutton_a",          "ps3button_x"          },
        { "xenonbutton_b",          "ps3button_circle"     },
        { "xenonbutton_x",          "ps3button_square"     },
        { "xenonbutton_y",          "ps3button_triangle"   },
        { "xenonbutton_lb",         "ps3button_l1"         },
        { "xenonbutton_rb",         "ps3button_r1"         },
        { "xenonbutton_lt",         "ps3button_l2"         },
        { "xenonbutton_rt",         "ps3button_r2"         },
        { "xenonbutton_back",       "ps3button_select"     },
        { "xenonbutton_start",      "ps3button_start"      },
        { "xenonbutton_dpad_all",   "ps3button_dpad_all"   },
        { "xenonbutton_dpad_up",    "ps3button_dpad_up"    },
        { "xenonbutton_dpad_down",  "ps3button_dpad_down"  },
        { "xenonbutton_dpad_left",  "ps3button_dpad_left"  },
        { "xenonbutton_dpad_right", "ps3button_dpad_right" },
        { "xenonbutton_dpad_ud",    "ps3button_dpad_ud"    },
        { "xenonbutton_dpad_rl",    "ps3button_dpad_rl"    },

        // The Button Layout and Stick Layout diagrams. The face buttons are
        // painted into the controller art, so the body image carries them.
        { "uie_xenonone_controller_top", "uie_ps4_controller_top" },
        { "uie_img_t7_menu_startmenu_option_lines_durango",
          "uie_img_t7_menu_startmenu_option_lines_orbis" },
    };
    // Cheap reject first; this runs for every image the game resolves.
    if (!strstr(name, "xenon") && !strstr(name, "durango")) return NULL;
    for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++)
        if (strcmp(name, map[i].xenon) == 0) return map[i].ps;
    return NULL;
}

static void *ds_db_find_xasset(int type, const char *name, int create, int wait) {
    if (name && g_log_assets && (type == ASSET_TYPE_MATERIAL || looks_like_a_button(name)))
        note_asset(type, name);

    if (type == ASSET_TYPE_IMAGE && name && g_swap_glyphs) {
        const char *ps = playstation_image_for(name);
        // createDefault = 0 so a missing PlayStation image comes back NULL
        // instead of a placeholder, and the Xbox original is used instead.
        if (ps) {
            void *swapped = g_db_find_orig(type, ps, 0, wait);
            if (swapped) return swapped;
            ds_log("image: %s has no %s, keeping Xbox art", name, ps);
        }
    }

    void *r = g_db_find_orig(type, name, create, wait);
    if (type == ASSET_TYPE_RAWFILE && name && getenv("DS_DUMP_LUA") && strstr(name, ".lua"))
        dump_rawfile(name, r);
    return r;
}

// Writes `jmp [rip+0]; .quad dest`, the only form that reaches anywhere in the
// address space without a scratch register.
static void write_abs_jmp(uint8_t *at, uint64_t dest) {
    at[0] = 0xFF; at[1] = 0x25;
    at[2] = at[3] = at[4] = at[5] = 0x00;
    memcpy(at + 6, &dest, 8);
}

static int install_db_find_hook(intptr_t slide) {
    uint8_t *target = (uint8_t *)(uintptr_t)(DB_FIND_VMADDR + slide);

    if (memcmp(target, g_db_find_prologue, DB_FIND_PROLOGUE) != 0) {
        ds_log("probe: DB_FindXAssetHeader prologue does not match; not hooking");
        return 0;
    }

    uint8_t *tramp = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (tramp == MAP_FAILED) { ds_log("probe: trampoline mmap failed"); return 0; }
    memcpy(tramp, g_db_find_prologue, DB_FIND_PROLOGUE);
    write_abs_jmp(tramp + DB_FIND_PROLOGUE, (uint64_t)(uintptr_t)(target + DB_FIND_PROLOGUE));
    if (mprotect(tramp, 4096, PROT_READ | PROT_EXEC) != 0) {
        ds_log("probe: trampoline mprotect failed");
        return 0;
    }

    // VM_PROT_COPY is what makes a signed, shared text page privately writable.
    uintptr_t page = (uintptr_t)target & ~0xFFFULL;
    size_t len = ((uintptr_t)target + DB_FIND_PROLOGUE) - page;
    kern_return_t kr = vm_protect(mach_task_self(), page, len, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) { ds_log("probe: vm_protect rw failed (%d)", kr); return 0; }

    write_abs_jmp(target, (uint64_t)(uintptr_t)&ds_db_find_xasset);
    memset(target + 14, 0x90, DB_FIND_PROLOGUE - 14);

    kr = vm_protect(mach_task_self(), page, len, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) ds_log("probe: vm_protect rx restore failed (%d)", kr);

    g_db_find_orig = (void *(*)(int, const char *, int, int))tramp;
    ds_log("probe: hooked DB_FindXAssetHeader, logging material lookups");
    return 1;
}

// -------------------------------------------------------- hook entry point

static void install_menu_glyph_hook(void) {
    g_log_assets = getenv("DS_MENU_PROBE") != NULL;
    g_swap_glyphs = getenv("DS_XBOX_GLYPHS") == NULL;
    if (!g_log_assets && !g_swap_glyphs) return;

    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *h = _dyld_get_image_header(i);
        if (h && h->filetype == MH_EXECUTE) {
            mh = (const struct mach_header_64 *)h;
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!mh || !spans_executable_segment(mh, DB_FIND_VMADDR, DB_FIND_PROLOGUE)) {
        ds_log("probe: DB_FindXAssetHeader address not in this executable; skipping");
        return;
    }
    install_db_find_hook(slide);
}

// ----------------------------------------------------------- interposes

// SDL finds joysticks through an IOHIDManager matching callback. Wrapping it
// shows exactly which devices SDL accepts, which is the only way to tell from
// outside the game whether the DualSense was recognised.
static IOHIDDeviceCallback g_sdl_match_cb;
static void *g_sdl_match_ctx;

static void ds_match_cb(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef dev) {
    int vid, pid;
    char serial[64], name[256] = "?";
    device_ids(dev, &vid, &pid, serial, sizeof(serial));
    CFTypeRef n = IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDProductKey));
    if (n && CFGetTypeID(n) == CFStringGetTypeID())
        CFStringGetCString(n, name, sizeof(name), kCFStringEncodingUTF8);

    ds_log("SDL matched device %04x:%04x '%s' serial=%s%s", vid, pid, name, serial,
           (vid == DS_VENDOR_ID && pid == DS_PRODUCT_ID) ? "  <<< DUALSENSE" : "");

    if (g_sdl_match_cb) g_sdl_match_cb(ctx, result, sender, dev);
}

static void ds_IOHIDManagerRegisterDeviceMatchingCallback(IOHIDManagerRef mgr,
                                                          IOHIDDeviceCallback cb, void *ctx) {
    ds_log("SDL registered a device-matching callback; watching enumeration");
    g_sdl_match_cb = cb;
    g_sdl_match_ctx = ctx;
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, ds_match_cb, ctx);
}

// Services we told SDL were force-feedback capable, each pinned to the physical
// pad its effects should drive. With Steam Input enabled the game drives virtual
// Xbox pads, so we claim those too and route their motor values to real hardware.
static io_service_t g_claimed[DS_MAX_PADS * 2];
static int g_claimed_slot[DS_MAX_PADS * 2];
static int g_claimed_n;

// "GamePad-2" -> slot 1. Steam numbers its virtual pads by player index, which
// is the only hint available once the real controller is hidden behind one.
static int trailing_index(const char *name) {
    size_t len = strlen(name);
    size_t end = len;
    while (end > 0 && name[end - 1] >= '0' && name[end - 1] <= '9') end--;
    if (end == len) return -1;
    long n = strtol(name + end, NULL, 10);
    if (n < 1 || n > DS_MAX_PADS) return -1;
    return (int)(n - 1);
}

static int slot_for_service(io_service_t service) {
    char serial[64], name[256];

    if (service_string(service, CFSTR(kIOHIDSerialNumberKey), serial, sizeof(serial))) {
        int slot = pad_index_for_serial(serial);
        if (slot >= 0) return slot;
    }
    if (service_string(service, CFSTR(kIOHIDProductKey), name, sizeof(name))) {
        int slot = trailing_index(name);
        if (slot >= 0) return slot;
    }
    return g_claimed_n < DS_MAX_PADS ? g_claimed_n : 0;
}

static void claim_service(io_service_t s, int slot) {
    if (g_claimed_n < (int)(sizeof(g_claimed) / sizeof(g_claimed[0]))) {
        g_claimed[g_claimed_n] = s;
        g_claimed_slot[g_claimed_n] = slot;
        g_claimed_n++;
    }
}

static int claimed_slot(io_service_t s, int *slot) {
    for (int i = 0; i < g_claimed_n; i++) {
        if (g_claimed[i] == s) { *slot = g_claimed_slot[i]; return 1; }
    }
    return 0;
}

static HRESULT ds_FFIsForceFeedback(io_service_t service) {
    int already;
    if (claimed_slot(service, &already)) return FF_OK;

    if (service_is_dualsense(service)) {
        ds_pads_scan();
        int slot = slot_for_service(service);
        ds_log("FFIsForceFeedback: claiming DualSense directly for slot %d", slot);
        claim_service(service, slot);
        return FF_OK;
    }

    HRESULT real = FFIsForceFeedback(service);
    if (real != FF_OK && ds_pads_scan() > 0) {
        int slot = slot_for_service(service);
        char name[256] = "?";
        service_string(service, CFSTR(kIOHIDProductKey), name, sizeof(name));
        ds_log("FFIsForceFeedback: claiming virtual pad '%s' -> DualSense slot %d", name, slot);
        claim_service(service, slot);
        return FF_OK;
    }
    return real;
}

static HRESULT ds_FFCreateDevice(io_service_t service, FFDeviceObjectReference *out) {
    int slot = 0;
    if (claimed_slot(service, &slot) || service_is_dualsense(service)) {
        FakeDevice *d = calloc(1, sizeof(FakeDevice));
        d->magic = FAKE_DEVICE_MAGIC;
        d->gain = 10000;
        d->slot = slot;
        *out = (FFDeviceObjectReference)d;
        ds_pads_scan();
        ds_log("FFCreateDevice: fake device %p slot %d", d, slot);
        return FF_OK;
    }
    return FFCreateDevice(service, out);
}

static HRESULT ds_FFReleaseDevice(FFDeviceObjectReference dev) {
    if (is_fake_device(dev)) {
        dualsense_rumble(((FakeDevice *)dev)->slot, 0, 0);
        free(dev);
        return FF_OK;
    }
    return FFReleaseDevice(dev);
}

static HRESULT ds_FFDeviceGetForceFeedbackCapabilities(FFDeviceObjectReference dev, FFCAPABILITIES *caps) {
    if (is_fake_device(dev)) {
        memset(caps, 0, sizeof(*caps));
        caps->supportedEffects = FFCAP_ET_CONSTANTFORCE | FFCAP_ET_SINE | FFCAP_ET_SQUARE |
                                 FFCAP_ET_TRIANGLE | FFCAP_ET_SAWTOOTHUP | FFCAP_ET_SAWTOOTHDOWN;
        caps->numFfAxes = 1;
        caps->ffAxes[0] = FFJOFS_X;
        caps->storageCapacity = 16;
        caps->playbackCapacity = 16;
        return FF_OK;
    }
    return FFDeviceGetForceFeedbackCapabilities(dev, caps);
}

static HRESULT ds_FFDeviceGetForceFeedbackProperty(FFDeviceObjectReference dev, FFProperty prop,
                                                   void *value, IOByteCount size) {
    if (is_fake_device(dev)) {
        if (prop == FFPROP_FFGAIN && size >= sizeof(UInt32)) {
            *(UInt32 *)value = ((FakeDevice *)dev)->gain;
            return FF_OK;
        }
        if (prop == FFPROP_AUTOCENTER && size >= sizeof(UInt32)) {
            *(UInt32 *)value = 0;
            return FF_OK;
        }
        return FF_OK;
    }
    return FFDeviceGetForceFeedbackProperty(dev, prop, value, size);
}

static HRESULT ds_FFDeviceSetForceFeedbackProperty(FFDeviceObjectReference dev, FFProperty prop, void *value) {
    if (is_fake_device(dev)) {
        if (prop == FFPROP_FFGAIN && value) ((FakeDevice *)dev)->gain = *(UInt32 *)value;
        return FF_OK;
    }
    return FFDeviceSetForceFeedbackProperty(dev, prop, value);
}

static HRESULT ds_FFDeviceSendForceFeedbackCommand(FFDeviceObjectReference dev, FFCommandFlag cmd) {
    if (is_fake_device(dev)) {
        if (cmd & (FFSFFC_RESET | FFSFFC_STOPALL | FFSFFC_PAUSE))
            dualsense_rumble(((FakeDevice *)dev)->slot, 0, 0);
        return FF_OK;
    }
    return FFDeviceSendForceFeedbackCommand(dev, cmd);
}

static HRESULT ds_FFDeviceCreateEffect(FFDeviceObjectReference dev, CFUUIDRef uuid,
                                       FFEFFECT *def, FFEffectObjectReference *out) {
    if (is_fake_device(dev)) {
        FakeEffect *fx = calloc(1, sizeof(FakeEffect));
        fx->magic = FAKE_EFFECT_MAGIC;
        fx->type = uuid ? (CFUUIDRef)CFRetain(uuid) : NULL;
        fx->slot = ((FakeDevice *)dev)->slot;
        effect_magnitudes(fx, def);
        *out = (FFEffectObjectReference)fx;
        ds_log("FFDeviceCreateEffect: fake effect %p slot=%d l=%u r=%u", fx, fx->slot, fx->left, fx->right);
        return FF_OK;
    }
    return FFDeviceCreateEffect(dev, uuid, def, out);
}

static HRESULT ds_FFDeviceReleaseEffect(FFDeviceObjectReference dev, FFEffectObjectReference fxref) {
    if (is_fake_device(dev) || is_fake_effect(fxref)) {
        FakeEffect *fx = (FakeEffect *)fxref;
        if (fx) {
            if (fx->playing) dualsense_rumble(fx->slot, 0, 0);
            if (fx->type) CFRelease(fx->type);
            free(fx);
        }
        return FF_OK;
    }
    return FFDeviceReleaseEffect(dev, fxref);
}

static HRESULT ds_FFEffectSetParameters(FFEffectObjectReference fxref, FFEFFECT *def, FFEffectParameterFlag flags) {
    if (is_fake_effect(fxref)) {
        FakeEffect *fx = (FakeEffect *)fxref;
        effect_magnitudes(fx, def);
        dump_effect(def);
        if (flags & FFEP_START) fx->playing = 1;
        ds_log("FFEffectSetParameters: slot=%d l=%u r=%u playing=%d", fx->slot, fx->left, fx->right, fx->playing);
        push_active(fx);
        return FF_OK;
    }
    return FFEffectSetParameters(fxref, def, flags);
}

static HRESULT ds_FFEffectStart(FFEffectObjectReference fxref, UInt32 iterations, FFEffectStartFlag flags) {
    if (is_fake_effect(fxref)) {
        FakeEffect *fx = (FakeEffect *)fxref;
        fx->playing = 1;
        ds_log("FFEffectStart: slot=%d l=%u r=%u", fx->slot, fx->left, fx->right);
        push_active(fx);
        return FF_OK;
    }
    return FFEffectStart(fxref, iterations, flags);
}

static HRESULT ds_FFEffectStop(FFEffectObjectReference fxref) {
    if (is_fake_effect(fxref)) {
        FakeEffect *fx = (FakeEffect *)fxref;
        fx->playing = 0;
        ds_log("FFEffectStop: slot=%d", fx->slot);
        dualsense_rumble(fx->slot, 0, 0);
        return FF_OK;
    }
    return FFEffectStop(fxref);
}

static HRESULT ds_FFEffectGetEffectStatus(FFEffectObjectReference fxref, FFEffectStatusFlag *status) {
    if (is_fake_effect(fxref)) {
        *status = ((FakeEffect *)fxref)->playing ? FFEGES_PLAYING : FFEGES_NOTPLAYING;
        return FF_OK;
    }
    return FFEffectGetEffectStatus(fxref, status);
}

// ------------------------------------------------- audio follows the default

// Right after creating each output queue the game pins it to the device that
// happened to be default at the time, with
// AudioQueueSetProperty(kAudioQueueProperty_CurrentDevice). That pin is why
// changing the Mac's output mid-game left the game playing into the old
// device. An unpinned AudioQueue follows the system default on its own.
//
// Re-pointing the queue afterwards is not an alternative: a running queue
// rejects the property with kAudioQueueErr_InvalidRunState (-66678), and
// stopping it to get the change accepted ends the stream. The game never
// enqueues again and the result is silence on the correct device.

static int g_audio_follow = 1;

static OSStatus ds_AudioQueueSetProperty(AudioQueueRef q, AudioQueuePropertyID id,
                                         const void *data, UInt32 size) {
    if (id == kAudioQueueProperty_CurrentDevice && g_audio_follow) {
        char uid[256] = "?";
        if (data && size >= sizeof(CFStringRef)) {
            CFStringRef s = *(CFStringRef *)data;
            if (s) CFStringGetCString(s, uid, sizeof(uid), kCFStringEncodingUTF8);
        }
        ds_log("audio: not pinning queue %p to %s, following the system default",
               (void *)q, uid);
        return noErr;
    }
    return AudioQueueSetProperty(q, id, data, size);
}

DYLD_INTERPOSE(ds_AudioQueueSetProperty, AudioQueueSetProperty)

static void watch_default_output_device(void) {
    if (getenv("DS_NO_AUDIO_FOLLOW")) {
        g_audio_follow = 0;
        ds_log("audio: DS_NO_AUDIO_FOLLOW set, output stays on the launch device");
    }
}

DYLD_INTERPOSE(ds_IOHIDManagerRegisterDeviceMatchingCallback, IOHIDManagerRegisterDeviceMatchingCallback)
DYLD_INTERPOSE(ds_FFIsForceFeedback, FFIsForceFeedback)
DYLD_INTERPOSE(ds_FFCreateDevice, FFCreateDevice)
DYLD_INTERPOSE(ds_FFReleaseDevice, FFReleaseDevice)
DYLD_INTERPOSE(ds_FFDeviceGetForceFeedbackCapabilities, FFDeviceGetForceFeedbackCapabilities)
DYLD_INTERPOSE(ds_FFDeviceGetForceFeedbackProperty, FFDeviceGetForceFeedbackProperty)
DYLD_INTERPOSE(ds_FFDeviceSetForceFeedbackProperty, FFDeviceSetForceFeedbackProperty)
DYLD_INTERPOSE(ds_FFDeviceSendForceFeedbackCommand, FFDeviceSendForceFeedbackCommand)
DYLD_INTERPOSE(ds_FFDeviceCreateEffect, FFDeviceCreateEffect)
DYLD_INTERPOSE(ds_FFDeviceReleaseEffect, FFDeviceReleaseEffect)
DYLD_INTERPOSE(ds_FFEffectSetParameters, FFEffectSetParameters)
DYLD_INTERPOSE(ds_FFEffectStart, FFEffectStart)
DYLD_INTERPOSE(ds_FFEffectStop, FFEffectStop)
DYLD_INTERPOSE(ds_FFEffectGetEffectStatus, FFEffectGetEffectStatus)

__attribute__((constructor))
static void ds_init(void) {
    ds_log("--- dualsense rumble shim loaded (pid %d) ---", getpid());
    patch_playstation_glyphs();
    install_menu_glyph_hook();
    watch_default_output_device();
    if (!getenv("DS_NO_SELFTEST")) {
        pthread_t t;
        pthread_create(&t, NULL, selftest_thread, NULL);
        pthread_detach(t);
    }
}

#ifdef DS_TEST_MAIN
// Drives the controllers directly, bypassing ForceFeedback entirely, so the HID
// output reports and the slot assignment can be verified on their own:
//     ./rumbletest [strength 0-255]
int main(int argc, char **argv) {
    int strength = argc > 1 ? atoi(argv[1]) : 180;
    int n = ds_pads_scan();
    if (n == 0) {
        fprintf(stderr, "no DualSense found (expecting %04x:%04x)\n", DS_VENDOR_ID, DS_PRODUCT_ID);
        return 1;
    }
    printf("%d pad(s)\n", n);
    for (int slot = 0; slot < n; slot++) {
        printf("slot %d (%s): strong, weak, both @ %d\n", slot, g_pads[slot].serial, strength);
        dualsense_rumble(slot, (uint8_t)strength, 0);
        sleep(1);
        dualsense_rumble(slot, 0, (uint8_t)strength);
        sleep(1);
        dualsense_rumble(slot, (uint8_t)strength, (uint8_t)strength);
        sleep(1);
        dualsense_rumble(slot, 0, 0);
        sleep(1);
    }
    printf("done\n");
    return 0;
}
#endif
