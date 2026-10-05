#include <string.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include "steam_emu.h"
#include "steam.h"
#include "dyld-interposing.h"

bool offline_mode = false;

#define EMU_GENERIC_VTABLE_SLOTS 256
#define EMU_NUM_GENERIC_PTRS 20

static uint64_t emu_generic_stub(void) { return 0; }
static void *emu_generic_vtable[EMU_GENERIC_VTABLE_SLOTS];
static void *emu_generic_ptrs[EMU_NUM_GENERIC_PTRS];

static bool check_offline(void) {
    if (offline_mode) return true;
    const char *env = getenv("BO3MACFIX_OFFLINE");
    if (env && (strcmp(env, "1") == 0 || strcasecmp(env, "true") == 0)) {
        offline_mode = true;
        return true;
    }
    return false;
}

// -- Fake ISteamUser vtable --------------------------------------------------

static CSteamID emu_fixed_steamid;

static CSteamID emu_GetSteamID(void *iface) {
    return emu_fixed_steamid;
}
static HSteamUser emu_GetHSteamUser(void *iface) { return 1; }
static bool emu_BLoggedOn(void *iface) { return true; }
static int emu_InitiateGameConnection(void *i, void *a, int b, CSteamID c, uint32_t d, uint16_t e, bool f) { return 0; }
static void emu_TerminateGameConnection(void *i, uint32_t a, uint16_t b) {}
static void emu_TrackAppUsageEvent(void *i, CGameID *g, int e, const char *x) {}
static bool emu_GetUserDataFolder(void *i, char *buf, int len) {
    if (buf && len > 0) buf[0] = '\0';
    return true;
}
static void emu_noop_void(void *i) {}
static int emu_GetAvailableVoice(void *i, uint32_t *a, uint32_t *b, uint32_t c) { return 1; /* no data */ }
static int emu_GetVoice(void *i, bool a, void *b, uint32_t c, uint32_t *d, bool e, void *f, uint32_t g, uint32_t *h, uint32_t j) { return 1; }
static int emu_DecompressVoice(void *i, const void *a, uint32_t b, void *c, uint32_t d, uint32_t *e, uint32_t f) { return 1; }
static uint32_t emu_GetVoiceOptimalSampleRate(void *i) { return 48000; }
static int emu_GetAuthSessionTicket(void *i, void *t, int m, uint32_t *o) { if (o) *o = 0; return 0; }
static int emu_BeginAuthSession(void *i, const void *t, int l, CSteamID s) { return 0; }
static void emu_EndAuthSession(void *i, CSteamID s) {}
static void emu_CancelAuthTicket(void *i, int h) {}
static int emu_UserHasLicenseForApp(void *i, CSteamID s, AppId_t a) { return 0; /* has license */ }
static bool emu_BIsBehindNAT(void *i) { return false; }
static void emu_AdvertiseGame(void *i, CSteamID s, uint32_t ip, uint16_t p) {}
static SteamAPICall_t emu_RequestEncryptedAppTicket(void *i, void *d, int l) { return 0; }
static bool emu_GetEncryptedAppTicket(void *i, void *t, int m, uint32_t *o) { return false; }
static int emu_GetGameBadgeLevel(void *i, int s, bool f) { return 0; }
static int emu_GetPlayerSteamLevel(void *i) { return 1; }
static SteamAPICall_t emu_RequestStoreAuthURL(void *i, const char *u) { return 0; }
static bool emu_BIsPhoneVerified(void *i) { return false; }
static bool emu_BIsTwoFactorEnabled(void *i) { return false; }

static ISteamUser emu_steamuser_vtable;
static ISteamUser *emu_steamuser_ptr;

// -- Fake ISteamFriends vtable -----------------------------------------------

static const char *emu_playername = "Player";

