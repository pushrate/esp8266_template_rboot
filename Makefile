# Makefile for ESP8266 projects
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


## Makefiles come with a bunch of rules built in, usually helpful, except when you are trying to debug
## at which point your rules become very insignificant
##
## n.b. On debugging: Use --only-print to extract what exactly is being executed, --debug to see how the rules are nested and how dependancies are being resolved, and --trace to understand why things are being rebuilt.
MAKEFLAGS += --no-builtin-rules

## Output directors to store intermediate compiled files
## relative to the project directory
BUILD_BASE	= build
FW_BASE		= firmware

## base directory of the ESP8266 SDK package, absolute
## default assumes ESP_HOME is your esp-open-sdk root directory
SDK_BASE	?= $(ESP_HOME)/sdk

## esptool.py path and port
ESPTOOL		?= esptool.py
ESPPORT		?= /dev/ttyUSB0
FLASH_FLAGS     ?= --flash_mode qio --flash_size 4MB -ff 40m

# name for the target project
TARGET		= example

# which modules (subdirectories) of the project to include in compiling
MODULES		= app uart

# allow some configuration headers to live at the repo root, as it is much easier to find them there
EXTRA_INCDIR    = .

# libraries used in this project, mainly provided by the SDK
LIBS		= c gcc hal pp phy net80211 lwip wpa main crypto json upgrade ssl wps smartconfig airkiss at

# compiler flags using during compilation of source files
#http://www.esp8266.com/viewtopic.php?t=231&p=1139
CFLAGS		= -Wpointer-arith -Wundef -Werror -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mtext-section-literals  -D__ets__ -DICACHE_FLASH

# linker flags used to generate the main object file
LDFLAGS		= -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static 

# linker script used for the above linkier step
LD_SCRIPT	= eagle.app.v6.ld

# If asked to build 'debug', add gdbstub directory to the build, and enable necessary debug cflags
# if building in debug configuration, set define, and add gdbstub
ifeq ($(filter debug,$(MAKECMDGOALS)),debug)
MODULES += esp-gdbstub
CFLAGS  += -Og -ggdb -DDEBUG -DGDBSTUB_FREERTOS=0
else
#optimize for space
CFLAGS += -Os
endif

# various paths inside the espressif SDK that we'll be using in this project
SDK_LIBDIR	= lib
SDK_LDDIR	= ld
SDK_INCDIR	= include include/json

# we create two different files for uploading into the flash
# these are the names and options to generate them
# So there is a little mystery here, looking at many past examples file_2_addr used to be 0x40000
# but esptool now generates 0x10000. I found this reference to explain the change:
# https://github.com/pfalcon/esp-open-sdk/issues/226 which indicates that the ld script has changed.
# Why and what the implication is, I'm not sure, 
FW_FILE_1_ADDR	= 0x00000
FW_FILE_2_ADDR	= 0x10000

# select which tools to use as compiler, librarian and linker
CC		:= xtensa-lx106-elf-gcc
AR		:= xtensa-lx106-elf-ar
LD		:= xtensa-lx106-elf-gcc


####
#### no user configurable options below here
####
SRC_DIR		:= $(MODULES)
BUILD_DIR	:= $(addprefix $(BUILD_BASE)/,$(MODULES))

SDK_LIBDIR	:= $(addprefix $(SDK_BASE)/,$(SDK_LIBDIR))
SDK_INCDIR	:= $(addprefix -I$(SDK_BASE)/,$(SDK_INCDIR))

SRC		:= $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.c)) $(foreach sdir,$(SRC_DIR),$(wildcard $(sdir)/*.S))
OBJ		:= $(patsubst %.S,$(BUILD_BASE)/%.o,$(patsubst %.c,$(BUILD_BASE)/%.o,$(SRC)))
LIBS		:= $(addprefix -l,$(LIBS))
APP_AR		:= $(addprefix $(BUILD_BASE)/,$(TARGET)_app.a)
TARGET_OUT	:= $(addprefix $(BUILD_BASE)/,$(TARGET).out)

LD_SCRIPT	:= $(addprefix -T$(SDK_BASE)/$(SDK_LDDIR)/,$(LD_SCRIPT))

INCDIR	:= $(addprefix -I,$(SRC_DIR))
EXTRA_INCDIR	:= $(addprefix -I,$(EXTRA_INCDIR))
MODULE_INCDIR	:= $(addsuffix /include,$(INCDIR))

FW_FILE_1	:= $(addprefix $(FW_BASE)/,$(FW_FILE_1_ADDR).bin)
FW_FILE_2	:= $(addprefix $(FW_BASE)/,$(FW_FILE_2_ADDR).bin)

V ?= $(VERBOSE)
ifeq ("$(V)","1")
Q :=
vecho := @true
else
Q := @
vecho := @echo
endif

vpath %.c $(SRC_DIR)

# There are a bunch of ways to handle nested directories, but I found this pretty elegant, and I've
# never actually define functions in a makefile before, so seeing it done this way was really helpful

define compile-objects
# Rules are tested, but if the requirements aren't satisfied, then it just moves on to the next one that matches.
# Here I use that property to try and build the .o file from a .S file (if it exists)

build/$1/%.o: $1/%.S
	$(vecho) "SCC $$<"
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS) -c $$< -o $$@

build/$1/%.o: $1/%.c
	$(vecho) "CC $$<"
	$(Q) $(CC) $(INCDIR) $(MODULE_INCDIR) $(EXTRA_INCDIR) $(SDK_INCDIR) $(CFLAGS) -c $$< -o $$@
endef

# .PHONY target is something I need to look up every time: basically it serves to tell Make that
# these targets aren't associated with an actual filesystem file
.PHONY: all checkdirs flash clean

all: checkdirs $(TARGET_OUT) $(FW_FILE_1) $(FW_FILE_2)

$(FW_BASE)/%.bin: $(TARGET_OUT) | $(FW_BASE)
	$(vecho) "FW $(FW_BASE)/"
	$(Q) $(ESPTOOL) elf2image -o $(FW_BASE)/ $(TARGET_OUT)

$(TARGET_OUT): $(APP_AR)
	$(vecho) "LD $@"
	$(Q) $(LD) -L$(SDK_LIBDIR) $(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(LIBS) $(APP_AR) -Wl,--end-group -o $@

$(APP_AR): $(OBJ)
	$(vecho) "AR $@"
	$(Q) $(AR) cru $@ $^

checkdirs: $(BUILD_DIR) $(FW_BASE)

$(BUILD_DIR):
	$(Q) mkdir -p $@

$(FW_BASE):
	$(Q) mkdir -p $@

debug: checkdirs $(TARGET_OUT) $(FW_FILE_1) $(FW_FILE_2)

flash: $(FW_FILE_1) $(FW_FILE_2)
	$(ESPTOOL) --port $(ESPPORT) write_flash $(FLASH_FLAGS) $(FW_FILE_1_ADDR) $(FW_FILE_1) $(FW_FILE_2_ADDR) $(FW_FILE_2)

clean:
	$(Q) rm -rf $(FW_BASE) $(BUILD_BASE)

$(foreach bdir,$(SRC_DIR),$(eval $(call compile-objects,$(bdir))))
