# updated at https://github.com/pushrate/esp8266_template
# Based on Makefile for ESP8266 projects
# https://github.com/esp8266/source-code-examples
#
# Thanks to:
# - zarya
# - Jeroen Domburg (Sprite_tm)
# - Christian Klippel (mamalala)
# - Tommie Gannert (tommie)
#
# Changelog:
# - 2017-07-08: Add support for debug stub, flash_flags, and compiling assembly files
# - 2014-10-06: Changed the variables to include the header file directory
# - 2014-10-06: Added global var for the Xtensa tool root
# - 2014-11-23: Updated for SDK 0.9.3
# - 2014-12-25: Replaced esptool by esptool.py

## Makefiles come with a bunch of rules built in, usually helpful, except when you
## are trying to debug at which point your rules become very insignificant.
## n.b. On debugging: Use --only-print to extract what exactly is being executed,
## --debug to see how the rules are nested and how dependancies are being resolved,
## and --trace to understand why things are being rebuilt.
MAKEFLAGS += --no-builtin-rules

# Output directory to store intermediate compiled files.
# They are relative to the project directory
BUILD_BASE = build
FW_BASE = firmware

# base directory of the ESP8266 SDK package, absolute
# default assumes ESP_HOME is your esp-open-sdk root directory
SDK_BASE ?= $(ESP_HOME)/sdk

# esptool.py details
ESPTOOL     ?= esptool.py
ESPPORT     ?= /dev/ttyUSB0
FLASH_FLAGS ?= --flash_mode qio --flash_size 4MB -ff 40m

# name for the target project, will effect naming of .out file
TARGET = example

## This makefile just assumes all .c and .s files in the MODULES directories are code that
## should be compiled into the final binary
# which modules (subdirectories) of the project to include in compiling
MODULES = app rboot

# allow some configuration headers to live at the repo root, as it is much easier to find them there
EXTRA_INCDIR = .

## this is all of the libs present in the espressif SDK except lwip_536
# libraries used in this project, mainly provided by the SDK

#https://github.com/raburton/rboot
# go to esp library folder, and weaken symbol as follows, creating main2 library
# xtensa-lx106-elf-objcopy -W Cache_Read_Enable_New libmain.a libmain_rboot.a

LIBS = c hal airkiss at crypto driver espnow gcc json lwip main_rboot mesh net80211 phy pp pwm smartconfig ssl upgrade wpa2 wpa wps

# compiler flags using during compilation of source files
#http://www.esp8266.com/viewtopic.php?t=231&p=1139
CFLAGS = -Wpointer-arith -Wundef -Werror -Wl,-EL -fno-inline-functions -nostdlib \
-mlongcalls -mtext-section-literals  -D__ets__ -DICACHE_FLASH

## from linker docs: -u symbol: force symbol to be entered in the output file as an undefined symbol.
LDFLAGS = -nostdlib -Wl,--no-check-sections -Wl,--gc-sections -u call_user_start -u Cache_Read_Enable_New -Wl,-static

## There is some interesting voodoo that I don't yet completely understand with the ld file, you can add a symbol pattern there
## to force the linker to put all matching objects in irom (flash). Instead, I use the GDBFN define to set all the gdbstub functions
## to default into flash which will allow us to link gdbstub in without overfilling ram
# Linker script defines where everything will go in memory
LD_SCRIPT = eagle.app.v6.ld

# If asked to build 'debug', add gdbstub directory to the build, and enable necessary debug cflags,
# if building in debug configuration, set define, and add gdbstub
ifeq ($(filter debug,$(MAKECMDGOALS)),debug)
MODULES += esp-gdbstub
CFLAGS  += -Og -ggdb -DDEBUG -DGDBSTUB_FREERTOS=0 -DATTR_GDBFN=ICACHE_FLASH_ATTR
else
#optimize for space
CFLAGS += -Os
endif

# various paths inside the espressif SDK that we'll be using in this project
SDK_LIBDIR = lib
SDK_LDDIR  = ld
SDK_INCDIR = include include/json driver_lib/include

## So there is a little mystery here, looking at many past examples file_2_addr used to be 0x40000
## but esptool now generates 0x10000. I found this reference to explain the change:
## https://github.com/pfalcon/esp-open-sdk/issues/226 which indicates that the ld script has changed.
## I think the implication is that there is much more irom space, but nothing is reserved for updates.

## Update: this might help clarify it all, file1 is a whole bunch of stuff, fronted by a header that
## describes its own layout (segments, see esptool image_info) that need to be loaded into ram at boot
## time by the builtin firmware, basically initializing iram, etc. 0x10000 is the irom, exactly as it
## will exist at 0x40210000.
# We create two different files for uploading into the flash.
FW_FILE_1_ADDR = 0x02000

# select which tools to use as compiler, librarian and linker
CC := xtensa-lx106-elf-gcc
AR := xtensa-lx106-elf-ar
LD := xtensa-lx106-elf-gcc

##
## From here down, deal with generic compile logic
##
SRC_DIR   := $(MODULES)
BUILD_DIR := $(addprefix $(BUILD_BASE)/,$(MODULES))

