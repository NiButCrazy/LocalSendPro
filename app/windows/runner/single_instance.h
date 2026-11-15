#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// Name of the mutex that marks a running LocalSend instance. The "Local\" prefix
// scopes it to the current session, so one instance is allowed per user session.
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\localsend_app_single_instance";

// Window class registered by win32_window.cpp for the Flutter window.
constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// dwData tag for the WM_COPYDATA payload that carries the command line arguments
// of a second launch to the running instance. The payload is a list of
// NUL-separated UTF-8 arguments terminated by an extra NUL.
constexpr DWORD kSingleInstanceCopyDataMagic = 0x4C53454E;  // 'LSEN'

#endif  // RUNNER_SINGLE_INSTANCE_H_
