#include "sh_runtime_internal.h"

#include <string.h>

const char* sh_game_state_name(ShGameState state)
{
    static const char* const names[] = {
        "Init/Boot",
        "KonamiLogo",
        "KcetLogo",
        "MovieIntroFadeIn",
        "AutoLoadSavegame",
        "MovieIntroAlternate",
        "MovieIntro",
        "MainMenu",
        "LoadSavegameScreen",
        "MovieOpening",
        "MainLoadScreen",
        "InGame",
        "MapEvent",
        "ExitMovie",
        "InventoryScreen",
        "PaperMapScreen",
        "SaveScreen",
        "DebugMoviePlayer",
        "OptionScreen",
        "LoadStatusScreen",
        "LoadMapScreen",
        "Credits",
        "RemovedDebug"
    };
    uint32_t value = (uint32_t)state;

    if (value >= (uint32_t)(sizeof(names) / sizeof(names[0])))
    {
        return "Unknown";
    }

    return names[value];
}

const char* sh_sys_state_name(ShSysState state)
{
    static const char* const names[] = {
        "Gameplay",
        "OptionsMenu",
        "StatusMenu",
        "MapScreen",
        "Fmv",
        "LoadOverlay",
        "LoadRoom",
        "ReadMessage",
        "SaveMenu0",
        "SaveMenu1",
        "EventCallback",
        "EventSetFlag",
        "EventPlaySound",
        "GameOver",
        "GamePaused",
        "Invalid"
    };
    uint32_t value = (uint32_t)state;

    if (value >= (uint32_t)(sizeof(names) / sizeof(names[0])))
    {
        return "Unknown";
    }

    return names[value];
}

ShResult sh_runtime_game_enable_reference(ShRuntime* runtime)
{
    ShOverlayDescriptor descriptor = SH_OVERLAY_DESCRIPTOR_INIT;
    ShResult result;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!runtime->game.reference_registered)
    {
        descriptor.id = SH_REFERENCE_ENGINE_OVERLAY_ID;
        descriptor.slot = SH_OVERLAY_SLOT_ENGINE;
        descriptor.name = "BODYPROG_REFERENCE_HEADLESS";
        descriptor.init = sh_reference_game_overlay_init;
        descriptor.tick = sh_reference_game_overlay_tick;
        descriptor.shutdown = sh_reference_game_overlay_shutdown;
        descriptor.userdata = &runtime->game;

        result = sh_runtime_overlay_register(runtime, &descriptor);

        if (result != SH_RESULT_OK)
        {
            return result;
        }

        runtime->game.reference_registered = true;
    }

    result = sh_runtime_overlay_activate(
        runtime,
        SH_REFERENCE_ENGINE_OVERLAY_ID);

    if (result != SH_RESULT_OK)
    {
        if (runtime->game.reference_registered)
        {
            (void)sh_runtime_overlay_unregister(
                runtime,
                SH_REFERENCE_ENGINE_OVERLAY_ID);
            runtime->game.reference_registered = false;
        }

        return result;
    }

    return SH_RESULT_OK;
}

ShResult sh_runtime_game_disable_reference(ShRuntime* runtime)
{
    ShOverlayInfo active = SH_OVERLAY_INFO_INIT;
    ShResult result;

    if (runtime == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!runtime->game.reference_registered)
    {
        return SH_RESULT_OK;
    }

    result = sh_runtime_overlay_get_active(
        runtime,
        SH_OVERLAY_SLOT_ENGINE,
        &active);

    if (result == SH_RESULT_OK &&
        active.id == SH_REFERENCE_ENGINE_OVERLAY_ID)
    {
        result = sh_runtime_overlay_deactivate(
            runtime,
            SH_OVERLAY_SLOT_ENGINE);

        if (result != SH_RESULT_OK)
        {
            return result;
        }
    }
    else if (result != SH_RESULT_OK &&
             result != SH_RESULT_NOT_FOUND)
    {
        return result;
    }

    result = sh_runtime_overlay_unregister(
        runtime,
        SH_REFERENCE_ENGINE_OVERLAY_ID);

    if (result != SH_RESULT_OK)
    {
        return result;
    }

    runtime->game.reference_registered = false;
    runtime->game.snapshot.reference_enabled = false;
    return SH_RESULT_OK;
}

ShResult sh_runtime_game_set_boot_signals(
    ShRuntime* runtime,
    const ShGameBootSignals* signals)
{
    if (runtime == NULL || signals == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!runtime->game.snapshot.reference_enabled)
    {
        return SH_RESULT_INVALID_STATE;
    }

    if (!sh_runtime_size_is_supported(
            signals->struct_size,
            sizeof(ShGameBootSignals)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (signals->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    runtime->game.boot_signals = *signals;
    runtime->game.boot_signals.struct_size =
        (uint32_t)sizeof(ShGameBootSignals);
    runtime->game.boot_signals.abi_version =
        SH_ABI_VERSION_CURRENT;

    return SH_RESULT_OK;
}

ShResult sh_runtime_game_set_konami_signals(
    ShRuntime* runtime,
    const ShGameKonamiSignals* signals)
{
    if (runtime == NULL || signals == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!runtime->game.snapshot.reference_enabled)
    {
        return SH_RESULT_INVALID_STATE;
    }

    if (!sh_runtime_size_is_supported(
            signals->struct_size,
            sizeof(ShGameKonamiSignals)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (signals->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    runtime->game.konami_signals = *signals;
    runtime->game.konami_signals.struct_size =
        (uint32_t)sizeof(ShGameKonamiSignals);
    runtime->game.konami_signals.abi_version =
        SH_ABI_VERSION_CURRENT;

    return SH_RESULT_OK;
}

ShResult sh_runtime_game_get_snapshot(
    const ShRuntime* runtime,
    ShGameSnapshot* out_snapshot)
{
    if (runtime == NULL || out_snapshot == NULL)
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (!sh_runtime_is_ready(runtime))
    {
        return SH_RESULT_NOT_READY;
    }

    if (!sh_runtime_size_is_supported(
            out_snapshot->struct_size,
            sizeof(ShGameSnapshot)))
    {
        return SH_RESULT_INVALID_ARGUMENT;
    }

    if (out_snapshot->abi_version != SH_ABI_VERSION_CURRENT)
    {
        return SH_RESULT_UNSUPPORTED_VERSION;
    }

    memcpy(out_snapshot, &runtime->game.snapshot, sizeof(*out_snapshot));
    return SH_RESULT_OK;
}
