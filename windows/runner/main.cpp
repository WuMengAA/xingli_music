#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <shlobj.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 读取 shared_preferences.json 里的 settings.engineBackend（R21 图形后端选配）。
// 返回静态缓冲内的宽字符串指针；未配置/读取失败返回 nullptr。
// 文件路径：%APPDATA%\com.stelarith\xingli_music\shared_preferences.json
const wchar_t *ReadEngineBackendFromPrefs() {
  static wchar_t g_value[64] = {0};

  wchar_t appdata[MAX_PATH] = {0};
  if (::SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT,
                         appdata) != S_OK) {
    return nullptr;
  }
  std::wstring path(appdata);
  path += L"\\com.stelarith\\xingli_music\\shared_preferences.json";

  HANDLE h = ::CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    return nullptr;
  }
  DWORD size = ::GetFileSize(h, nullptr);
  if (size == 0 || size > 1 << 20) {
    ::CloseHandle(h);
    return nullptr;
  }
  std::string content(size, '\0');
  DWORD read = 0;
  BOOL ok = ::ReadFile(h, &content[0], size, &read, nullptr);
  ::CloseHandle(h);
  if (!ok || read != size) {
    return nullptr;
  }

  const std::string key = "\"settings.engineBackend\"";
  size_t pos = content.find(key);
  if (pos == std::string::npos) {
    return nullptr;
  }
  pos += key.size();
  pos = content.find('"', pos);
  if (pos == std::string::npos) {
    return nullptr;
  }
  size_t end = content.find('"', pos + 1);
  if (end == std::string::npos) {
    return nullptr;
  }
  std::string val = content.substr(pos + 1, end - pos - 1);
  if (val.empty()) {
    return nullptr;
  }
  // ASCII 值转宽字符（auto/skiaOpengl/impellerD3D11/impellerVulkan/software）
  MultiByteToWideChar(CP_UTF8, 0, val.c_str(), (int)val.size(), g_value, 63);
  return g_value;
}

// 把「实际生效的渲染后端」写入 %APPDATA%\com.stelarith\xingli_music\
// engine_backend_active.txt，供设置页展示真实状态（R22，UTF-8）。
void WriteActiveBackend(const char *name) {
  wchar_t appdata[MAX_PATH] = {0};
  if (::SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT,
                         appdata) != S_OK) {
    return;
  }
  std::wstring dir(appdata);
  dir += L"\\com.stelarith\\xingli_music";
  ::CreateDirectoryW(dir.c_str(), nullptr);
  std::wstring path = dir + L"\\engine_backend_active.txt";
  HANDLE h = ::CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                           CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written = 0;
  ::WriteFile(h, name, (DWORD)strlen(name), &written, nullptr);
  ::CloseHandle(h);
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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // ── Windows 渲染后端：可配置（R21/R22，重启生效）────────────────────
  // 设置 → 基础 → 画面 → 性能与质量 → 图形后端 选择后写入
  // shared_preferences.json（键 settings.engineBackend），本处启动时读取。
  // 取值：auto / skiaOpengl / impellerD3D11 / impellerVulkan / software。
  // 默认策略（用户定版 R22）：未配置 / auto → Windows 默认 DX11（Impeller）；
  // 显式 skiaOpengl → 走 Skia（不设置任何 switch）。
  // ⚠️ impellerVulkan：Flutter Windows 引擎 Impeller 仅实现 D3D11，
  // enable-impeller-vulkan 不被识别 → 显式回退 DX11（R22 实测切换无效）。
  const wchar_t *engineBackend = ReadEngineBackendFromPrefs();
  // R27：默认图形后端改为 Skia/ANGLE（skiaOpengl）。体素世界依赖 ImageShader 贴图，
  // Impeller/D3D11 下解码图作 ImageShader 源整批采样为黑（用户报「高清档方块黑、
  // 天/云不黑」——天/云走纯色/形状绘制没问题，唯有贴图图集走 ImageShader 黑）；
  // Skia 路径解码图采样正常。显式选 impellerD3D11 / impellerVulkan 仍走 Impeller
  // （Vulkan 不支持 → 回退 DX11）。设置页「图形后端」可切回。
  const bool wantVulkan = engineBackend != nullptr &&
                          wcscmp(engineBackend, L"impellerVulkan") == 0;
  const bool wantSkia = engineBackend == nullptr ||
                        wcscmp(engineBackend, L"auto") == 0 ||
                        wcscmp(engineBackend, L"skiaOpengl") == 0;
  const bool isDefaultDx11 = engineBackend != nullptr &&
                             (wcscmp(engineBackend, L"impellerD3D11") == 0 ||
                              wantVulkan);  // Vulkan 不支持 → 回退 DX11
  const bool wantSoftware = engineBackend != nullptr &&
                            wcscmp(engineBackend, L"software") == 0;
  const char *activeBackend = "skiaOpengl";  // 默认 Skia/ANGLE（贴图可靠）
  if (isDefaultDx11 && !wantSkia) {
    SetEnvironmentVariable(L"FLUTTER_ENGINE_SWITCHES", L"1");
    SetEnvironmentVariable(L"FLUTTER_ENGINE_SWITCH_1", L"enable-impeller");
  } else if (wantSoftware) {
    activeBackend = "software";
    SetEnvironmentVariable(L"FLUTTER_ENGINE_SWITCHES", L"1");
    SetEnvironmentVariable(L"FLUTTER_ENGINE_SWITCH_1",
                           L"enable-software-rendering");
  } else if (wantSkia) {
    activeBackend = "skiaOpengl";
  }
  // skiaOpengl：不设置任何 switch（引擎默认 Skia/ANGLE 路径）。
  WriteActiveBackend(activeBackend);

  // ── Windows 无障碍桥禁用（崩溃根治，R20 定位）─────────────────────
  // crash dump + 反汇编证实：设置→场景页面切换时语义树大规模更新，
  // 引擎 accessibility_bridge.cc 遍历语义节点遇内部 NULL 指针（访问
  // 0x48 字段）→ flutter_windows.dll+0x3A9FA 空指针崩溃。三种渲染后端
  // 同偏移崩溃 = 引擎 CPU 端通用路径。这是 Flutter Windows 已知回归
  // （flutter/flutter#103808）。3.44 引擎已移除 FLUTTER_A11Y 变量，
  // 真正根治在 Dart 层 ExcludeSemantics（app.dart）；本行保留为兜底。
  SetEnvironmentVariable(L"FLUTTER_A11Y", L"off");

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 900);
  // 窗口标题「星璃音乐·星尘初聚」（Unicode 转义，避免源码编码问题；
  // 代号变更时与 lib/core/app_version.dart 的 codename 同步）。
  if (!window.Create(
        L"\x661F\x748B\x97F3\x4E50\x00B7\x661F\x5C18\x521D\x805A",
        origin,
        size)) {
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
