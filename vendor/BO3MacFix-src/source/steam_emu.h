#ifndef STEAM_EMU_H_
#define STEAM_EMU_H_

#include <stdbool.h>
#include "steam/CSteamAPIContext.h"

extern bool offline_mode;

void steam_emu_init(void);
CSteamAPIContext *steam_emu_get_context(void);

#endif // STEAM_EMU_H_
