#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <thread>
#include <vector>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "winrt_ext.h"

namespace {

// Keeps the single-instance mutex alive for the whole process lifetime. Closing
// the handle would let another launch believe that no instance is running.
HANDLE g_instance_mutex = nullptr;

// Runs the share activation query on a dedicated MTA thread. The main thread is
// an STA (required by Flutter's OLE integration), and blocking on WinRT async
// operations from an STA is not allowed; cppwinrt asserts with !is_sta_thread.
std::string GetSharedMediaJson() {
  std::string result;

  std::thread worker([&result]() {
    if (FAILED(::CoInitializeEx(nullptr, COINIT_MULTITHREADED))) {
      return;
    }
    const winrt::hstring media = GetSharedMedia();
    if (!media.empty()) {
      result = Utf8FromUtf16(media.c_str());
    }
    ::CoUninitialize();
  });
  worker.join();

  return result;
}

// Hands the command line over to an already running instance and returns true
// when that instance accepted it. The second process then exits without creating
// a Flutter window, so activation is immediate instead of waiting for a full
// engine startup.
bool TryHandOverToRunningInstance(const std::vector<std::string>& args) {
  HANDLE mutex = CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (mutex == nullptr) {
    return false;
  }
  if (GetLastError() != ERROR_ALREADY_EXISTS) {
    g_instance_mutex = mutex;
    return false;
  }
  CloseHandle(mutex);

  HWND window = FindWindowW(kMainWindowClassName, nullptr);
  if (window == nullptr) {
    // The other instance has not created its window yet; fall back to the
    // regular startup path, which performs the HTTP hand-over.
    return false;
  }

  // NUL-separated UTF-8 arguments, terminated by an extra NUL.
  std::string payload;
  for (const auto& arg : args) {
    payload.append(arg);
    payload.push_back('\0');
  }
  payload.push_back('\0');

  COPYDATASTRUCT copy_data = {};
  copy_data.dwData = kSingleInstanceCopyDataMagic;
  copy_data.cbData = static_cast<DWORD>(payload.size());
  copy_data.lpData = const_cast<char*>(payload.data());

  DWORD_PTR result = 0;
  const LRESULT sent =
      SendMessageTimeoutW(window, WM_COPYDATA, 0,
                          reinterpret_cast<LPARAM>(&copy_data),
                          SMTO_ABORTIFHUNG | SMTO_BLOCK, 1000, &result);
  return sent != 0 && result == TRUE;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  if (IsRunningWithIdentity()) {
    const std::string share_arg = GetSharedMediaJson();
    if (!share_arg.empty()) {
      printf("share: %s\n", share_arg.c_str());
      command_line_arguments.push_back("--share");
      command_line_arguments.push_back(share_arg);
    }
  }

  if (TryHandOverToRunningInstance(command_line_arguments)) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(500, 600);
  if (!window.Create(L"LocalSend", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
