#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/IOKitLib.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>

#include "dobby.h"

#define DS_VENDOR_ID  0x054C
#define DS_PRODUCT_ID 0x0CE6
#define DS_BT_OUTPUT_REPORT_SIZE 78
#define DS_BT_REPORT_ID 0x31

#define ADDR_SDL_HapticOpenFromJoystick 0x13a300
#define ADDR_SDL_HapticRumbleInit       0x13a7f0
#define ADDR_SDL_HapticRumblePlay       0x13a8c0
#define ADDR_SDL_HapticRumbleStop       0x13aa00

static FILE *logfile = NULL;
#define DSLOG(...) do { \
    if (!logfile) logfile = fopen("/tmp/dualsense_rumble.log", "a"); \
    if (logfile) { fprintf(logfile, __VA_ARGS__); fflush(logfile); } \
} while(0)

static IOHIDDeviceRef ds_device = NULL;
static pthread_mutex_t ds_lock = PTHREAD_MUTEX_INITIALIZER;
static uintptr_t game_base = 0;
static uint8_t fake_haptic[256];

static void find_dualsense(void) {
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!mgr) return;

    int vid = DS_VENDOR_ID, pid = DS_PRODUCT_ID;
    CFNumberRef cfVid = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef cfPid = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFStringRef keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
    CFTypeRef vals[] = { cfVid, cfPid };
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault,
        (const void **)keys, (const void **)vals, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    IOHIDManagerSetDeviceMatching(mgr, match);
    IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

    CFSetRef devs = IOHIDManagerCopyDevices(mgr);
    if (devs && CFSetGetCount(devs) > 0) {
        IOHIDDeviceRef d;
        CFSetGetValues(devs, (const void **)&d);
        ds_device = d;
        CFRetain(ds_device);
        DSLOG("[DSRumble] DualSense acquired: %p\n", (void *)ds_device);
    } else {
        DSLOG("[DSRumble] No DualSense found\n");
    }
    if (devs) CFRelease(devs);
    CFRelease(match); CFRelease(cfVid); CFRelease(cfPid);
}

static void send_rumble(uint8_t left, uint8_t right) {
    if (!ds_device) return;

    uint8_t buf[DS_BT_OUTPUT_REPORT_SIZE];
    memset(buf, 0, sizeof(buf));
    buf[0] = DS_BT_REPORT_ID;
    buf[1] = 0x02;
    buf[2] = 0x03;
    buf[3] = right;
    buf[4] = left;

    IOReturn ret = IOHIDDeviceSetReport(ds_device, kIOHIDReportTypeOutput, DS_BT_REPORT_ID, buf, sizeof(buf));
    if (ret != kIOReturnSuccess) {
        DSLOG("[DSRumble] SetReport failed: 0x%x\n", ret);
    }
}

/* --- Dobby hooks --- */

static void *(*orig_SDL_HapticOpenFromJoystick)(void *joystick);
static int (*orig_SDL_HapticRumbleInit)(void *haptic);
static int (*orig_SDL_HapticRumblePlay)(void *haptic, float strength, uint32_t length);
static int (*orig_SDL_HapticRumbleStop)(void *haptic);

void *hooked_SDL_HapticOpenFromJoystick(void *joystick) {
    DSLOG("[DSRumble] SDL_HapticOpenFromJoystick(%p)\n", joystick);

    if (!ds_device) {
        DSLOG("[DSRumble]   No DualSense, falling through to original\n");
        return orig_SDL_HapticOpenFromJoystick(joystick);
    }

    memset(fake_haptic, 0, sizeof(fake_haptic));
    /* offset 0x18: supported capabilities - set constant force (0x2) */
    *(uint32_t *)(fake_haptic + 0x18) = 0x2;
    /* offset 0x10: neffects (max effects) */
    *(int32_t *)(fake_haptic + 0x10) = 16;
    /* offset 0x14: nplaying */
    *(int32_t *)(fake_haptic + 0x14) = 0;
    /* offset 0x28: ref count */
    *(int32_t *)(fake_haptic + 0x28) = 1;
    /* offset 0x2c: rumble_id, set to 0 (valid) so RumblePlay doesn't bail */
    *(int32_t *)(fake_haptic + 0x2c) = 0;

    DSLOG("[DSRumble]   Returning fake haptic device %p\n", (void *)fake_haptic);
    return (void *)fake_haptic;
}

int hooked_SDL_HapticRumbleInit(void *haptic) {
    DSLOG("[DSRumble] SDL_HapticRumbleInit(%p) -> forced 0\n", haptic);
    return 0;
}

int hooked_SDL_HapticRumblePlay(void *haptic, float strength, uint32_t length) {
    if (strength < 0.0f) strength = 0.0f;
    if (strength > 1.0f) strength = 1.0f;
    uint8_t motor = (uint8_t)(strength * 255.0f);

    DSLOG("[DSRumble] RumblePlay str=%.3f dur=%u motor=%u\n", strength, length, motor);

    pthread_mutex_lock(&ds_lock);
    send_rumble(motor, motor);
    pthread_mutex_unlock(&ds_lock);

    if (length > 0 && length < 10000) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(length * NSEC_PER_MSEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            pthread_mutex_lock(&ds_lock);
            send_rumble(0, 0);
            pthread_mutex_unlock(&ds_lock);
        });
    }

    return 0;
}

int hooked_SDL_HapticRumbleStop(void *haptic) {
    DSLOG("[DSRumble] RumbleStop\n");
    pthread_mutex_lock(&ds_lock);
    send_rumble(0, 0);
    pthread_mutex_unlock(&ds_lock);
    return 0;
}

__attribute__((constructor))
static void dsrumble_init(void) {
    logfile = fopen("/tmp/dualsense_rumble.log", "w");
    DSLOG("[DSRumble] DYLIB LOADED\n");

    find_dualsense();

    game_base = _dyld_get_image_vmaddr_slide(0) + 0x100000000;
    DSLOG("[DSRumble] Game base: 0x%lx\n", game_base);

    DobbyHook((void *)(game_base + ADDR_SDL_HapticOpenFromJoystick),
              (void *)hooked_SDL_HapticOpenFromJoystick,
              (void **)&orig_SDL_HapticOpenFromJoystick);
    DSLOG("[DSRumble] Hooked SDL_HapticOpenFromJoystick\n");

    DobbyHook((void *)(game_base + ADDR_SDL_HapticRumbleInit),
              (void *)hooked_SDL_HapticRumbleInit,
              (void **)&orig_SDL_HapticRumbleInit);
    DSLOG("[DSRumble] Hooked SDL_HapticRumbleInit\n");

    DobbyHook((void *)(game_base + ADDR_SDL_HapticRumblePlay),
              (void *)hooked_SDL_HapticRumblePlay,
              (void **)&orig_SDL_HapticRumblePlay);
    DSLOG("[DSRumble] Hooked SDL_HapticRumblePlay\n");

    DobbyHook((void *)(game_base + ADDR_SDL_HapticRumbleStop),
              (void *)hooked_SDL_HapticRumbleStop,
              (void **)&orig_SDL_HapticRumbleStop);
    DSLOG("[DSRumble] Hooked SDL_HapticRumbleStop\n");

    DSLOG("[DSRumble] All 4 hooks installed. Ready.\n");
}
