// SMTC 桥头文件（Windows System Media Transport Controls）
#ifndef FLUTTER_RUNNER_SMTC_BRIDGE_H_
#define FLUTTER_RUNNER_SMTC_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

namespace smtc_bridge {

// 注册 MethodChannel 并初始化 SystemMediaTransportControls。
// 应在 Flutter 引擎创建后（FlutterWindow::OnCreate 中 RegisterPlugins 之后）调用。
void Register(flutter::BinaryMessenger* messenger, HWND hwnd);

// 反注册（窗口销毁时调用，避免回调悬挂）。
void Dispose();

}  // namespace smtc_bridge

#endif  // FLUTTER_RUNNER_SMTC_BRIDGE_H_
