#include <Windows.h>

DWORD WINAPI ExampleProc(LPVOID lpThreadParameter) {
    UNREFERENCED_PARAMETER(lpThreadParameter);
    return 0;
}

VOID WINAPI ExampleProcEnd() {}