static const char *emu_GetPersonaName(void *i) { return emu_playername; }
static SteamAPICall_t emu_SetPersonaName(void *i, const char *n) { return 0; }
static int emu_GetPersonaState(void *i) { return 1; /* online */ }
static int emu_GetFriendCount(void *i, int f) { return 0; }
static CSteamID emu_GetFriendByIndex(void *i, int idx, int f) { CSteamID z = {0}; return z; }
static int emu_GetFriendRelationship(void *i, CSteamID s) { return 0; }
static int emu_GetFriendPersonaState(void *i, CSteamID s) { return 0; }
static const char *emu_GetFriendPersonaName(void *i, CSteamID s) { return ""; }
static bool emu_GetFriendGamePlayed(CSteamID s, void *info) { return false; }
static const char *emu_GetFriendPersonaNameHistory(void *i, CSteamID s, int n) { return ""; }
static int emu_GetFriendSteamLevel(void *i, CSteamID s) { return 0; }
static const char *emu_GetPlayerNickname(void *i, CSteamID s) { return ""; }
static int emu_GetFriendsGroupCount(void *i) { return 0; }
static uint16_t emu_GetFriendsGroupIDByIndex(void *i, int idx) { return 0; }
static const char *emu_GetFriendsGroupName(void *i, uint16_t g) { return ""; }
static int emu_GetFriendsGroupMembersCount(void *i, uint16_t g) { return 0; }
static void emu_GetFriendsGroupMembersList(void *i, uint16_t g, CSteamID *o, int n) {}
static bool emu_HasFriend(void *i, CSteamID s, int f) { return false; }
static int emu_GetClanCount(void *i) { return 0; }
static CSteamID emu_GetClanByIndex(void *i, int idx) { CSteamID z = {0}; return z; }
static const char *emu_GetClanName(void *i, CSteamID s) { return ""; }
static const char *emu_GetClanTag(void *i, CSteamID s) { return ""; }
static bool emu_GetClanActivityCounts(void *i, CSteamID s, int *a, int *b, int *c) { return false; }
static SteamAPICall_t emu_DownloadClanActivityCounts(CSteamID *s, int n) { return 0; }
static int emu_GetFriendCountFromSource(void *i, CSteamID s) { return 0; }
static CSteamID emu_GetFriendFromSourceByIndex(void *i, CSteamID s, int idx) { CSteamID z = {0}; return z; }
static bool emu_IsUserInSource(void *i, CSteamID u, CSteamID s) { return false; }
static void emu_SetInGameVoiceSpeaking(void *i, CSteamID s, bool b) {}
static void emu_ActivateGameOverlay(void *i, const char *d) {}
static void emu_ActivateGameOverlayToUser(void *i, const char *d, CSteamID s) {}
static void emu_ActivateGameOverlayToWebPage(void *i, const char *u) {}
static void emu_ActivateGameOverlayToStore(void *i, AppId_t a, int f) {}
static void emu_SetPlayedWith(void *i, CSteamID s) {}
static void emu_ActivateGameOverlayInviteDialog(void *i, CSteamID l) {}
static int emu_ret0_steamid(void *i, CSteamID s) { return 0; }
static bool emu_RequestUserInformation(void *i, CSteamID s, bool b) { return false; }
static SteamAPICall_t emu_RequestClanOfficerList(void *i, CSteamID s) { return 0; }
static CSteamID emu_GetClanOwner(void *i, CSteamID s) { CSteamID z = {0}; return z; }
static int emu_GetClanOfficerCount(void *i, CSteamID s) { return 0; }
static CSteamID emu_GetClanOfficerByIndex(void *i, CSteamID s, int idx) { CSteamID z = {0}; return z; }
static uint32_t emu_GetUserRestrictions(void *i) { return 0; }
static bool emu_SetRichPresence(void *i, const char *k, const char *v) { return true; }
static void emu_ClearRichPresence(void *i) {}
static const char *emu_GetFriendRichPresence(void *i, CSteamID s, const char *k) { return ""; }
static int emu_GetFriendRichPresenceKeyCount(void *i, CSteamID s) { return 0; }
static const char *emu_GetFriendRichPresenceKeyByIndex(void *i, CSteamID s, int idx) { return ""; }
static void emu_RequestFriendRichPresence(void *i, CSteamID s) {}
static bool emu_InviteUserToGame(void *i, CSteamID s, const char *c) { return false; }
static int emu_GetCoplayFriendCount(void *i) { return 0; }
static CSteamID emu_GetCoplayFriend(void *i, int idx) { CSteamID z = {0}; return z; }
static int emu_GetFriendCoplayTime(void *i, CSteamID s) { return 0; }
static AppId_t emu_GetFriendCoplayGame(void *i, CSteamID s) { return 0; }
static SteamAPICall_t emu_JoinClanChatRoom(void *i, CSteamID s) { return 0; }
static bool emu_LeaveClanChatRoom(void *i, CSteamID s) { return false; }
static int emu_GetClanChatMemberCount(void *i, CSteamID s) { return 0; }
static CSteamID emu_GetChatMemberByIndex(void *i, CSteamID s, int idx) { CSteamID z = {0}; return z; }
static bool emu_SendClanChatMessage(void *i, CSteamID s, const char *t) { return false; }
static int emu_GetClanChatMessage(CSteamID s, int m, void *t, int max, int *e, CSteamID *c) { return 0; }
static bool emu_IsClanChatAdmin(void *i, CSteamID s, CSteamID u) { return false; }
static bool emu_IsClanChatWindowOpenInSteam(void *i, CSteamID s) { return false; }
static bool emu_OpenClanChatWindowInSteam(void *i, CSteamID s) { return false; }
static bool emu_CloseClanChatWindowInSteam(void *i, CSteamID s) { return false; }
static bool emu_SetListenForFriendsMessages(void *i, bool b) { return false; }
static bool emu_ReplyToFriendMessage(void *i, CSteamID s, const char *m) { return false; }
static int emu_GetFriendMessage(void *i, CSteamID s, int m, void *d, int l, int *e) { return 0; }
static SteamAPICall_t emu_GetFollowerCount(void *i, CSteamID s) { return 0; }
static SteamAPICall_t emu_IsFollowing(void *i, CSteamID s) { return 0; }
static SteamAPICall_t emu_EnumerateFollowingList(void *i, uint32_t idx) { return 0; }

