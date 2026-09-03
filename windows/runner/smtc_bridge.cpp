// ═══════════════════════════════════════════════════════════════════════
// SMTC 桥（Windows System Media Transport Controls）
//
// 把星璃播放器的媒体信息 / 播放状态同步到 Windows 系统媒体控件
// （任务栏媒体卡片 + 全局媒体键），并把系统媒体键事件转发回 Dart。
//
// 协议（MethodChannel "com.stelarith.xingli_music/smtc"）：
//   Dart → native:
//     updateMediaItem({title, artist, album, duration, artPath})
//     updatePlayback({playing, positionMs, durationMs})
//     clear()
//   native → Dart:
//     onButton({action})   action: play/pause/next/previous/stop
//     onSeek({positionMs})
// ═══════════════════════════════════════════════════════════════════════
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <SystemMediaTransportControlsInterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <memory>
#include <string>

#include "smtc_bridge.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

using winrt::Windows::Media::MediaPlaybackStatus;
using winrt::Windows::Media::MediaPlaybackType;
using winrt::Windows::Media::SystemMediaTransportControls;
using winrt::Windows::Media::SystemMediaTransportControlsButton;
using winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater;
using winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties;

SystemMediaTransportControls g_smtc{nullptr};
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
std::atomic<bool> g_registered{false};

// 事件 token（保存以避免 revoker 提前析构导致回调失效）。
winrt::event_token g_button_token;
winrt::event_token g_seek_token;

std::string ToUtf8(const winrt::hstring& s) {
  if (s.empty()) return std::string();
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, nullptr, 0,
                                        nullptr, nullptr);
  std::string out(len > 0 ? len - 1 : 0, '\0');
  if (len > 0) {
    ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, &out[0], len, nullptr,
                          nullptr);
  }
  return out;
}

winrt::hstring ToHstring(const std::string& s) {
  if (s.empty()) return winrt::hstring();
  const int len =
      ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring out(len, L'\0');
  if (len > 0) {
    ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &out[0], len);
  }
  return winrt::hstring(out);
}

std::string GetString(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return std::string();
  }
  return std::get<std::string>(it->second);
}

double GetDouble(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  if (it == map.end()) return 0.0;
  const EncodableValue& v = it->second;
  if (std::holds_alternative<int>(v)) return static_cast<double>(std::get<int>(v));
  if (std::holds_alternative<double>(v)) return std::get<double>(v);
  return 0.0;
}

bool GetBool(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  if (it == map.end() || !std::holds_alternative<bool>(it->second)) return false;
  return std::get<bool>(it->second);
}

void EmitButton(const std::string& action) {
  if (!g_channel) return;
  EncodableMap args;
  args[EncodableValue("action")] = EncodableValue(action);
  g_channel->InvokeMethod("onButton", std::make_unique<EncodableValue>(args));
}

// 本地文件路径 → 随机访问流引用（SMTC 缩略图）。
void SetThumbnail(SystemMediaTransportControlsDisplayUpdater& updater,
                  const std::string& artPath) {
  if (artPath.empty()) return;
  try {
    const std::wstring wide(artPath.begin(), artPath.end());
    auto file =
        winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(wide).get();
    auto ref = winrt::Windows::Storage::Streams::RandomAccessStreamReference::
        CreateFromFile(file);
    updater.Thumbnail(ref);
  } catch (...) {
    // 封面加载失败不阻塞（仅显示无封面）。
  }
}

void HandleUpdateMediaItem(const EncodableMap& args) {
  if (!g_smtc) return;
  try {
    SystemMediaTransportControlsDisplayUpdater updater = g_smtc.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
    updater.MusicProperties().Title(ToHstring(GetString(args, "title")));
    updater.MusicProperties().Artist(ToHstring(GetString(args, "artist")));
    updater.MusicProperties().AlbumTitle(ToHstring(GetString(args, "album")));
    SetThumbnail(updater, GetString(args, "artPath"));
    updater.Update();
  } catch (...) {
  }
}

