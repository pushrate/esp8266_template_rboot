## Extended ESP8266 example/template project

Slightly more complex example for use with rboot, and includes rboot-api for accessing/updating settings for OTA use

## Motivation

I've extended and updated the Makefile example from the wonderful people over at esp8266.org. I wanted to share it as a way to help other people, as well as force myself to document how it all works so I don't have to reverse engineer it again later.

## Usage

Most of the detail is covered in the Makefile, take a look there to customize this for your project.

I've included a gdbinit file example (you'll need to update the bin file location if you change the project name), which you can invoke either by using the -x flag to xtensa-lx106-elf-gdb or issuing 'source gdbinit' from the gdb prompt

## Caveats

I've only tested with esp-open-sdk, and not the RTOS version. This means I've set GDBSTUB_FREERTOS define to zero in the Makefile for the debug configuration

## TODO

I think it'd be better to clearly separate the debug build from the release build. Right now, if you don't do a make clean, you can end up with a mixture of objects with and without debug information.