static ISteamFriends emu_steamfriends_vtable;
static ISteamFriends *emu_steamfriends_ptr;

// -- Fake ISteamApps vtable --------------------------------------------------

static bool emu_true_void(void *i) { return true; }
static bool emu_false_void(void *i) { return false; }
static const char *emu_GetCurrentGameLanguage(void *i) { return "english"; }
static const char *emu_GetAvailableGameLanguages(void *i) { return "english"; }
static bool emu_BIsSubscribedApp(void *i, AppId_t a) { return true; }
static bool emu_BIsDlcInstalled(void *i, AppId_t a) { return true; }
static uint32_t emu_GetEarliestPurchaseUnixTime(void *i, AppId_t a) { return 1400000000; }
static int emu_GetDLCCount(void *i) { return 0; }
static bool emu_BGetDLCDataByIndex(void *i, int idx, AppId_t *a, bool *b, char *n, int l) { return false; }
static void emu_InstallDLC(void *i, AppId_t a) {}
static void emu_UninstallDLC(void *i, AppId_t a) {}
static void emu_RequestAppProofOfPurchaseKey(void *i, AppId_t a) {}
static bool emu_GetCurrentBetaName(void *i, char *n, int l) { return false; }
static bool emu_MarkContentCorrupt(void *i, bool b) { return false; }
static uint32_t emu_GetInstalledDepots(void *i, AppId_t a, DepotId_t *d, uint32_t m) { return 0; }
static uint32_t emu_GetAppInstallDir(void *i, AppId_t a, char *buf, uint32_t len) {
    const char *path = ".";
    if (buf && len > 0) strncpy(buf, path, len);
    return (uint32_t)strlen(path);
}
static bool emu_BIsAppInstalled(void *i, AppId_t a) { return true; }
static CSteamID emu_GetAppOwner(void *i) { return emu_GetSteamID(i); }
static const char *emu_GetLaunchQueryParam(void *i, const char *k) { return ""; }
static bool emu_GetDlcDownloadProgress(void *i, AppId_t a, uint64_t *dl, uint64_t *total) { return false; }
static int emu_GetAppBuildId(void *i) { return 0; }
static void emu_RequestAllProofOfPurchaseKeys(void *i) {}

static ISteamApps emu_steamapps_vtable;
static ISteamApps *emu_steamapps_ptr;

// -- Fake CSteamAPIContext ---------------------------------------------------

static CSteamAPIContext emu_context;

