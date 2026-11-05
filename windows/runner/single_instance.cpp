#include "single_instance.h"

#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <functional>
#include <string>

namespace {

std::wstring ModulePath(HANDLE process) {
  wchar_t buffer[MAX_PATH * 4];
  DWORD size = static_cast<DWORD>(std::size(buffer));
  if (process == nullptr) {
    size = ::GetModuleFileNameW(nullptr, buffer, size);
  } else if (!::QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    size = 0;
  }
  std::wstring path(buffer, size);
  std::transform(path.begin(), path.end(), path.begin(), std::towlower);
  return path;
}

struct Search {
  std::wstring exe;
  HWND found = nullptr;
};

// Finds a top-level Flutter window owned by another process of this exe.
BOOL CALLBACK FindWindowOfExe(HWND hwnd, LPARAM param) {
  auto* search = reinterpret_cast<Search*>(param);
  wchar_t cls[64];
  if (!::GetClassNameW(hwnd, cls, 64) ||
      wcscmp(cls, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) {
    return TRUE;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  if (pid == ::GetCurrentProcessId()) return TRUE;
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return TRUE;
  const bool same = ModulePath(process) == search->exe;
  ::CloseHandle(process);
  if (!same) return TRUE;
  search->found = hwnd;
  return FALSE;
}

std::wstring FirstArgument() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  std::wstring arg;
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      if (argv[i][0] != L'-') {
        arg = argv[i];
        break;
      }
    }
    ::LocalFree(argv);
  }
  return arg;
}

}  // namespace

bool ForwardToRunningInstance() {
  const std::wstring exe = ModulePath(nullptr);
  // The mutex is per executable, so a debug build and an installed copy can
  // run side by side. It is released when this process exits.
  const std::wstring name =
      L"Local\\EasyGit-" + std::to_wstring(std::hash<std::wstring>{}(exe));
  ::CreateMutexW(nullptr, FALSE, name.c_str());
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;

  Search search{exe};
  // The first instance may still be creating its window.
  for (int attempt = 0; attempt < 20 && search.found == nullptr; attempt++) {
    ::EnumWindows(FindWindowOfExe, reinterpret_cast<LPARAM>(&search));
    if (search.found == nullptr) ::Sleep(100);
  }
  if (search.found == nullptr) return false;

  DWORD pid = 0;
  ::GetWindowThreadProcessId(search.found, &pid);
  // Let the running instance bring itself to the front.
  ::AllowSetForegroundWindow(pid);

  const std::wstring folder = FirstArgument();
  COPYDATASTRUCT data{};
  data.dwData = kOpenFolderMessage;
  data.cbData = static_cast<DWORD>((folder.size() + 1) * sizeof(wchar_t));
  data.lpData = const_cast<wchar_t*>(folder.c_str());
  DWORD_PTR result = 0;
  ::SendMessageTimeoutW(search.found, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
                        SMTO_ABORTIFHUNG, 3000, &result);
  return true;
}
