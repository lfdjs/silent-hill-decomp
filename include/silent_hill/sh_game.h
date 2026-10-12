#ifndef SILENT_HILL_SH_GAME_H
#define SILENT_HILL_SH_GAME_H

#include "silent_hill/sh_result.h"
#include "silent_hill/sh_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SH_REFERENCE_ENGINE_OVERLAY_ID UINT32_C(0x53480001)

typedef enum ShGameState
{
    SH_GAME_STATE_INIT = 0,
    SH_GAME_STATE_BOOT = SH_GAME_STATE_INIT,
    SH_GAME_STATE_KONAMI_LOGO = 1,
    SH_GAME_STATE_KCET_LOGO = 2,
    SH_GAME_STATE_MOVIE_INTRO_FADE_IN = 3,
    SH_GAME_STATE_AUTO_LOAD_SAVEGAME = 4,
    SH_GAME_STATE_MOVIE_INTRO_ALTERNATE = 5,
    SH_GAME_STATE_MOVIE_INTRO = 6,
    SH_GAME_STATE_MAIN_MENU = 7,
    SH_GAME_STATE_LOAD_SAVEGAME_SCREEN = 8,
    SH_GAME_STATE_MOVIE_OPENING = 9,
    SH_GAME_STATE_MAIN_LOAD_SCREEN = 10,
    SH_GAME_STATE_IN_GAME = 11,
    SH_GAME_STATE_MAP_EVENT = 12,
    SH_GAME_STATE_EXIT_MOVIE = 13,
    SH_GAME_STATE_INVENTORY_SCREEN = 14,
    SH_GAME_STATE_PAPER_MAP_SCREEN = 15,
    SH_GAME_STATE_SAVE_SCREEN = 16,
    SH_GAME_STATE_DEBUG_MOVIE_PLAYER = 17,
    SH_GAME_STATE_OPTION_SCREEN = 18,
    SH_GAME_STATE_LOAD_STATUS_SCREEN = 19,
    SH_GAME_STATE_LOAD_MAP_SCREEN = 20,
    SH_GAME_STATE_CREDITS = 21,
    SH_GAME_STATE_REMOVED_DEBUG = 22
} ShGameState;

typedef enum ShSysState
{
    SH_SYS_STATE_GAMEPLAY = 0,
    SH_SYS_STATE_OPTIONS_MENU = 1,
    SH_SYS_STATE_STATUS_MENU = 2,
    SH_SYS_STATE_MAP_SCREEN = 3,
    SH_SYS_STATE_FMV = 4,
    SH_SYS_STATE_LOAD_OVERLAY = 5,
    SH_SYS_STATE_LOAD_ROOM = 6,
    SH_SYS_STATE_READ_MESSAGE = 7,
    SH_SYS_STATE_SAVE_MENU_0 = 8,
    SH_SYS_STATE_SAVE_MENU_1 = 9,
    SH_SYS_STATE_EVENT_CALLBACK = 10,
    SH_SYS_STATE_EVENT_SET_FLAG = 11,
    SH_SYS_STATE_EVENT_PLAY_SOUND = 12,
    SH_SYS_STATE_GAME_OVER = 13,
    SH_SYS_STATE_GAME_PAUSED = 14,
    SH_SYS_STATE_INVALID = 15
} ShSysState;

typedef uint32_t ShGameActions;

#define SH_GAME_ACTION_NONE UINT32_C(0)
#define SH_GAME_ACTION_SCREEN_INIT (UINT32_C(1) << 0u)
#define SH_GAME_ACTION_AUDIO_TASK (UINT32_C(1) << 1u)
#define SH_GAME_ACTION_QUEUE_BOOT_ASSETS (UINT32_C(1) << 2u)
#define SH_GAME_ACTION_START_FADE (UINT32_C(1) << 3u)
#define SH_GAME_ACTION_WAIT_AUDIO (UINT32_C(1) << 4u)
#define SH_GAME_ACTION_WAIT_FADE_OR_FILES (UINT32_C(1) << 5u)
#define SH_GAME_ACTION_STATE_TRANSITION (UINT32_C(1) << 6u)
#define SH_GAME_ACTION_UNIMPLEMENTED_STATE (UINT32_C(1) << 7u)
#define SH_GAME_ACTION_QUEUE_KONAMI_ASSETS (UINT32_C(1) << 8u)
#define SH_GAME_ACTION_DRAW_BOOT_LOGO (UINT32_C(1) << 9u)
#define SH_GAME_ACTION_PRESENT_FRAME (UINT32_C(1) << 10u)
#define SH_GAME_ACTION_WAIT_FADE_NONE (UINT32_C(1) << 11u)
#define SH_GAME_ACTION_WAIT_LOGO_DELAY (UINT32_C(1) << 12u)
#define SH_GAME_ACTION_WAIT_FILE_QUEUE (UINT32_C(1) << 13u)
#define SH_GAME_ACTION_QUEUE_KCET_ASSETS (UINT32_C(1) << 14u)
#define SH_GAME_ACTION_CHECK_MEMORY_CARD (UINT32_C(1) << 15u)
#define SH_GAME_ACTION_QUEUE_STREAM_ASSETS (UINT32_C(1) << 16u)
#define SH_GAME_ACTION_RESTORE_SETTINGS (UINT32_C(1) << 17u)
#define SH_GAME_ACTION_SELECT_INTRO_ROUTE (UINT32_C(1) << 18u)
#define SH_GAME_ACTION_UNSUPPORTED_SAVE_LOAD (UINT32_C(1) << 19u)