void steam_emu_init(void) {
    const char *envname = getenv("BO3MACFIX_PLAYERNAME");
    if (envname && strlen(envname) >= 1 && strlen(envname) <= 16)
        emu_playername = envname;

    // Generate a stable fake SteamID from the username
    uint64_t hash = 0;
    const char *p = emu_playername;
    while (*p) { hash = hash * 31 + (unsigned char)*p; p++; }
    emu_fixed_steamid.id = 76561198000000000ULL + (hash % 999999999);

    // -- ISteamUser vtable --
    memset(&emu_steamuser_vtable, 0, sizeof(emu_steamuser_vtable));
    emu_steamuser_vtable.GetHSteamUser = emu_GetHSteamUser;
    emu_steamuser_vtable.BLoggedOn = emu_BLoggedOn;
    emu_steamuser_vtable.GetSteamID = emu_GetSteamID;
    emu_steamuser_vtable.InitiateGameConnection = emu_InitiateGameConnection;
    emu_steamuser_vtable.TerminateGameConnection = emu_TerminateGameConnection;
    emu_steamuser_vtable.TrackAppUsageEvent = emu_TrackAppUsageEvent;
    emu_steamuser_vtable.GetUserDataFolder = emu_GetUserDataFolder;
    emu_steamuser_vtable.StartVoiceRecording = emu_noop_void;
    emu_steamuser_vtable.StopVoiceRecording = emu_noop_void;
    emu_steamuser_vtable.GetAvailableVoice = emu_GetAvailableVoice;
    emu_steamuser_vtable.GetVoice = emu_GetVoice;
    emu_steamuser_vtable.DecompressVoice = emu_DecompressVoice;
    emu_steamuser_vtable.GetVoiceOptimalSampleRate = emu_GetVoiceOptimalSampleRate;
    emu_steamuser_vtable.GetAuthSessionTicket = emu_GetAuthSessionTicket;
    emu_steamuser_vtable.BeginAuthSession = emu_BeginAuthSession;
    emu_steamuser_vtable.EndAuthSession = emu_EndAuthSession;
    emu_steamuser_vtable.CancelAuthTicket = emu_CancelAuthTicket;
    emu_steamuser_vtable.UserHasLicenseForApp = emu_UserHasLicenseForApp;
    emu_steamuser_vtable.BIsBehindNAT = emu_BIsBehindNAT;
    emu_steamuser_vtable.AdvertiseGame = emu_AdvertiseGame;
    emu_steamuser_vtable.RequestEncryptedAppTicket = emu_RequestEncryptedAppTicket;
    emu_steamuser_vtable.GetEncryptedAppTicket = emu_GetEncryptedAppTicket;
    emu_steamuser_vtable.GetGameBadgeLevel = emu_GetGameBadgeLevel;
    emu_steamuser_vtable.GetPlayerSteamLevel = emu_GetPlayerSteamLevel;
    emu_steamuser_vtable.RequestStoreAuthURL = emu_RequestStoreAuthURL;
    emu_steamuser_vtable.BIsPhoneVerified = emu_BIsPhoneVerified;
    emu_steamuser_vtable.BIsTwoFactorEnabled = emu_BIsTwoFactorEnabled;
    emu_steamuser_ptr = &emu_steamuser_vtable;

    // -- ISteamFriends vtable --
    memset(&emu_steamfriends_vtable, 0, sizeof(emu_steamfriends_vtable));
    emu_steamfriends_vtable.GetPersonaName = emu_GetPersonaName;
    emu_steamfriends_vtable.SetPersonaName = emu_SetPersonaName;
    emu_steamfriends_vtable.GetPersonaState = emu_GetPersonaState;
    emu_steamfriends_vtable.GetFriendCount = emu_GetFriendCount;
    emu_steamfriends_vtable.GetFriendByIndex = emu_GetFriendByIndex;
    emu_steamfriends_vtable.GetFriendRelationship = emu_GetFriendRelationship;
    emu_steamfriends_vtable.GetFriendPersonaState = emu_GetFriendPersonaState;
    emu_steamfriends_vtable.GetFriendPersonaName = emu_GetFriendPersonaName;
    emu_steamfriends_vtable.GetFriendGamePlayed = emu_GetFriendGamePlayed;
    emu_steamfriends_vtable.GetFriendPersonaNameHistory = emu_GetFriendPersonaNameHistory;
    emu_steamfriends_vtable.GetFriendSteamLevel = emu_GetFriendSteamLevel;
    emu_steamfriends_vtable.GetPlayerNickname = emu_GetPlayerNickname;
    emu_steamfriends_vtable.GetFriendsGroupCount = emu_GetFriendsGroupCount;
    emu_steamfriends_vtable.GetFriendsGroupIDByIndex = emu_GetFriendsGroupIDByIndex;
    emu_steamfriends_vtable.GetFriendsGroupName = emu_GetFriendsGroupName;
    emu_steamfriends_vtable.GetFriendsGroupMembersCount = emu_GetFriendsGroupMembersCount;
    emu_steamfriends_vtable.GetFriendsGroupMembersList = emu_GetFriendsGroupMembersList;
    emu_steamfriends_vtable.HasFriend = emu_HasFriend;
    emu_steamfriends_vtable.GetClanCount = emu_GetClanCount;
    emu_steamfriends_vtable.GetClanByIndex = emu_GetClanByIndex;
    emu_steamfriends_vtable.GetClanName = emu_GetClanName;
    emu_steamfriends_vtable.GetClanTag = emu_GetClanTag;
    emu_steamfriends_vtable.GetClanActivityCounts = emu_GetClanActivityCounts;
    emu_steamfriends_vtable.DownloadClanActivityCounts = emu_DownloadClanActivityCounts;
    emu_steamfriends_vtable.GetFriendCountFromSource = emu_GetFriendCountFromSource;
    emu_steamfriends_vtable.GetFriendFromSourceByIndex = emu_GetFriendFromSourceByIndex;
    emu_steamfriends_vtable.IsUserInSource = emu_IsUserInSource;
    emu_steamfriends_vtable.SetInGameVoiceSpeaking = emu_SetInGameVoiceSpeaking;
    emu_steamfriends_vtable.ActivateGameOverlay = emu_ActivateGameOverlay;
    emu_steamfriends_vtable.ActivateGameOverlayToUser = emu_ActivateGameOverlayToUser;
    emu_steamfriends_vtable.ActivateGameOverlayToWebPage = emu_ActivateGameOverlayToWebPage;
    emu_steamfriends_vtable.ActivateGameOverlayToStore = emu_ActivateGameOverlayToStore;
    emu_steamfriends_vtable.SetPlayedWith = emu_SetPlayedWith;
    emu_steamfriends_vtable.ActivateGameOverlayInviteDialog = emu_ActivateGameOverlayInviteDialog;
    emu_steamfriends_vtable.GetSmallFriendAvatar = emu_ret0_steamid;
    emu_steamfriends_vtable.GetMediumFriendAvatar = emu_ret0_steamid;
    emu_steamfriends_vtable.GetLargeFriendAvatar = emu_ret0_steamid;
    emu_steamfriends_vtable.RequestUserInformation = emu_RequestUserInformation;
    emu_steamfriends_vtable.RequestClanOfficerList = emu_RequestClanOfficerList;
    emu_steamfriends_vtable.GetClanOwner = emu_GetClanOwner;
    emu_steamfriends_vtable.GetClanOfficerCount = emu_GetClanOfficerCount;
    emu_steamfriends_vtable.GetClanOfficerByIndex = emu_GetClanOfficerByIndex;
    emu_steamfriends_vtable.GetUserRestrictions = emu_GetUserRestrictions;
    emu_steamfriends_vtable.SetRichPresence = emu_SetRichPresence;
    emu_steamfriends_vtable.ClearRichPresence = emu_ClearRichPresence;
    emu_steamfriends_vtable.GetFriendRichPresence = emu_GetFriendRichPresence;
    emu_steamfriends_vtable.GetFriendRichPresenceKeyCount = emu_GetFriendRichPresenceKeyCount;
    emu_steamfriends_vtable.GetFriendRichPresenceKeyByIndex = emu_GetFriendRichPresenceKeyByIndex;
    emu_steamfriends_vtable.RequestFriendRichPresence = emu_RequestFriendRichPresence;
    emu_steamfriends_vtable.InviteUserToGame = emu_InviteUserToGame;
    emu_steamfriends_vtable.GetCoplayFriendCount = emu_GetCoplayFriendCount;
    emu_steamfriends_vtable.GetCoplayFriend = emu_GetCoplayFriend;
    emu_steamfriends_vtable.GetFriendCoplayTime = emu_GetFriendCoplayTime;
    emu_steamfriends_vtable.GetFriendCoplayGame = emu_GetFriendCoplayGame;
    emu_steamfriends_vtable.JoinClanChatRoom = emu_JoinClanChatRoom;
    emu_steamfriends_vtable.LeaveClanChatRoom = emu_LeaveClanChatRoom;
    emu_steamfriends_vtable.GetClanChatMemberCount = emu_GetClanChatMemberCount;
    emu_steamfriends_vtable.GetChatMemberByIndex = emu_GetChatMemberByIndex;
    emu_steamfriends_vtable.SendClanChatMessage = emu_SendClanChatMessage;
    emu_steamfriends_vtable.GetClanChatMessage = emu_GetClanChatMessage;
    emu_steamfriends_vtable.IsClanChatAdmin = emu_IsClanChatAdmin;
    emu_steamfriends_vtable.IsClanChatWindowOpenInSteam = emu_IsClanChatWindowOpenInSteam;
    emu_steamfriends_vtable.OpenClanChatWindowInSteam = emu_OpenClanChatWindowInSteam;
    emu_steamfriends_vtable.CloseClanChatWindowInSteam = emu_CloseClanChatWindowInSteam;
    emu_steamfriends_vtable.SetListenForFriendsMessages = emu_SetListenForFriendsMessages;
    emu_steamfriends_vtable.ReplyToFriendMessage = emu_ReplyToFriendMessage;
    emu_steamfriends_vtable.GetFriendMessage = emu_GetFriendMessage;
    emu_steamfriends_vtable.GetFollowerCount = emu_GetFollowerCount;
    emu_steamfriends_vtable.IsFollowing = emu_IsFollowing;
    emu_steamfriends_vtable.EnumerateFollowingList = emu_EnumerateFollowingList;
    emu_steamfriends_ptr = &emu_steamfriends_vtable;

    // -- ISteamApps vtable --
    memset(&emu_steamapps_vtable, 0, sizeof(emu_steamapps_vtable));
    emu_steamapps_vtable.BIsSubscribed = emu_true_void;
    emu_steamapps_vtable.BIsLowViolence = emu_false_void;
    emu_steamapps_vtable.BIsCybercafe = emu_false_void;
    emu_steamapps_vtable.BIsVACBanned = emu_false_void;
    emu_steamapps_vtable.GetCurrentGameLanguage = emu_GetCurrentGameLanguage;
    emu_steamapps_vtable.GetAvailableGameLanguages = emu_GetAvailableGameLanguages;
    emu_steamapps_vtable.BIsSubscribedApp = emu_BIsSubscribedApp;
    emu_steamapps_vtable.BIsDlcInstalled = emu_BIsDlcInstalled;
    emu_steamapps_vtable.GetEarliestPurchaseUnixTime = emu_GetEarliestPurchaseUnixTime;
    emu_steamapps_vtable.BIsSubscribedFromFreeWeekend = emu_false_void;
    emu_steamapps_vtable.GetDLCCount = emu_GetDLCCount;
    emu_steamapps_vtable.BGetDLCDataByIndex = emu_BGetDLCDataByIndex;
    emu_steamapps_vtable.InstallDLC = emu_InstallDLC;
    emu_steamapps_vtable.UninstallDLC = emu_UninstallDLC;
    emu_steamapps_vtable.RequestAppProofOfPurchaseKey = emu_RequestAppProofOfPurchaseKey;
    emu_steamapps_vtable.GetCurrentBetaName = emu_GetCurrentBetaName;
    emu_steamapps_vtable.MarkContentCorrupt = emu_MarkContentCorrupt;
    emu_steamapps_vtable.GetInstalledDepots = emu_GetInstalledDepots;
    emu_steamapps_vtable.GetAppInstallDir = emu_GetAppInstallDir;
    emu_steamapps_vtable.BIsAppInstalled = emu_BIsAppInstalled;
    emu_steamapps_vtable.GetAppOwner = emu_GetAppOwner;
    emu_steamapps_vtable.GetLaunchQueryParam = emu_GetLaunchQueryParam;
    emu_steamapps_vtable.GetDlcDownloadProgress = emu_GetDlcDownloadProgress;
    emu_steamapps_vtable.GetAppBuildId = emu_GetAppBuildId;
    emu_steamapps_vtable.RequestAllProofOfPurchaseKeys = emu_RequestAllProofOfPurchaseKeys;
    emu_steamapps_ptr = &emu_steamapps_vtable;

    // -- Generic stub vtable for interfaces we don't have definitions for --
    // 256 slots of a function that returns 0 — safe to call, won't crash
    for (int i = 0; i < EMU_GENERIC_VTABLE_SLOTS; i++)
        emu_generic_vtable[i] = (void *)emu_generic_stub;
    for (int i = 0; i < EMU_NUM_GENERIC_PTRS; i++)
        emu_generic_ptrs[i] = emu_generic_vtable;

    // -- Build the fake context --
    memset(&emu_context, 0, sizeof(emu_context));
    emu_context.m_pSteamUser = &emu_steamuser_ptr;
    emu_context.m_pSteamFriends = &emu_steamfriends_ptr;
    emu_context.m_pSteamApps = &emu_steamapps_ptr;
    emu_context.m_pSteamClient          = &emu_generic_ptrs[0];
    emu_context.m_pSteamUtils           = &emu_generic_ptrs[1];
    emu_context.m_pSteamMatchmaking     = &emu_generic_ptrs[2];
    emu_context.m_pSteamUserStats       = &emu_generic_ptrs[3];
    emu_context.m_pSteamMatchmakingServers = &emu_generic_ptrs[4];
    emu_context.m_pSteamNetworking      = &emu_generic_ptrs[5];
    emu_context.m_pSteamRemoteStorage   = &emu_generic_ptrs[6];
    emu_context.m_pSteamScreenshots     = &emu_generic_ptrs[7];
    emu_context.m_pSteamHTTP            = &emu_generic_ptrs[8];
    emu_context.m_pSteamUnifiedMessages = &emu_generic_ptrs[9];
    emu_context.m_pController           = &emu_generic_ptrs[10];
    emu_context.m_pSteamUGC             = &emu_generic_ptrs[11];
    emu_context.m_pSteamAppList         = &emu_generic_ptrs[12];
    emu_context.m_pSteamMusic           = &emu_generic_ptrs[13];
    emu_context.m_pSteamMusicRemote     = &emu_generic_ptrs[14];
    emu_context.m_pSteamHTMLSurface     = &emu_generic_ptrs[15];
    emu_context.m_pSteamInventory       = &emu_generic_ptrs[16];
    emu_context.m_pSteamVideo           = &emu_generic_ptrs[17];

    printf("[BO3MacFix] Offline mode: Steam emulator initialized (player: %s)\n", emu_playername);
}

