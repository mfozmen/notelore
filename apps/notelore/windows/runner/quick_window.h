#ifndef RUNNER_QUICK_WINDOW_H_
#define RUNNER_QUICK_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// The quick-add window (quick_window_native.dart, #800): the global shortcut
// Ctrl+Alt+N and the main window's small floating shape.
class QuickWindow {
 public:
  QuickWindow(HWND window, flutter::BinaryMessenger* messenger);
  ~QuickWindow();

  // True when |message| was the shortcut, which is then handed to Dart.
  bool Handle(UINT message, WPARAM wparam);

 private:
  bool Listen(bool on);
  bool TypesOnAltGr() const;
  void Compact();
  void Restore(bool refocus);
  void Front();

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool listening_ = false;
  bool compact_ = false;
  bool opening_ = false;
  WINDOWPLACEMENT placement_{sizeof(WINDOWPLACEMENT)};
  RECT frame_{};
  LONG_PTR style_ = 0;
  HWND previous_ = nullptr;
};

#endif  // RUNNER_QUICK_WINDOW_H_
