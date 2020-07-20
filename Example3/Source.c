/*
    Example3:
        Inject and execute code in a process.
*/

#include <Windows.h>
#include <stdio.h>

// Export4C externs
EXTERN_C LPTHREAD_START_ROUTINE E4C_Addr_InjectProc;
EXTERN_C SIZE_T E4C_Size_InjectProc;

int main() {
    DWORD   dwPID, dwLastError, dwResult;
    HANDLE  hProc, hRemoteThread;
    LPVOID  lpRemoteMem;
    dwLastError = ERROR_SUCCESS;
    // Use current process ID in this example.
    // Architecture (x64/x86) of target process should be the same with this example.
    dwPID = GetCurrentProcessId();
    hProc = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | PROCESS_VM_WRITE | SYNCHRONIZE, FALSE, dwPID);
    if (hProc == INVALID_HANDLE_VALUE) {
        dwLastError = ERROR_INVALID_HANDLE;
        goto Label_3;
    }
    // Allocate memory for the process
    lpRemoteMem = VirtualAllocEx(hProc, NULL, E4C_Size_InjectProc, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!lpRemoteMem) {
        dwLastError = GetLastError();
        printf_s("Allocate memory failed with error: %d", dwLastError);
        goto Label_2;
    }
    // Write code to the memory and flush cache
    if (!WriteProcessMemory(hProc, lpRemoteMem, E4C_Addr_InjectProc, E4C_Size_InjectProc, NULL)) {
        dwLastError = GetLastError();
        printf_s("Write code failed with error: %d", dwLastError);
        goto Label_1;
    }
    FlushInstructionCache(hProc, lpRemoteMem, E4C_Size_InjectProc);
    // Create remote thread and wait for the result
    hRemoteThread = CreateRemoteThread(hProc, NULL, 0, lpRemoteMem, NULL, 0, NULL);
    if (!hRemoteThread) {
        dwLastError = GetLastError();
        printf_s("Create remote thread failed with error: %d", dwLastError);
        goto Label_1;
    }
    WaitForSingleObject(hRemoteThread, INFINITE);
    if (!GetExitCodeThread(hRemoteThread, &dwResult)) {
        dwLastError = GetLastError();
        printf_s("Get exit code of remote thread failed with error: %d", dwLastError);
        goto Label_0;
    }
    // "InjectProc" function returns "666"
    printf_s("Remote thread returns: %d", dwResult);
    // Cleanup and exit
Label_0:
    CloseHandle(hRemoteThread);
Label_1:
    VirtualFreeEx(hProc, lpRemoteMem, 0, MEM_RELEASE);
Label_2:
    CloseHandle(hProc);
Label_3:
    return dwLastError;
}