CSteamAPIContext *steam_emu_get_context(void) {
    return &emu_context;
}

// -- DYLD interpositions for Steam API entry points --------------------------
// These intercept calls to libsteam_api.dylib from the game binary.
// DYLD_INTERPOSE redirects other images' calls to us, but calls from within
// this dylib still reach the real implementation, so we can fall through.

extern bool SteamAPI_Init(void);
bool SteamAPI_Init_new(void) {
    if (check_offline()) return true;
    return SteamAPI_Init();
}
DYLD_INTERPOSE(SteamAPI_Init_new, SteamAPI_Init);

extern bool SteamAPI_RestartAppIfNecessary(uint32_t unOwnAppID);
bool SteamAPI_RestartAppIfNecessary_new(uint32_t unOwnAppID) {
    if (check_offline()) return false;
    return SteamAPI_RestartAppIfNecessary(unOwnAppID);
}
DYLD_INTERPOSE(SteamAPI_RestartAppIfNecessary_new, SteamAPI_RestartAppIfNecessary);

extern void SteamAPI_RunCallbacks(void);
void SteamAPI_RunCallbacks_new(void) {
    if (check_offline()) return;
    SteamAPI_RunCallbacks();
}
DYLD_INTERPOSE(SteamAPI_RunCallbacks_new, SteamAPI_RunCallbacks);

