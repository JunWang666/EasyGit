// "Open in EasyGit" for the Windows 11 File Explorer context menu.
//
// The new context menu only shows IExplorerCommand handlers that come with a
// package identity. AppxManifest.xml (a sparse package whose files live in
// the EasyGit install folder) registers this DLL for folders and for the
// background of an open folder. Invoking the command starts easygit.exe with
// the folder; a running EasyGit takes the folder over (windows/runner).

#include <shlwapi.h>
#include <shobjidl_core.h>
#include <windows.h>
#include <wrl/implements.h>
#include <wrl/module.h>

#include <string>

using Microsoft::WRL::ClassicCom;
using Microsoft::WRL::InhibitRoOriginateError;
using Microsoft::WRL::Module;
using Microsoft::WRL::ModuleType;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;

namespace {

HMODULE g_module = nullptr;

// easygit.exe next to this DLL.
std::wstring ExePath() {
  wchar_t path[MAX_PATH * 4];
  const DWORD n = ::GetModuleFileNameW(g_module, path, static_cast<DWORD>(std::size(path)));
  std::wstring dir(path, n);
  dir.resize(dir.find_last_of(L"\\/") + 1);
  return dir + L"easygit.exe";
}

}  // namespace

class __declspec(uuid("EE18C7F1-DA63-46D6-8FA2-DE30FB6FD490")) OpenInEasyGitCommand final
    : public RuntimeClass<RuntimeClassFlags<ClassicCom | InhibitRoOriginateError>,
                          IExplorerCommand> {
 public:
  IFACEMETHODIMP GetTitle(IShellItemArray*, LPWSTR* name) override {
    return ::SHStrDupW(L"Open in EasyGit", name);
  }

  IFACEMETHODIMP GetIcon(IShellItemArray*, LPWSTR* icon) override {
    return ::SHStrDupW((ExePath() + L",0").c_str(), icon);
  }

  IFACEMETHODIMP GetToolTip(IShellItemArray*, LPWSTR* tip) override {
    *tip = nullptr;
    return E_NOTIMPL;
  }

  IFACEMETHODIMP GetCanonicalName(GUID* guid) override {
    *guid = __uuidof(OpenInEasyGitCommand);
    return S_OK;
  }

  IFACEMETHODIMP GetState(IShellItemArray* items, BOOL, EXPCMDSTATE* state) override {
    // One folder at a time; hidden for multiple selections.
    DWORD count = 1;
    if (items != nullptr) items->GetCount(&count);
    *state = count == 1 ? ECS_ENABLED : ECS_HIDDEN;
    return S_OK;
  }

  IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override {
    if (items == nullptr) return E_INVALIDARG;
    Microsoft::WRL::ComPtr<IShellItem> item;
    HRESULT hr = items->GetItemAt(0, &item);
    if (FAILED(hr)) return hr;
    LPWSTR folder = nullptr;
    hr = item->GetDisplayName(SIGDN_FILESYSPATH, &folder);
    if (FAILED(hr)) return hr;  // not a file system folder (e.g. This PC)
    const std::wstring exe = ExePath();
    const std::wstring args = L"\"" + std::wstring(folder) + L"\"";
    ::CoTaskMemFree(folder);
    const auto result = reinterpret_cast<INT_PTR>(
        ::ShellExecuteW(nullptr, L"open", exe.c_str(), args.c_str(), nullptr, SW_SHOWNORMAL));
    return result > 32 ? S_OK : HRESULT_FROM_WIN32(::GetLastError());
  }

  IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override {
    *flags = ECF_DEFAULT;
    return S_OK;
  }

  IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** commands) override {
    *commands = nullptr;
    return E_NOTIMPL;
  }
};

CoCreatableClass(OpenInEasyGitCommand)

STDAPI DllGetActivationFactory(HSTRING id, IActivationFactory** factory) {
  return Module<ModuleType::InProc>::GetModule().GetActivationFactory(id, factory);
}

STDAPI DllCanUnloadNow() {
  return Module<ModuleType::InProc>::GetModule().GetObjectCount() == 0 ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** object) {
  return Module<ModuleType::InProc>::GetModule().GetClassObject(clsid, iid, object);
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    ::DisableThreadLibraryCalls(module);
  }
  return TRUE;
}
