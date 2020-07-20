/**
  * @warning Disable features like JMC (Just My Code) , Security Cookie, SDL and RTC to prevent external procedure calls generated.
  * @see See also the C/C++ settings for this file
  */

#include <Windows.h>

DWORD WINAPI InjectProc(LPVOID lpThreadParameter) {
    UNREFERENCED_PARAMETER(lpThreadParameter);
    return 666;
}