extern void SteamAPI_Shutdown(void);
void SteamAPI_Shutdown_new(void) {
    if (check_offline()) return;
    SteamAPI_Shutdown();
}
DYLD_INTERPOSE(SteamAPI_Shutdown_new, SteamAPI_Shutdown);

extern bool SteamAPI_IsSteamRunning(void);
bool SteamAPI_IsSteamRunning_new(void) {
    if (check_offline()) return true;
    return SteamAPI_IsSteamRunning();
}
DYLD_INTERPOSE(SteamAPI_IsSteamRunning_new, SteamAPI_IsSteamRunning);

extern void SteamAPI_RegisterCallback(CCallback *pCallback, int iCallback);
void SteamAPI_RegisterCallback_new(CCallback *pCallback, int iCallback) {
    if (check_offline()) return;
    SteamAPI_RegisterCallback(pCallback, iCallback);
}
DYLD_INTERPOSE(SteamAPI_RegisterCallback_new, SteamAPI_RegisterCallback);

extern void SteamAPI_UnregisterCallback(CCallback *pCallback);
void SteamAPI_UnregisterCallback_new(CCallback *pCallback) {
    if (check_offline()) return;
    SteamAPI_UnregisterCallback(pCallback);
}
DYLD_INTERPOSE(SteamAPI_UnregisterCallback_new, SteamAPI_UnregisterCallback);

