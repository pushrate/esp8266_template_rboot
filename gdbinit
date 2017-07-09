#echo gdbinit is being used\n
#set debug remote 1
#set verbose 1
set serial baud 115200
set remote hardware-breakpoint-limit 1
set remote hardware-watchpoint-limit 1
#set debug xtensa 4

define connect
 file build/example.out
 target remote /dev/ttyUSB0
end
