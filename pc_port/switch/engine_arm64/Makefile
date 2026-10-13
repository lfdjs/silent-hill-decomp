# SPDX-License-Identifier: GPL-3.0-or-later
# Stage 14B.2: compile/link real Silent Hill original C modules into a Switch NRO.
.SUFFIXES:
ifeq ($(strip $(DEVKITPRO)),)
$(error DEVKITPRO missing; export DEVKITPRO=/opt/devkitpro)
endif
TOPDIR ?= $(CURDIR)
include $(DEVKITPRO)/libnx/switch_rules
TARGET := SHGameCoreArm64
BUILD := build
SOURCES := source
DATA := data
INCLUDES := include
APP_TITLE := Silent Hill ARM64 TIM Asset Viewer
APP_AUTHOR := Community Port Experiment
APP_VERSION := 0.3.0
ARCH := -march=armv8-a+crc+crypto -mtune=cortex-a57 -mtp=soft -fPIE
CFLAGS := -std=c11 -O2 -g -Wall -Wextra -ffunction-sections -fno-strict-aliasing -fwrapv $(ARCH) $(DEFINES)
# Match the desktop port's override include order, not the original Psy-Q SDK.
GAME_ROOT := $(abspath $(TOPDIR)/../../..)
CFLAGS += -D__SWITCH__ -DVER_USA -DSH_PC_PORT -DSKIP_ASM \
          -I$(GAME_ROOT)/pc_port/include \
          -I$(GAME_ROOT)/pc_port/include/psyq_compat \
          -I$(GAME_ROOT)/include \
          -I$(GAME_ROOT)/include/decomp \
          -I$(GAME_ROOT)/pc_port/PsyCross/include/psx \
          -I$(GAME_ROOT)/pc_port/PsyCross/include \
          $(INCLUDE)
CXXFLAGS := $(CFLAGS) -fno-rtti -fno-exceptions
ASFLAGS := -g $(ARCH)
LDFLAGS := -specs=$(DEVKITPRO)/libnx/switch.specs -g $(ARCH) -Wl,-Map,$(notdir $*.map)
LIBS := -lnx
LIBDIRS := $(PORTLIBS) $(LIBNX)
ifneq ($(BUILD),$(notdir $(CURDIR)))
export OUTPUT := $(CURDIR)/$(TARGET)
export TOPDIR := $(CURDIR)
export VPATH := $(foreach d,$(SOURCES),$(CURDIR)/$(d))
export DEPSDIR := $(CURDIR)/$(BUILD)
CFILES := $(foreach d,$(SOURCES),$(notdir $(wildcard $(d)/*.c)))
CPPFILES := $(foreach d,$(SOURCES),$(notdir $(wildcard $(d)/*.cpp)))
SFILES := $(foreach d,$(SOURCES),$(notdir $(wildcard $(d)/*.s)))
export LD := $(CC)
export OFILES := $(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
export INCLUDE := $(foreach d,$(INCLUDES),-I$(CURDIR)/$(d)) \
                  $(foreach d,$(LIBDIRS),-I$(d)/include) -I$(CURDIR)/$(BUILD)
export LIBPATHS := $(foreach d,$(LIBDIRS),-L$(d)/lib)
export NROFLAGS += --nacp=$(CURDIR)/$(TARGET).nacp \
                   --icon=$(DEVKITPRO)/libnx/default_icon.jpg
.PHONY: all clean
all: $(BUILD)
$(BUILD):
	@mkdir -p $@
	@$(MAKE) --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile
clean:
	@rm -rf $(BUILD) $(TARGET).elf $(TARGET).nro $(TARGET).nacp
else
.PHONY: all
DEPENDS := $(OFILES:.o=.d)
all: $(OUTPUT).nro
$(OUTPUT).nro: $(OUTPUT).elf $(OUTPUT).nacp
$(OUTPUT).elf: $(OFILES)
-include $(DEPENDS)
endif
