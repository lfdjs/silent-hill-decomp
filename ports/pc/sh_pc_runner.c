#define _POSIX_C_SOURCE 200809L

#include "sh_pc_app.h"

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <time.h>
#endif

#if defined(SH_PC_HAVE_X11)
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>
#endif

typedef struct ShPcWindow
{
    bool headless;
    bool exit_requested;
    ShInputButtons buttons;
    char state_label[96];
    unsigned int width;
    unsigned int height;
    bool logo_visible;
    bool interlaced;
    uint16_t logical_width;
#if defined(SH_PC_HAVE_X11)
    Display* display;
    Window window;
    GC gc;
    Atom wm_delete;
#endif
} ShPcWindow;

static bool parse_positive(const char* input, uint64_t* value)
{
    unsigned long long parsed;
    char* end = NULL;

    if (input == NULL || input[0] == '\0' || input[0] == '-')
    {
        return false;
    }
    errno = 0;
    parsed = strtoull(input, &end, 10);
    if (errno == ERANGE || end == input || *end != '\0' || parsed == 0ull)
    {
        return false;
    }
    *value = (uint64_t)parsed;
    return true;
}

static void sleep_frame(void)
{
#if defined(_WIN32)
    Sleep(16u);
#else
    struct timespec delay = {0, 16666667L};
    (void)nanosleep(&delay, NULL);
#endif
}

#if defined(SH_PC_HAVE_X11)
static ShInputButtons map_key(KeySym key)
{
    switch (key)
    {
        case XK_Up: case XK_w: case XK_W: return SH_INPUT_BUTTON_UP;
        case XK_Down: case XK_s: case XK_S: return SH_INPUT_BUTTON_DOWN;
        case XK_Left: case XK_a: case XK_A: return SH_INPUT_BUTTON_LEFT;
        case XK_Right: case XK_d: case XK_D: return SH_INPUT_BUTTON_RIGHT;
        case XK_Return: case XK_KP_Enter: return SH_INPUT_BUTTON_START;
        case XK_space: return SH_INPUT_BUTTON_CROSS;
        case XK_Shift_L: case XK_Shift_R: return SH_INPUT_BUTTON_R1;
        default: return 0u;
    }
}

static bool window_init(ShPcWindow* screen)
{
    int display_id;
    unsigned long black;

    screen->display = XOpenDisplay(NULL);
    if (screen->display == NULL)
    {
        return false;
    }
    display_id = DefaultScreen(screen->display);
    black = BlackPixel(screen->display, display_id);
    screen->window = XCreateSimpleWindow(screen->display,
        RootWindow(screen->display, display_id), 0, 0,
        screen->width, screen->height, 0, black, black);
    if (screen->window == 0)
    {
        XCloseDisplay(screen->display);
        screen->display = NULL;
        return false;
    }
    screen->gc = XCreateGC(screen->display, screen->window, 0, NULL);
    XSetForeground(screen->display, screen->gc,
        WhitePixel(screen->display, display_id));
    XSelectInput(screen->display, screen->window,
        ExposureMask | KeyPressMask | KeyReleaseMask | StructureNotifyMask);
    XStoreName(screen->display, screen->window,
        "Silent Hill - PC runtime diagnostic (not playable)");
    screen->wm_delete = XInternAtom(screen->display, "WM_DELETE_WINDOW", False);
    (void)XSetWMProtocols(screen->display, screen->window,
        &screen->wm_delete, 1);
    XMapWindow(screen->display, screen->window);
    XFlush(screen->display);
    return true;
}

static void window_poll(ShPcWindow* screen)
{
    while (XPending(screen->display) > 0)
    {
        XEvent event;
        XNextEvent(screen->display, &event);
        if (event.type == ClientMessage &&
            (Atom)event.xclient.data.l[0] == screen->wm_delete)
        {
            screen->exit_requested = true;
        }
        else if (event.type == DestroyNotify)
        {
            screen->exit_requested = true;
        }
        else if (event.type == ConfigureNotify)
        {
            screen->width = (unsigned int)event.xconfigure.width;
            screen->height = (unsigned int)event.xconfigure.height;
        }
        else if (event.type == KeyPress || event.type == KeyRelease)
        {
            KeySym key = XLookupKeysym(&event.xkey, 0);
            ShInputButtons button = map_key(key);
            if (key == XK_Escape && event.type == KeyPress)
            {
                screen->exit_requested = true;
            }
            if (event.type == KeyPress)
            {
                screen->buttons |= button;
            }
            else
            {
                screen->buttons &= ~button;
            }
        }
    }
}

static void window_draw(ShPcWindow* screen)
{
    const char* instructions = "ENTER / SPACE: skip logo | ESC: quit";
    const char* disclaimer = "Reference placeholders only - no original assets";
    int y = (int)(screen->height / 2u);
    XClearWindow(screen->display, screen->window);
    XDrawString(screen->display, screen->window, screen->gc,
        24, 50, "SILENT HILL - PORTABLE DIAGNOSTIC", 33);
    XDrawString(screen->display, screen->window, screen->gc,
        24, 90, screen->state_label, (int)strlen(screen->state_label));
    if (screen->logo_visible)
    {
        const char* logo = "[KONAMI LOGO: ASSET NOT LOADED]";
        XDrawString(screen->display, screen->window, screen->gc,
            24, y, logo, (int)strlen(logo));
    }
    XDrawString(screen->display, screen->window, screen->gc,
        24, y + 60, instructions, (int)strlen(instructions));
    XDrawString(screen->display, screen->window, screen->gc,
        24, y + 90, disclaimer, (int)strlen(disclaimer));
    XFlush(screen->display);
}

