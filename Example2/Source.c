/*
    Example2:
        Print the result of comparison between with and without Export4C.
*/

#include <Windows.h>
#include <Shlwapi.h>

#pragma comment (lib, "Shlwapi.lib")

// C externs
EXTERN_C DWORD WINAPI ExampleProc(LPVOID ThreadParameter);
EXTERN_C VOID WINAPI ExampleProcEnd(VOID);
// Export4C externs
EXTERN_C LPTHREAD_START_ROUTINE E4C_Addr_ExampleProc;
EXTERN_C SIZE_T E4C_Size_ExampleProc;

VOID PrintAddressAndSize(LPVOID FuncAddress, SIZE_T FuncSize, BOOL E4CUsed) {
    TCHAR   szOutput[1024];
    INT     iChOutputLength;
    iChOutputLength = wnsprintf(szOutput, ARRAYSIZE(szOutput), TEXT("[Export4C%s used] \tAddress is: %p, size is: %zu bytes\r\n"), E4CUsed ? TEXT("") : TEXT(" not"), FuncAddress, FuncSize);
    if (iChOutputLength > 0)
        WriteConsole(GetStdHandle(STD_OUTPUT_HANDLE), szOutput, (DWORD)iChOutputLength, NULL, NULL);
}

int main() {
    // Print C externs
    PrintAddressAndSize(ExampleProc, (SIZE_T)ExampleProcEnd - (SIZE_T)ExampleProc, FALSE);
    // Print Export4C externs
    PrintAddressAndSize(E4C_Addr_ExampleProc, E4C_Size_ExampleProc, TRUE);
    return 0;
}