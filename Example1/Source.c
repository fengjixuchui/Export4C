/*
    Example1:
        Reference the actual address and size of "ExampleProc" function,
        which defined in "ExampleProc.c".
*/

#include <Windows.h>
#include <Shlwapi.h>

#pragma comment (lib, "Shlwapi.lib")

// Proto of "ExampleProc" function
typedef int(__stdcall* PEXAMPLEPROC)(int a, int b);

// Actual address of "ExampleProc" function, exported by Export4C
extern PEXAMPLEPROC E4C_Addr_ExampleProc;
// Size in bytes of "ExampleProc" function, exported by Export4C
extern size_t E4C_Size_ExampleProc;

int main() {
    TCHAR   szOutput[1024];
    int     iResult, cch;
    size_t  uSize;
    iResult = E4C_Addr_ExampleProc(2, 3);
    uSize = E4C_Size_ExampleProc;
    cch = wnsprintf(szOutput, ARRAYSIZE(szOutput), TEXT("Address is: %p, size is: %zu bytes, 2 + 3 = %d\r\n"), E4C_Addr_ExampleProc, (DWORD)uSize, iResult);
    if (cch > 0)
        WriteConsole(GetStdHandle(STD_OUTPUT_HANDLE), szOutput, cch, NULL, NULL);
    return 0;
}