SDK_LIBDIR := $(addprefix $(SDK_BASE)/,$(SDK_LIBDIR))
SDK_INCDIR := $(addprefix -I$(SDK_BASE)/,$(SDK_INCDIR))

## Find and add each .s file in each module to SRC ( end up with "app/app.c esp-gdbstub/gdbstub-entry.S ...")
SRC := $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.c)) $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.S))
## Take each source file, prefix with build_base, and make them .o files, (end up with  "build/app/app.o build/esp-gdbstub/gdbstub-entry.o")
OBJ := $(patsubst %.S,$(BUILD_BASE)/%.o,$(patsubst %.c,$(BUILD_BASE)/%.o,$(SRC)))
## For each lib listed, turn them into compiler -l flags
LIBS := $(addprefix -l,$(LIBS))

## Generate the name for the combined file/lib
APP_AR := $(addprefix $(BUILD_BASE)/,$(TARGET)_app.a)
## Generate the elf executable name
TARGET_OUT := $(addprefix $(BUILD_BASE)/,$(TARGET).out)

# Again, turn the ld script into a linker flag
LD_SCRIPT := $(addprefix -T$,$(LD_SCRIPT))

# Generate include flags (module, module/include, and *EXTRA_INCDIR*)
INCDIR := $(addprefix -I,$(SRC_DIR))
EXTRA_INCDIR := $(addprefix -I,$(EXTRA_INCDIR))
MODULE_INCDIR := $(addsuffix /include,$(INCDIR))

FW_FILE_1 := $(addprefix $(FW_BASE)/,$(FW_FILE_1_ADDR).bin)

## Simple helper function that if in verbose mode provides extra information
V ?= $(VERBOSE)
ifeq ("$(V)","1")
Q :=
vecho := @true
else
Q := @
vecho := @echo
endif

## There are a bunch of ways to handle nested directories, but I found this pretty elegant, and I've
## never actually define functions in a makefile before, so seeing it done this way was really helpful

## Make rules are tested, but if the requirements aren't satisfied, then it just moves on to the next one that matches.
## Here I use that property to try and build the .o file from a .S file (if it exists)
define compile-objects
build/$1/%.o: $1/%.S
	$(vecho) "SCC $$<"
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS) -c $$< -o $$@

build/$1/%.o: $1/%.c
	$(vecho) "CC $$<"
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS) -c $$< -o $$@
endef

## .PHONY target is something I need to look up every time: basically it serves to tell Make that
## these targets aren't associated with an actual filesystem file
.PHONY: all checkdirs flash1 flash2 flash3 clean

all: checkdirs $(TARGET_OUT) $(FW_FILE_1)

## This was a bit of an oddity: if observing with just-print it will appeart to be run twice, but in practice it is only
## run once (I think). The rule would be matched for each of the firmware files, but the first invocation will generate both.
# esptool splits the elf file (example.out) into the two firmware files.
$(FW_BASE)/%.bin: $(TARGET_OUT) | $(FW_BASE)
	$(vecho) "FW $(FW_BASE)/"
	$(Q) $(ESPTOOL) elf2image --version=2 --checksum-irom $(TARGET_OUT) -o ./firmware/$(FW_FILE_1_ADDR).bin

## Call the linker: start-group end-group tells the linker to iterate through this set of libraries multiple time to resolve
## references. Otherwise it would only go through once, and items at the start of the list couldn't rely on
## those at the end
$(TARGET_OUT): $(APP_AR)
	$(vecho) "LD $@"
	$(Q) $(LD) -L$(SDK_LIBDIR) $(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(APP_AR) $(LIBS) -Wl,--end-group -o $@

$(APP_AR): $(OBJ)
	$(vecho) "AR $@"
	$(Q) $(AR) cru $@ $^

checkdirs: $(BUILD_DIR) $(FW_BASE)

$(BUILD_DIR):
	$(Q) mkdir -p $@

$(FW_BASE):
	$(Q) mkdir -p $@

debug: checkdirs $(TARGET_OUT) $(FW_FILE_1) $(FW_FILE_2)

## TODO: There is probably some utility in wiping/initializing memory areas that aren't program related (stored settings, etc)
flash1: $(FW_FILE_1)
	$(ESPTOOL) --port $(ESPPORT) write_flash $(FLASH_FLAGS) $(FW_FILE_1_ADDR) $(FW_FILE_1)

flash2: $(FW_FILE_1)
	$(ESPTOOL) --port $(ESPPORT) write_flash $(FLASH_FLAGS) 0x102000 $(FW_FILE_1)

flash3: $(FW_FILE_1)
	$(ESPTOOL) --port $(ESPPORT) write_flash $(FLASH_FLAGS) 0x202000 $(FW_FILE_1)

clean:
	$(Q) rm -rf $(FW_BASE) $(BUILD_BASE)

## Iterate through all the modules and create the compile rules for their contents
$(foreach bdir,$(SRC_DIR),$(eval $(call compile-objects,$(bdir))))