static void window_destroy(ShPcWindow* screen)
{
    if (screen->display != NULL)
    {
        XFreeGC(screen->display, screen->gc);
        XDestroyWindow(screen->display, screen->window);
        XCloseDisplay(screen->display);
        screen->display = NULL;
    }
}
#endif

static void video_sink(void* userdata, const ShPresentationCommand* command)
{
    ShPcWindow* screen = (ShPcWindow*)userdata;
    switch (command->type)
    {
        case SH_PRESENTATION_COMMAND_CONFIGURE_DISPLAY:
            screen->logical_width = command->width;
            screen->interlaced = command->interlaced;
            break;
        case SH_PRESENTATION_COMMAND_DRAW_BOOT_LOGO:
            screen->logo_visible = true;
            break;
        case SH_PRESENTATION_COMMAND_PRESENT_FRAME:
#if defined(SH_PC_HAVE_X11)
            if (!screen->headless)
            {
                window_draw(screen);
            }
#endif
            break;
        default:
            break;
    }
}

static void audio_sink(void* userdata, const ShAudioCommand* command)
{
    (void)userdata;
    if (command->type == SH_AUDIO_COMMAND_TASK)
    {
        printf("Audio task observed: %u (no SPU playback)\n",
            (unsigned int)command->task_id);
    }
}

int main(int argc, char** argv)
{
    ShPcApp app;
    ShPcWindow screen;
    ShResult result;
    uint64_t max_ticks = UINT64_C(600);
    bool fast = false;
    bool headless = false;
    int idx;

    for (idx = 1; idx < argc; idx++)
    {
        if (strcmp(argv[idx], "--headless") == 0)
        {
            headless = true;
        }
        else if (strcmp(argv[idx], "--fast") == 0)
        {
            fast = true;
        }
        else if (strcmp(argv[idx], "--max-ticks") == 0 && idx + 1 < argc)
        {
            if (!parse_positive(argv[++idx], &max_ticks))
            {
                fputs("invalid --max-ticks value\n", stderr);
                return EXIT_FAILURE;
            }
        }
        else
        {
            fprintf(stderr,
                "usage: %s [--headless] [--fast] [--max-ticks N]\n", argv[0]);
            return EXIT_FAILURE;
        }
    }

    memset(&screen, 0, sizeof(screen));
    screen.headless = headless;
    screen.width = 640u;
    screen.height = 480u;

#if defined(SH_PC_HAVE_X11)
    if (!headless && !window_init(&screen))
    {
        fputs("X11 display unavailable; use --headless\n", stderr);
        return EXIT_FAILURE;
    }
#else
    if (!headless)
    {
        fputs("X11 backend not built; use --headless\n", stderr);
        return EXIT_FAILURE;
    }
#endif

    result = sh_pc_app_init(&app, video_sink, audio_sink, &screen);
    if (result != SH_RESULT_OK)
    {
        fprintf(stderr, "PC runtime init: %s\n", sh_result_string(result));
#if defined(SH_PC_HAVE_X11)
        if (!headless) window_destroy(&screen);
#endif
        return EXIT_FAILURE;
    }

    printf("Silent Hill PC diagnostic ABI %s\n", SH_VERSION_STRING);
    printf("Backend: %s\n", headless ? "headless" : "X11");
    puts("NOTE: diagnostic placeholders; no original graphics/audio/gameplay");

    while (app.ticks < max_ticks && !screen.exit_requested)
    {
        ShGameState before = app.snapshot.state;
#if defined(SH_PC_HAVE_X11)
        if (!headless)
        {
            window_poll(&screen);
            if (screen.exit_requested) break;
        }
#endif
        result = sh_pc_app_tick(&app, screen.buttons);
        if (result != SH_RESULT_OK)
        {
            fprintf(stderr, "PC tick: %s\n", sh_result_string(result));
            break;
        }
        (void)snprintf(screen.state_label, sizeof(screen.state_label),
            "State: %s | tick: %" PRIu64,
            sh_game_state_name(app.snapshot.state), app.ticks);
        if (app.snapshot.state != before)
        {
            printf("State transition: %s -> %s (tick=%" PRIu64 ")\n",
                sh_game_state_name(before),
                sh_game_state_name(app.snapshot.state), app.ticks);
        }
        if (app.reached_unsupported)
        {
            printf("Reached unsupported state: %s\n",
                sh_game_state_name(app.snapshot.state));
            break;
        }
        if (!fast)
        {
            sleep_frame();
        }
    }

    printf("PC summary: ticks=%" PRIu64 " frames=%" PRIu64
           " video=%" PRIu64 " audio=%" PRIu64
           " task160=%" PRIu64 " task162=%" PRIu64 "\n",
           app.ticks, app.frames, app.video_commands,
           app.audio_commands, app.audio_160_count, app.audio_162_count);

    sh_pc_app_destroy(&app);
#if defined(SH_PC_HAVE_X11)
    if (!headless) window_destroy(&screen);
#endif
    return result == SH_RESULT_OK ? EXIT_SUCCESS : EXIT_FAILURE;
}