void HandleUpdatePlayback(const EncodableMap& args) {
  if (!g_smtc) return;
  try {
    g_smtc.PlaybackStatus(GetBool(args, "playing")
                              ? MediaPlaybackStatus::Playing
                              : MediaPlaybackStatus::Paused);
    SystemMediaTransportControlsTimelineProperties props;
    props.Position(winrt::Windows::Foundation::TimeSpan{
        static_cast<int64_t>(GetDouble(args, "positionMs") * 10'000)});
    props.StartTime(winrt::Windows::Foundation::TimeSpan{0});
    const double dur = GetDouble(args, "durationMs");
    if (dur > 0) {
      props.EndTime(winrt::Windows::Foundation::TimeSpan{
          static_cast<int64_t>(dur * 10'000)});
    }
    g_smtc.UpdateTimelineProperties(props);
  } catch (...) {
  }
}

}  // namespace

namespace smtc_bridge {

void Register(flutter::BinaryMessenger* messenger, HWND hwnd) {
  if (g_registered) return;
  g_registered = true;

  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "com.stelarith.xingli_music/smtc",
      &flutter::StandardMethodCodec::GetInstance());

  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();
        if (method == "updateMediaItem") {
          if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
            HandleUpdateMediaItem(*args);
          }
          result->Success();
        } else if (method == "updatePlayback") {
          if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
            HandleUpdatePlayback(*args);
          }
          result->Success();
        } else if (method == "clear") {
          if (g_smtc) {
            g_smtc.PlaybackStatus(MediaPlaybackStatus::Stopped);
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // 初始化 SMTC：Win32 桌面应用无 CoreWindow，须用 ISystemMediaTransportControlsInterop
  // 经窗口句柄获取（GetForCurrentView 仅在 UWP/CoreWindow 有效）。
  try {
    auto interop = winrt::get_activation_factory<
        SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::com_ptr<ISystemMediaTransportControlsInterop> interopPtr;
    interop.as(interopPtr);
    SystemMediaTransportControls smtc{nullptr};
    winrt::check_hresult(interopPtr->GetForWindow(
        hwnd, winrt::guid_of<SystemMediaTransportControls>(),
        winrt::put_abi(smtc)));
    g_smtc = smtc;
    if (!g_smtc) return;

    g_button_token = g_smtc.ButtonPressed(
        [](const SystemMediaTransportControls&,
           const winrt::Windows::Media::
               SystemMediaTransportControlsButtonPressedEventArgs& e) {
          switch (e.Button()) {
            case SystemMediaTransportControlsButton::Play:
              EmitButton("play");
              break;
            case SystemMediaTransportControlsButton::Pause:
              EmitButton("pause");
              break;
            case SystemMediaTransportControlsButton::Next:
              EmitButton("next");
              break;
            case SystemMediaTransportControlsButton::Previous:
              EmitButton("previous");
              break;
            case SystemMediaTransportControlsButton::Stop:
              EmitButton("stop");
              break;
            default:
              break;
          }
        });

    g_seek_token = g_smtc.PlaybackPositionChangeRequested(
        [](const SystemMediaTransportControls&,
           const winrt::Windows::Media::
               PlaybackPositionChangeRequestedEventArgs& e) {
          if (!g_channel) return;
          EncodableMap args;
          args[EncodableValue("positionMs")] =
              EncodableValue(static_cast<double>(
                  e.RequestedPlaybackPosition().count() / 10'000.0));
          g_channel->InvokeMethod("onSeek",
                                  std::make_unique<EncodableValue>(args));
        });
  } catch (...) {
    // SMTC 初始化失败（如无系统媒体会话）→ 静默，Dart 侧不感知。
    g_smtc = nullptr;
  }
}

void Dispose() {
  if (!g_registered) return;
  g_registered = false;
  if (g_smtc) {
    try {
      g_smtc.ButtonPressed(g_button_token);
      g_smtc.PlaybackPositionChangeRequested(g_seek_token);
    } catch (...) {
    }
  }
  g_smtc = nullptr;
  g_channel.reset();
}

}  // namespace smtc_bridge
