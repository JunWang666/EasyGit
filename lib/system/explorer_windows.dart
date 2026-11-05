import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Opens [path] as a new tab in the most recently used File Explorer window
/// (Windows 11) and brings that window to the front. Returns false when no
/// Explorer window is open or it has no tabs, so the caller can open a new
/// window instead. Windows only.
Future<bool> openInRecentExplorerTab(String path) async {
  final frame = _topmostExplorerWindow();
  if (frame == 0) return false;
  final tabs = _findChild(frame, 'ShellTabWindowClass');
  if (tabs == 0) return false; // Explorer without tabs (Windows 10)

  // Tabs are only scriptable through the Shell COM API, easiest reached from
  // PowerShell. The script counts the window's tabs, waits for "go" (sent
  // once the new tab is requested), then navigates the tab that appears.
  // Values travel in environment variables so they need no quoting.
  const script = r'''
$sh = New-Object -ComObject Shell.Application
function Tabs { @($sh.Windows() | Where-Object { $_.HWND -eq [long]$env:EASYGIT_HWND }) }
$before = (Tabs).Count
[Console]::Out.WriteLine("ready")
[Console]::Out.Flush()
[void][Console]::In.ReadLine()
for ($i = 0; $i -lt 40; $i++) {
  $t = Tabs
  if ($t.Count -gt $before) { $t[$t.Count - 1].Navigate2($env:EASYGIT_PATH); exit 0 }
  Start-Sleep -Milliseconds 50
}
exit 3
''';
  try {
    final ps = await Process.start(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      environment: {'EASYGIT_HWND': '$frame', 'EASYGIT_PATH': path},
    );
    final lines = ps.stdout.transform(utf8.decoder).transform(const LineSplitter());
    final ready = await lines.first.timeout(const Duration(seconds: 10), onTimeout: () => '');
    if (ready.trim() != 'ready') {
      ps.kill();
      return false;
    }
    _sendMessage(tabs, _wmCommand, _cmdNewTab, 1);
    ps.stdin.writeln('go');
    await ps.stdin.close();
    final code = await ps.exitCode.timeout(const Duration(seconds: 10), onTimeout: () {
      ps.kill();
      return -1;
    });
    if (code != 0) return false;
  } catch (_) {
    return false;
  }
  _bringToFront(frame);
  return true;
}

final _user32 = DynamicLibrary.open('user32.dll');

final _getTopWindow =
    _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetTopWindow');
final _getWindow =
    _user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('GetWindow');
final _findWindowEx = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
final _getClassName = _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
final _isWindowVisible =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');
final _isIconic = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IsIconic');
final _showWindow =
    _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
final _setForegroundWindow =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
final _sendMessage = _user32.lookupFunction<IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('SendMessageW');

const _gwHwndNext = 2;
const _swRestore = 9;
const _wmCommand = 0x0111;

/// Undocumented Explorer command that opens a new tab, sent to the tab host.
const _cmdNewTab = 0xA21B;

/// Top-level windows are listed front to back, so the first Explorer frame
/// found is the one used last.
int _topmostExplorerWindow() {
  final buf = calloc<Uint16>(64).cast<Utf16>();
  try {
    for (var h = _getTopWindow(0); h != 0; h = _getWindow(h, _gwHwndNext)) {
      if (_isWindowVisible(h) == 0) continue;
      final n = _getClassName(h, buf, 64);
      if (n > 0 && buf.toDartString(length: n) == 'CabinetWClass') return h;
    }
    return 0;
  } finally {
    calloc.free(buf);
  }
}

int _findChild(int parent, String className) {
  final cls = className.toNativeUtf16(allocator: calloc);
  try {
    return _findWindowEx(parent, 0, cls, nullptr);
  } finally {
    calloc.free(cls);
  }
}

void _bringToFront(int hwnd) {
  if (_isIconic(hwnd) != 0) _showWindow(hwnd, _swRestore);
  _setForegroundWindow(hwnd);
}
