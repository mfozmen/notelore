#include "quick_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

namespace {

constexpr int kHotkey = 0x4E4C;  // any id unique to this window
constexpr int kWidth = 460;
constexpr int kHeight = 260;
constexpr int kTop = 64;

// Takes the focus from the app in front. Windows keeps it from a background
// process even after the shortcut, unless their input queues are joined.
void TakeFocus(HWND window) {
  const DWORD front = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
  const DWORD self = GetCurrentThreadId();
  const bool joined = front != self && AttachThreadInput(front, self, TRUE);
  BringWindowToTop(window);
  SetForegroundWindow(window);
  if (joined) AttachThreadInput(front, self, FALSE);
}

}  // namespace

QuickWindow::QuickWindow(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "io.github.mfozmen.notelore/quick",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "listen") {
      const auto* on = std::get_if<bool>(call.arguments());
      result->Success(flutter::EncodableValue(Listen(on != nullptr && *on)));
    } else if (method == "compact") {
      Compact();
      result->Success();
    } else if (method == "restore") {
      Restore();
      result->Success();
    } else if (method == "front") {
      Front();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

QuickWindow::~QuickWindow() { Listen(false); }

bool QuickWindow::Handle(UINT message, WPARAM wparam) {
  if (message != WM_HOTKEY || wparam != kHotkey) return false;
  channel_->InvokeMethod("pressed", nullptr);
  return true;
}

bool QuickWindow::Listen(bool on) {
  if (listening_) UnregisterHotKey(window_, kHotkey);
  listening_ = on && RegisterHotKey(window_, kHotkey,
                                    MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'N');
  return listening_ || !on;
}

void QuickWindow::Compact() {
  if (compact_) return Front();
  previous_ = GetForegroundWindow();
  GetWindowPlacement(window_, &placement_);
  GetWindowRect(window_, &frame_);
  style_ = GetWindowLongPtr(window_, GWL_STYLE);
  compact_ = true;
  // On the screen the person works on: the one under the app they are in.
  HMONITOR monitor = MonitorFromWindow(previous_ ? previous_ : window_,
                                       MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(MONITORINFO)};
  GetMonitorInfo(monitor, &info);
  const double scale = GetDpiForWindow(window_) / 96.0;
  const int width = static_cast<int>(kWidth * scale);
  const int height = static_cast<int>(kHeight * scale);
  const RECT& area = info.rcWork;
  const int x = area.left + (area.right - area.left - width) / 2;
  const int y = area.top + static_cast<int>(kTop * scale);
  SetWindowLongPtr(window_, GWL_STYLE,
                   (style_ & ~WS_OVERLAPPEDWINDOW) | WS_POPUP | WS_VISIBLE);
  DWM_WINDOW_CORNER_PREFERENCE round = DWMWCP_ROUND;
  DwmSetWindowAttribute(window_, DWMWA_WINDOW_CORNER_PREFERENCE, &round,
                        sizeof(round));
  if (IsIconic(window_)) ShowWindow(window_, SW_RESTORE);
  SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  TakeFocus(window_);
}

void QuickWindow::Restore() {
  if (!compact_) return;
  compact_ = false;
  SetWindowLongPtr(window_, GWL_STYLE, style_);
  SetWindowPos(window_, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
  // Back as it was, minimized again if it was; the person returns to their app.
  SetWindowPlacement(window_, &placement_);
  // Coming back from a screen of another scale, Windows resizes the window by
  // the ratio (WM_DPICHANGED): the frame it had is set again.
  if (placement_.showCmd == SW_SHOWNORMAL) {
    SetWindowPos(window_, nullptr, frame_.left, frame_.top,
                 frame_.right - frame_.left, frame_.bottom - frame_.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  if (previous_ && previous_ != window_ && IsWindow(previous_)) {
    SetForegroundWindow(previous_);
  }
}

void QuickWindow::Front() {
  if (IsIconic(window_)) ShowWindow(window_, SW_RESTORE);
  ShowWindow(window_, SW_SHOW);
  TakeFocus(window_);
}
