#include "ets_sys.h"
#include "osapi.h"
#include "gpio.h"
#include "os_type.h"
#include "user_config.h"
#include "driver/uart.h"

#ifdef DEBUG
#include "gdbstub.h"
#endif

//Init function
void ICACHE_FLASH_ATTR
user_init()
{
  uart_init(115200, 115200);
  UART_SetPrintPort(0);

#ifdef DEBUG
  gdbstub_init();
#endif

  os_printf("Hi this is working\n");

  #ifdef DEBUG
  // insert breakpoint programmatically
  gdbstub_do_break();
  #endif

  os_printf("Just hit the end\n");
}
