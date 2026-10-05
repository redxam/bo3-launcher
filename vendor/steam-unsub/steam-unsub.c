// steam-unsub — unsubscribes from a Black Ops III workshop item.
//
// The launcher is arm64 but Valve's libsteam_api.dylib that ships with the game
// is x86_64 only, so this runs as a separate Intel helper under Rosetta and the
// launcher spawns it.
//
// It dlopens the game's own copy of the dylib rather than bundling Valve's,
// so nothing of theirs is redistributed.
//
//   steam-unsub <path-to-libsteam_api.dylib> --count
//   steam-unsub <path-to-libsteam_api.dylib> <publishedFileId>
//
// Exit codes: 0 ok, 1 bad usage, 2 dylib problem, 3 Steam not running, 4 failed.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdint.h>

#define BO3_APPID "311210"
#define STEAMCLIENT_VERSION "SteamClient017"
#define STEAMUGC_VERSION "STEAMUGC_INTERFACE_VERSION008"

typedef int32_t HSteamPipe;
typedef int32_t HSteamUser;

typedef bool (*fn_Init)(void);
typedef void (*fn_Shutdown)(void);
typedef void (*fn_RunCallbacks)(void);
typedef void *(*fn_CreateInterface)(const char *version, int *returnCode);
typedef HSteamUser (*fn_GetHSteamUser)(void);
typedef HSteamPipe (*fn_GetHSteamPipe)(void);
typedef void *(*fn_GetISteamUGC)(void *client, HSteamUser user, HSteamPipe pipe, const char *version);
typedef uint64_t (*fn_UnsubscribeItem)(void *ugc, uint64_t publishedFileId);
typedef uint32_t (*fn_GetNumSubscribedItems)(void *ugc);

static void *need(void *lib, const char *name) {
    void *sym = dlsym(lib, name);
    if (!sym) fprintf(stderr, "steam-unsub: missing symbol %s\n", name);
    return sym;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <libsteam_api.dylib> <publishedFileId|--count>\n", argv[0]);
        return 1;
    }

    const char *dylibPath = argv[1];
    const char *target = argv[2];
    int countOnly = (strcmp(target, "--count") == 0);

    uint64_t fileId = 0;
    if (!countOnly) {
        fileId = strtoull(target, NULL, 10);
        if (fileId == 0) {
            fprintf(stderr, "steam-unsub: '%s' is not a workshop id\n", target);
            return 1;
        }
    }

    // Must be set before SteamAPI_Init or it won't know which app we are.
    setenv("SteamAppId", BO3_APPID, 1);
    setenv("SteamGameId", BO3_APPID, 1);

    void *lib = dlopen(dylibPath, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "steam-unsub: cannot load %s: %s\n", dylibPath, dlerror());
        return 2;
    }

    fn_Init Init = (fn_Init)need(lib, "SteamAPI_Init");
    fn_Shutdown Shutdown = (fn_Shutdown)need(lib, "SteamAPI_Shutdown");
    fn_RunCallbacks RunCallbacks = (fn_RunCallbacks)need(lib, "SteamAPI_RunCallbacks");
    fn_CreateInterface CreateInterface = (fn_CreateInterface)need(lib, "SteamInternal_CreateInterface");
    fn_GetHSteamUser GetUser = (fn_GetHSteamUser)need(lib, "SteamAPI_GetHSteamUser");
    fn_GetHSteamPipe GetPipe = (fn_GetHSteamPipe)need(lib, "SteamAPI_GetHSteamPipe");
    fn_GetISteamUGC GetUGC = (fn_GetISteamUGC)need(lib, "SteamAPI_ISteamClient_GetISteamUGC");

    if (!Init || !Shutdown || !RunCallbacks || !CreateInterface || !GetUser || !GetPipe || !GetUGC)
        return 2;

    if (!Init()) {
        fprintf(stderr, "steam-unsub: SteamAPI_Init failed (is Steam running and logged in?)\n");
        return 3;
    }

    int rc = 4;
    void *client = CreateInterface(STEAMCLIENT_VERSION, NULL);
    void *ugc = NULL;

    if (!client) {
        fprintf(stderr, "steam-unsub: no %s interface\n", STEAMCLIENT_VERSION);
        goto done;
    }

    ugc = GetUGC(client, GetUser(), GetPipe(), STEAMUGC_VERSION);
    if (!ugc) {
        fprintf(stderr, "steam-unsub: no %s interface\n", STEAMUGC_VERSION);
        goto done;
    }

    if (countOnly) {
        fn_GetNumSubscribedItems GetCount =
            (fn_GetNumSubscribedItems)need(lib, "SteamAPI_ISteamUGC_GetNumSubscribedItems");
        if (!GetCount) goto done;
        printf("%u\n", GetCount(ugc));
        rc = 0;
        goto done;
    }

    fn_UnsubscribeItem Unsubscribe =
        (fn_UnsubscribeItem)need(lib, "SteamAPI_ISteamUGC_UnsubscribeItem");
    if (!Unsubscribe) goto done;

    Unsubscribe(ugc, fileId);

    // The call is async. Pump callbacks so Steam actually sends it before we exit.
    for (int i = 0; i < 100; i++) {
        RunCallbacks();
        usleep(50 * 1000);
    }

    printf("unsubscribed %llu\n", (unsigned long long)fileId);
    rc = 0;

done:
    Shutdown();
    return rc;
}