typedef struct ShGameBootSignals
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool audio_streaming_idle;
    bool fade_finished;
    bool file_queue_empty;
} ShGameBootSignals;

#define SH_GAME_BOOT_SIGNALS_INIT \
    { \
        (uint32_t)sizeof(ShGameBootSignals), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        false, \
        false \
    }

typedef struct ShGameKonamiSignals
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool fade_none;
    bool fade_finished;
    bool file_queue_empty;
    bool any_input;
} ShGameKonamiSignals;

#define SH_GAME_KONAMI_SIGNALS_INIT \
    { \
        (uint32_t)sizeof(ShGameKonamiSignals), \
        SH_ABI_VERSION_CURRENT, \
        false, \
        false, \
        false, \
        false \
    }

/* The host supplies a tested memory-card outcome; this is not a PS1
 * memory-card emulator. Numeric values deliberately do not alias the
 * original SavegameEntryType values. */
typedef enum ShKcetCardRoute
{
    SH_KCET_CARD_WAIT = 0,
    SH_KCET_CARD_NO_CARD = 1,
    SH_KCET_CARD_NO_SPACE = 2,
    SH_KCET_CARD_NO_SAVE = 3,
    SH_KCET_CARD_HAS_SAVE = 4
} ShKcetCardRoute;

typedef struct ShGameKcetSignals
{
    uint32_t struct_size;
    uint32_t abi_version;
    bool fade_none;
    bool fade_finished;
    bool file_queue_empty;
    bool any_input;
    ShKcetCardRoute card_route;
} ShGameKcetSignals;

#define SH_GAME_KCET_SIGNALS_INIT \
    { \
        (uint32_t)sizeof(ShGameKcetSignals), \
        SH_ABI_VERSION_CURRENT, \
        false, false, false, false, SH_KCET_CARD_WAIT \
    }

typedef struct ShGameSnapshot
{
    uint32_t struct_size;
    uint32_t abi_version;
    ShGameState previous_state;
    ShGameState state;
    uint32_t state_steps[3];
    ShSysState sys_state;
    uint64_t last_tick_index;
    uint64_t state_tick_count;
    uint64_t transition_count;
    ShGameActions last_actions;
    uint16_t last_audio_task_id;
    bool reference_enabled;
    bool state_implemented;
} ShGameSnapshot;

#define SH_GAME_SNAPSHOT_INIT \
    { \
        (uint32_t)sizeof(ShGameSnapshot), \
        SH_ABI_VERSION_CURRENT, \
        SH_GAME_STATE_INIT, \
        SH_GAME_STATE_INIT, \
        { 0u, 0u, 0u }, \
        SH_SYS_STATE_GAMEPLAY, \
        0u, \
        0u, \
        0u, \
        SH_GAME_ACTION_NONE, \
        0u, \
        false, \
        true \
    }

SH_API const char* sh_game_state_name(ShGameState state);
SH_API const char* sh_sys_state_name(ShSysState state);

SH_API ShResult sh_runtime_game_enable_reference(
    ShRuntime* runtime);

SH_API ShResult sh_runtime_game_disable_reference(
    ShRuntime* runtime);

SH_API ShResult sh_runtime_game_set_boot_signals(
    ShRuntime* runtime,
    const ShGameBootSignals* signals);

SH_API ShResult sh_runtime_game_set_konami_signals(
    ShRuntime* runtime,
    const ShGameKonamiSignals* signals);

/* Opt-in: KCET remains unsupported until a host explicitly supplies
 * KCET signals. The default diagnostic/legacy trace is unchanged. */
SH_API ShResult sh_runtime_game_set_kcet_signals(
    ShRuntime* runtime,
    const ShGameKcetSignals* signals);

SH_API ShResult sh_runtime_game_get_snapshot(
    const ShRuntime* runtime,
    ShGameSnapshot* out_snapshot);

#ifdef __cplusplus
}
#endif

#endif