extern void SteamAPI_RegisterCallResult(CCallResult *pCallback, SteamAPICall_t hAPICall);
void SteamAPI_RegisterCallResult_new(CCallResult *pCallback, SteamAPICall_t hAPICall) {
    if (check_offline()) return;
    SteamAPI_RegisterCallResult(pCallback, hAPICall);
}
DYLD_INTERPOSE(SteamAPI_RegisterCallResult_new, SteamAPI_RegisterCallResult);

extern void SteamAPI_UnregisterCallResult(CCallResult *pCallback, SteamAPICall_t hAPICall);
void SteamAPI_UnregisterCallResult_new(CCallResult *pCallback, SteamAPICall_t hAPICall) {
    if (check_offline()) return;
    SteamAPI_UnregisterCallResult(pCallback, hAPICall);
}
DYLD_INTERPOSE(SteamAPI_UnregisterCallResult_new, SteamAPI_UnregisterCallResult);

extern HSteamPipe SteamAPI_GetHSteamPipe(void);
HSteamPipe SteamAPI_GetHSteamPipe_new(void) {
    if (check_offline()) return 1;
    return SteamAPI_GetHSteamPipe();
}
DYLD_INTERPOSE(SteamAPI_GetHSteamPipe_new, SteamAPI_GetHSteamPipe);

