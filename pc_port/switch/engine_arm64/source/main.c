/* SPDX-License-Identifier: GPL-3.0-or-later
 * Stage 14B.2 — original game core functions plus PS1 TIM data on ARM64.
 * The TIM decoder originated in our portability/core-api Stage 12A.
 * Graphics use the libnx framebuffer previously validated in Ryubing.
 * This is NOT a complete game engine, 3D GPU, PsyCross integration, or gameplay.
 */
#include <switch.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <string.h>
#include <sys/stat.h>

#include "game_core_bridge.h"
#include "sh_tim.h"

#define WIDTH 1280u
#define HEIGHT 720u
#define LOG_PATH "sdmc:/switch/SilentHillSwitch/engine14b2.log"
#define GAME_DIR "sdmc:/switch/SilentHillSwitch/gamedata/"

static FILE* s_log;
static void log_line(const char* s)
{
    if (s_log) { fprintf(s_log, "%s\n", s); fflush(s_log); }
}

static int test_real_rng(void)
{
    uint32_t first;
    int32_t second;
    uint16_t third;
    ShGameCore_Rng_SetSeed(UINT32_C(0x12345678));
    first = ShGameCore_Rng_Rand32();
    second = ShGameCore_Rng_Rand16();
    third = ShGameCore_Rng_Rand12();
    return first == UINT32_C(0x75432777) && second == 26264 &&
           third == 605u && ShGameCore_Rng_GetSeed() == UINT32_C(0x25DBFAC1);
}

static int test_real_memmove(void)
{
    uint32_t buf[6] = {1u,2u,3u,4u,5u,6u};
    ShGameCore_Mem_Move32(buf+1,buf,4*(int32_t)sizeof(uint32_t));
    if (buf[0]!=1u || buf[1]!=1u || buf[2]!=2u ||
        buf[3]!=3u || buf[4]!=4u || buf[5]!=6u) return 0;
    ShGameCore_Mem_Move32(buf,buf+1,4*(int32_t)sizeof(uint32_t));
    return buf[0]==1u && buf[1]==2u && buf[2]==3u &&
           buf[3]==4u && buf[4]==4u && buf[5]==6u;
}

static const char* const k_tim_names[] = {
    "KONAMI.TIM", "KONAMI2.TIM", "DEMO.TIM"
};

static int load_game_tim(ShTimImage* img, char* chosen, size_t cap)
{
    size_t i;
    char path[256];
    for (i=0u;i<sizeof(k_tim_names)/sizeof(k_tim_names[0]);i++) {
        snprintf(path,sizeof(path),"%s%s",GAME_DIR,k_tim_names[i]);
        if (sh_tim_load_file(path,img)==0) {
            snprintf(chosen,cap,"%s",k_tim_names[i]);
            return 1;
        }
    }
    snprintf(chosen,cap,"none");
    return 0;
}

/* Use rgba values via libnx API, not TIM decoder pixel word layout. */
static u32 pixel_from_tim(uint32_t argb)
{
    uint8_t r=(uint8_t)(argb>>16u);
    uint8_t g=(uint8_t)(argb>>8u);
    uint8_t b=(uint8_t)argb;
    return RGBA8_MAXALPHA(r,g,b);
}

static void draw(u32* fb, u32 stride, uint64_t frame, const ShTimImage* img,
                 int show_image, int rng_ok, int mem_ok, int sd_ok)
{
    u32 x,y;
    const u32 square_x=(u32)((frame*7u)%(WIDTH-65u));
    u32 dw=0,dh=0,left=0,top=0;
    static uint16_t xmap[900];
    static uint16_t ymap[590];
    if (img && img->pixels && show_image) {
        const u32 max_w=900u,max_h=590u;
        if ((uint64_t)img->width*max_h > (uint64_t)img->height*max_w) {
            dw=max_w;
            dh=(u32)((uint64_t)img->height*max_w/img->width);
        } else {
            dh=max_h;
            dw=(u32)((uint64_t)img->width*max_h/img->height);
        }
        if (dw==0u) dw=1u;
        if (dh==0u) dh=1u;
        left=(WIDTH-dw)/2u;
        top=75u+(590u-dh)/2u;
        for (x=0u;x<dw;x++) xmap[x]=(uint16_t)((uint64_t)x*img->width/dw);
        for (y=0u;y<dh;y++) ymap[y]=(uint16_t)((uint64_t)y*img->height/dh);
    }
    for (y=0u;y<HEIGHT;y++) {
        u32* row=fb+(size_t)y*stride;
        for (x=0u;x<WIDTH;x++) {
            u32 c=RGBA8_MAXALPHA(15,22,35);
            if (y<62u) c=RGBA8_MAXALPHA(24,67,173);
            else if (y>=680u) {
                if (x<WIDTH/3u)
                    c=rng_ok?RGBA8_MAXALPHA(28,160,90):RGBA8_MAXALPHA(190,55,55);
                else if (x<2u*WIDTH/3u)
                    c=mem_ok?RGBA8_MAXALPHA(28,160,90):RGBA8_MAXALPHA(190,55,55);
                else
                    c=sd_ok?RGBA8_MAXALPHA(28,160,90):RGBA8_MAXALPHA(190,55,55);
            }
            if (img && img->pixels && show_image &&
                y>=top && y<top+dh && x>=left && x<left+dw) {
                u32 ix=xmap[x-left];
                u32 iy=ymap[y-top];
                uint32_t argb=img->pixels[(size_t)iy*img->width+ix];
                if ((argb>>24u)!=0u) c=pixel_from_tim(argb);
            }
            else if ((!img || !img->pixels || !show_image) &&
                     y>=126u && y<610u) {
                if (y<240u) c=RGBA8_MAXALPHA(33,76,153);
                else if (y<350u) c=RGBA8_MAXALPHA(34,158,101);
                else if (y<470u) c=RGBA8_MAXALPHA(191,153,45);
                else c=RGBA8_MAXALPHA(81,90,108);
            }
            if (y>=9u && y<53u && x>=square_x && x<square_x+44u)
                c=RGBA8_MAXALPHA(255,255,255);
            row[x]=c;
        }
    }
}

