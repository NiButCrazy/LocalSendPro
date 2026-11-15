#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  transfer_progress_window_ = std::make_unique<TransferProgressWindow>(GetHandle());
  transfer_progress_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "org.localsend.localsend_app/transfer_progress",
          &flutter::StandardMethodCodec::GetInstance());
  transfer_progress_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleTransferProgressCall(call, std::move(result));
      });
  transfer_progress_window_->SetActionHandler(
      [this](const std::string& action) {
        flutter::EncodableMap arguments;
        arguments[flutter::EncodableValue(std::string("action"))] =
            flutter::EncodableValue(action);
        transfer_progress_channel_->InvokeMethod(
            "onWindowAction",
            std::make_unique<flutter::EncodableValue>(arguments));
      });

  return true;
}

void FlutterWindow::OnDestroy() {
  if (transfer_progress_channel_) {
    transfer_progress_channel_->SetMethodCallHandler(nullptr);
    transfer_progress_channel_ = nullptr;
  }
  if (transfer_progress_window_) {
    transfer_progress_window_->Destroy();
    transfer_progress_window_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleTransferProgressCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!transfer_progress_window_) {
    result->Error("unavailable", "Transfer progress window is not available");
    return;
  }

  if (call.method_name() == "hideProgress") {
    transfer_progress_window_->Hide();
    result->Success();
    return;
  }

  const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!arguments) {
    result->Error("bad_arguments", "Expected a map");
    return;
  }

  const auto title_it =
      arguments->find(flutter::EncodableValue(std::string("title")));
  const auto text_it =
      arguments->find(flutter::EncodableValue(std::string("text")));
  if (title_it == arguments->end() || text_it == arguments->end()) {
    result->Error("bad_arguments", "Missing title or text");
    return;
  }

  const auto* title = std::get_if<std::string>(&title_it->second);
  const auto* text = std::get_if<std::string>(&text_it->second);
  if (!title || !text) {
    result->Error("bad_arguments", "title and text must be strings");
    return;
  }

  const auto dark_it =
      arguments->find(flutter::EncodableValue(std::string("dark")));
  const auto background_it =
      arguments->find(flutter::EncodableValue(std::string("background")));
  const auto foreground_it =
      arguments->find(flutter::EncodableValue(std::string("foreground")));
  const auto accent_it =
      arguments->find(flutter::EncodableValue(std::string("accent")));
  if (dark_it != arguments->end() && background_it != arguments->end() &&
      foreground_it != arguments->end() && accent_it != arguments->end()) {
    const auto read_int = [](const flutter::EncodableValue& value)
        -> std::optional<int> {
      if (const auto* value32 = std::get_if<int32_t>(&value)) {
        return *value32;
      }
      if (const auto* value64 = std::get_if<int64_t>(&value)) {
        return static_cast<int>(*value64);
      }
      return std::nullopt;
    };
    const auto* dark = std::get_if<bool>(&dark_it->second);
    const auto background = read_int(background_it->second);
    const auto foreground = read_int(foreground_it->second);
    const auto accent = read_int(accent_it->second);
    if (dark && background && foreground && accent) {
      transfer_progress_window_->SetTheme(*dark, *background, *foreground,
                                          *accent);
    }
  }

  if (call.method_name() == "showWaiting") {
    const auto accept_it =
        arguments->find(flutter::EncodableValue(std::string("acceptLabel")));
    const auto decline_it =
        arguments->find(flutter::EncodableValue(std::string("declineLabel")));
    if (accept_it == arguments->end() || decline_it == arguments->end()) {
      result->Error("bad_arguments", "Missing acceptLabel or declineLabel");
      return;
    }
    const auto* accept_label = std::get_if<std::string>(&accept_it->second);
    const auto* decline_label = std::get_if<std::string>(&decline_it->second);
    if (!accept_label || !decline_label) {
      result->Error("bad_arguments",
                    "acceptLabel and declineLabel must be strings");
      return;
    }
    transfer_progress_window_->ShowWaiting(*title, *text, *accept_label,
                                           *decline_label);
    result->Success();
    return;
  }

  const auto progress_it =
      arguments->find(flutter::EncodableValue(std::string("progress")));
  if (progress_it == arguments->end()) {
    result->Error("bad_arguments", "Missing progress");
    return;
  }

  double progress = 0.0;
  if (const auto* value = std::get_if<double>(&progress_it->second)) {
    progress = *value;
  } else if (const auto* value32 =
                 std::get_if<int32_t>(&progress_it->second)) {
    progress = static_cast<double>(*value32);
  } else if (const auto* value64 =
                 std::get_if<int64_t>(&progress_it->second)) {
    progress = static_cast<double>(*value64);
  } else {
    result->Error("bad_arguments", "progress must be a number");
    return;
  }

  if (call.method_name() == "showProgress") {
    transfer_progress_window_->Show(*title, *text, progress);
  } else if (call.method_name() == "updateProgress") {
    transfer_progress_window_->Update(*title, *text, progress);
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