extern HSteamUser SteamAPI_GetHSteamUser(void);
HSteamUser SteamAPI_GetHSteamUser_new(void) {
    if (check_offline()) return 1;
    return SteamAPI_GetHSteamUser();
}
DYLD_INTERPOSE(SteamAPI_GetHSteamUser_new, SteamAPI_GetHSteamUser);

extern void *SteamInternal_CreateInterface(const char *ver);
static int emu_createinterface_idx = 0;
void *SteamInternal_CreateInterface_new(const char *ver) {
    if (check_offline()) {
        int idx = emu_createinterface_idx++;
        if (idx >= EMU_NUM_GENERIC_PTRS) idx = EMU_NUM_GENERIC_PTRS - 1;
        return &emu_generic_ptrs[idx];
    }
    return SteamInternal_CreateInterface(ver);
}
DYLD_INTERPOSE(SteamInternal_CreateInterface_new, SteamInternal_CreateInterface);

extern bool SteamInternal_GameServer_Init(uint32_t unIP, uint16_t usSteamPort, uint16_t usGamePort, uint16_t usQueryPort, int eServerMode, const char *pchVersionString);
bool SteamInternal_GameServer_Init_new(uint32_t unIP, uint16_t usSteamPort, uint16_t usGamePort, uint16_t usQueryPort, int eServerMode, const char *pchVersionString) {
    if (check_offline()) return true;
    return SteamInternal_GameServer_Init(unIP, usSteamPort, usGamePort, usQueryPort, eServerMode, pchVersionString);
}
DYLD_INTERPOSE(SteamInternal_GameServer_Init_new, SteamInternal_GameServer_Init);

extern void SteamGameServer_RunCallbacks(void);
void SteamGameServer_RunCallbacks_new(void) {
    if (check_offline()) return;
    SteamGameServer_RunCallbacks();
}
DYLD_INTERPOSE(SteamGameServer_RunCallbacks_new, SteamGameServer_RunCallbacks);

extern void SteamGameServer_Shutdown(void);
void SteamGameServer_Shutdown_new(void) {
    if (check_offline()) return;
    SteamGameServer_Shutdown();
}
DYLD_INTERPOSE(SteamGameServer_Shutdown_new, SteamGameServer_Shutdown);

extern HSteamPipe SteamGameServer_GetHSteamPipe(void);
HSteamPipe SteamGameServer_GetHSteamPipe_new(void) {
    if (check_offline()) return 1;
    return SteamGameServer_GetHSteamPipe();
}
DYLD_INTERPOSE(SteamGameServer_GetHSteamPipe_new, SteamGameServer_GetHSteamPipe);

extern HSteamUser SteamGameServer_GetHSteamUser(void);
HSteamUser SteamGameServer_GetHSteamUser_new(void) {
    if (check_offline()) return 1;
    return SteamGameServer_GetHSteamUser();
}
DYLD_INTERPOSE(SteamGameServer_GetHSteamUser_new, SteamGameServer_GetHSteamUser);