int main(int argc, char** argv)
{
    NWindow* window;
    Framebuffer fb;
    PadState pad;
    ShTimImage image={0};
    Result mount;
    int rng_ok,mem_ok,sd_ok,tim_ok,show_image;
    uint64_t frames=0;
    char chosen[64],msg[256];
    (void)argc; (void)argv;

    mount=fsdevMountSdmc();
    (void)mkdir("sdmc:/switch",0777);
    (void)mkdir("sdmc:/switch/SilentHillSwitch",0777);
    s_log=fopen(LOG_PATH,"w");
    sd_ok=s_log!=NULL;
    snprintf(msg,sizeof(msg),"BEGIN Stage14B.2 mount=0x%08" PRIX32 " writable=%s",
             (uint32_t)mount,sd_ok?"yes":"no");
    log_line(msg);
    rng_ok=test_real_rng();
    mem_ok=test_real_memmove();
    snprintf(msg,sizeof(msg),"GAME-RNG src/main/rng.c result=%s",rng_ok?"PASS":"FAIL");
    log_line(msg);
    snprintf(msg,sizeof(msg),"GAME-MEMMOVE src/main/memmove32.c result=%s",mem_ok?"PASS":"FAIL");
    log_line(msg);

    tim_ok=load_game_tim(&image,chosen,sizeof(chosen));
    show_image=tim_ok;
    snprintf(msg,sizeof(msg),"GAME-TIM file=%s result=%s width=%" PRIu32 " height=%" PRIu32 " bpp=%" PRIu32,
             chosen,tim_ok?"PASS":"NOT_FOUND",image.width,image.height,image.bits_per_pixel);
    log_line(msg);
    if (!tim_ok) log_line("GAME-TIM: place legally extracted KONAMI.TIM under sdmc:/switch/SilentHillSwitch/gamedata/ or use bundled DEMO.TIM");

    window=nwindowGetDefault();
    if (!window) {
        log_line("ERROR nwindowGetDefault failed");
        sh_tim_image_free(&image);
        if (s_log) fclose(s_log);
        return 2;
    }
    framebufferCreate(&fb,window,WIDTH,HEIGHT,PIXEL_FORMAT_RGBA_8888,2);
    framebufferMakeLinear(&fb);
    padConfigureInput(1,HidNpadStyleSet_NpadStandard);
    padInitializeDefault(&pad);
    log_line("DISPLAY framebuffer ready; PLUS exits, A toggles TIM/diagnostic");

    while (appletMainLoop()) {
        u32 stride_bytes=0;
        u32* pixels;
        u64 down;
        padUpdate(&pad);
        down=padGetButtonsDown(&pad);
        if ((down&HidNpadButton_Plus)!=0u) break;
        if ((down&HidNpadButton_A)!=0u) {
            show_image=!show_image;
            log_line(show_image?"INPUT A show TIM":"INPUT A show diagnostic bands");
        }
        pixels=(u32*)framebufferBegin(&fb,&stride_bytes);
        if (!pixels||stride_bytes<WIDTH*sizeof(u32)) {
            log_line("ERROR framebufferBegin invalid buffer");
            break;
        }
        draw(pixels,stride_bytes/sizeof(u32),frames,&image,show_image,rng_ok,mem_ok,sd_ok);
        framebufferEnd(&fb);
        ++frames;
        if (frames==1u) log_line("FRAME first framebufferEnd complete");
        if (frames%180u==0u) {
            snprintf(msg,sizeof(msg),"HEARTBEAT frames=%" PRIu64 " rng=%d mem=%d sd=%d tim=%d shown=%d",
                     frames,rng_ok,mem_ok,sd_ok,tim_ok,show_image);
            log_line(msg);
        }
    }
    snprintf(msg,sizeof(msg),"END frames=%" PRIu64,frames);
    log_line(msg);
    framebufferClose(&fb);
    sh_tim_image_free(&image);
    if (s_log) fclose(s_log);
    return (frames>0u && rng_ok && mem_ok && sd_ok && tim_ok)?0:1;
}
