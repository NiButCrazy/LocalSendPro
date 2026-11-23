#include "transfer_progress_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kClassName[] = L"LocalSendTransferProgressWindow";

constexpr int kProgressHeight = 112;
constexpr int kWaitingHeight = 112;
constexpr int kPinHeight = 220;

constexpr UINT_PTR kAnimationTimerId = 1;
constexpr int kAnimationIntervalMs = 15;
constexpr int kAnimationDurationMs = 180;
constexpr int kAnimationSlide = 10;  // logical pixels, visual offset only
constexpr BYTE kWindowAlpha = 255;   // fully opaque

// Smooths the progress bar between updates from the Dart side (every ~100 ms).
// The factor is deliberately small so the bar keeps moving continuously instead
// of catching up in a burst and then standing still until the next update.
constexpr UINT_PTR kProgressTimerId = 2;
constexpr int kProgressIntervalMs = 16;
constexpr double kProgressEase = 0.12;

double EaseOutCubic(double t) {
  const double remaining = 1.0 - t;
  return 1.0 - remaining * remaining * remaining;
}

COLORREF ToColorRef(int argb) {
  const auto value = static_cast<uint32_t>(argb);
  return RGB((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

COLORREF AdjustColor(COLORREF color, int delta) {
  const auto channel = [delta](int value) {
    const int shifted = value + delta;
    return shifted < 0 ? 0 : (shifted > 255 ? 255 : shifted);
  };
  return RGB(channel(GetRValue(color)), channel(GetGValue(color)),
             channel(GetBValue(color)));
}

bool IsLightColor(COLORREF color) {
  const int luminance = (GetRValue(color) * 299 + GetGValue(color) * 587 +
                         GetBValue(color) * 114) /
                        1000;
  return luminance > 160;
}

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                       static_cast<int>(wide.size()), nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

// The native window has no access to the Flutter translations, so the PIN error
// falls back to the system language, like the context menu title does.
std::wstring PinErrorMessage() {
  const LANGID language = GetUserDefaultUILanguage();
  if (PRIMARYLANGID(language) == LANG_CHINESE) {
    return L"\u9519\u8bef\u7684 PIN\uff0c\u8bf7\u91cd\u8bd5\u3002";
  }
  return L"Incorrect PIN. Please try again.";
}

}  // namespace

TransferProgressWindow::TransferProgressWindow(HWND owner) : owner_(owner) {}

TransferProgressWindow::~TransferProgressWindow() {
  Destroy();
}

void TransferProgressWindow::SetActionHandler(
    std::function<void(const std::string&)> handler) {
  action_handler_ = std::move(handler);
}

void TransferProgressWindow::SetPinHandler(
    std::function<void(const std::optional<std::string>&)> handler) {
  pin_handler_ = std::move(handler);
}

bool TransferProgressWindow::IsPinActive() const { return mode_ == Mode::pin; }

void TransferProgressWindow::SetTheme(bool dark, int background, int foreground,
                                      int accent) {
  dark_ = dark;
  background_color_ = ToColorRef(background);
  foreground_color_ = ToColorRef(foreground);
  accent_color_ = ToColorRef(accent);
  secondary_color_ = dark ? RGB(180, 180, 180) : RGB(100, 100, 100);
  RecreateBrushes();
  if (hwnd_) {
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void TransferProgressWindow::Show(const std::string& title,
                                  const std::string& text,
                                  double progress) {
  if (!EnsureCreated()) {
    return;
  }
  if (mode_ == Mode::pin) {
    // The caller replaced the PIN prompt with progress; tell Dart the PIN was canceled.
    CancelPin();
  }
  mode_ = Mode::progress;
  ResizeForMode();
  SetContent(title, text, progress);
  if (!user_positioned_) {
    PositionBottomRight();
  }
  const bool was_visible = IsWindowVisible(hwnd_) != FALSE;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  if (!was_visible) {
    StartShowAnimation();
  }
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void TransferProgressWindow::Update(const std::string& title,
                                    const std::string& text,
                                    double progress) {
  if (!EnsureCreated()) {
    return;
  }
  if (mode_ == Mode::pin) {
    // Progress of other transfers must not overwrite the PIN prompt.
    return;
  }
  if (mode_ != Mode::progress) {
    mode_ = Mode::progress;
    ResizeForMode();
  }
  SetContent(title, text, progress);
  if (!IsWindowVisible(hwnd_)) {
    StartShowAnimation();
  }
}

void TransferProgressWindow::ShowWaiting(const std::string& title,
                                         const std::string& text,
                                         const std::string& accept_label,
                                         const std::string& decline_label) {
  if (!EnsureCreated()) {
    return;
  }
  if (mode_ == Mode::pin) {
    // An incoming request takes the window over; the sending session is canceled.
    CancelPin();
  }
  mode_ = Mode::waiting;
  accept_label_ = Utf8ToWide(accept_label);
  decline_label_ = Utf8ToWide(decline_label);
  SetContent(title, text, 0.0);
  ResizeForMode();
  if (!user_positioned_) {
    PositionBottomRight();
  }
  const bool was_visible = IsWindowVisible(hwnd_) != FALSE;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  if (!was_visible) {
    StartShowAnimation();
  }
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void TransferProgressWindow::ShowPin(const std::string& title,
                                     const std::string& text, bool invalid,
                                     const std::string& confirm_label,
                                     const std::string& cancel_label) {
  if (!EnsureCreated()) {
    return;
  }

  const bool already_pin = mode_ == Mode::pin;
  if (!already_pin) {
    mode_ = Mode::pin;
    // A PIN needs keyboard focus, so the window must be activatable while it is shown.
    const LONG_PTR ex_style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    SetWindowLongPtrW(hwnd_, GWL_EXSTYLE, ex_style & ~static_cast<LONG_PTR>(WS_EX_NOACTIVATE));
    CreatePinEdit();
  }

  pin_confirm_label_ = Utf8ToWide(confirm_label);
  pin_cancel_label_ = Utf8ToWide(cancel_label);
  pin_error_ = invalid ? PinErrorMessage() : std::wstring();

  SetContent(title, text, 0.0);
  // SetContent starts the progress bar animation; a PIN window has no bar.
  KillTimer(hwnd_, kProgressTimerId);

  if (!already_pin) {
    ResizeForMode();
  }
  if (!user_positioned_) {
    PositionBottomRight();
  }

  const bool was_visible = IsWindowVisible(hwnd_) != FALSE;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  if (!was_visible) {
    StartShowAnimation();
  }
  if (pin_edit_) {
    SetWindowTextW(pin_edit_, L"");
    ShowWindow(pin_edit_, SW_SHOW);
  }
  SetForegroundWindow(hwnd_);
  if (pin_edit_) {
    SetFocus(pin_edit_);
  }
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void TransferProgressWindow::Hide() {
  if (mode_ == Mode::pin) {
    // Hiding cancels the prompt, otherwise the Dart future would never complete.
    CancelPin();
  }
  if (hwnd_) {
    KillTimer(hwnd_, kProgressTimerId);
  }
  StartHideAnimation();
}

void TransferProgressWindow::HideProgressOnly() {
  if (mode_ == Mode::pin) {
    return;
  }
  Hide();
}

void TransferProgressWindow::Destroy() {
  // Shutdown: the Dart side is going away, so never invoke the handler.
  pin_handler_ = nullptr;
  ExitPinMode();
  if (hwnd_) {
    KillTimer(hwnd_, kProgressTimerId);
    HWND window = hwnd_;
    hwnd_ = nullptr;
    DestroyWindow(window);
  }
  ReleaseResources();
}

bool TransferProgressWindow::EnsureCreated() {
  if (hwnd_) {
    return true;
  }

  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.style = CS_DROPSHADOW;
  window_class.lpfnWndProc = WndProc;
  window_class.hInstance = GetModuleHandleW(nullptr);
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kClassName;
  if (!RegisterClassExW(&window_class) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      kClassName, L"", WS_POPUP, 0, 0, Scale(360), Scale(HeightForMode()),
      nullptr, nullptr, GetModuleHandleW(nullptr), this);
  if (!hwnd_) {
    return false;
  }

  const DWM_WINDOW_CORNER_PREFERENCE corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));

  UpdateDpiAndFonts();
  RecreateBrushes();
  ResizeForMode();
  return true;
}

void TransferProgressWindow::SetContent(const std::string& title,
                                        const std::string& text,
                                        double progress) {
  title_ = Utf8ToWide(title);
  text_lines_.clear();
  const std::wstring wide_text = Utf8ToWide(text);
  size_t start = 0;
  while (start <= wide_text.size()) {
    const size_t end = wide_text.find(L'\n', start);
    if (end == std::wstring::npos) {
      text_lines_.push_back(wide_text.substr(start));
      break;
    }
    text_lines_.push_back(wide_text.substr(start, end - start));
    start = end + 1;
  }
  progress_ = std::clamp(progress, 0.0, 1.0);
  if (progress_ < displayed_progress_) {
    // A new transfer restarts from zero; jump back instead of sliding backwards.
    displayed_progress_ = progress_;
  }
  UpdateLayoutMetrics();
  if (hwnd_) {
    StartProgressAnimation();
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void TransferProgressWindow::UpdateDpiAndFonts() {
  dpi_ = hwnd_ ? GetDpiForWindow(hwnd_) : 96;
  if (dpi_ == 0) {
    dpi_ = 96;
  }

  if (title_font_) {
    DeleteObject(title_font_);
  }
  if (text_font_) {
    DeleteObject(text_font_);
  }
  if (small_font_) {
    DeleteObject(small_font_);
  }
  if (button_font_) {
    DeleteObject(button_font_);
  }

  title_font_ = CreateFontW(
      -MulDiv(12, static_cast<int>(dpi_), 72), 0, 0, 0, FW_SEMIBOLD, FALSE,
      FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  text_font_ = CreateFontW(
      -MulDiv(12, static_cast<int>(dpi_), 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
      FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  small_font_ = CreateFontW(
      -MulDiv(10, static_cast<int>(dpi_), 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
      FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  button_font_ = CreateFontW(
      -MulDiv(10, static_cast<int>(dpi_), 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
      FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

  if (pin_edit_ && text_font_) {
    SendMessageW(pin_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(text_font_),
                 TRUE);
  }
}

void TransferProgressWindow::RecreateBrushes() {
  if (background_brush_) {
    DeleteObject(background_brush_);
  }
  if (border_brush_) {
    DeleteObject(border_brush_);
  }
  if (track_brush_) {
    DeleteObject(track_brush_);
  }
  if (fill_brush_) {
    DeleteObject(fill_brush_);
  }
  if (button_brush_) {
    DeleteObject(button_brush_);
  }
  if (button_hover_brush_) {
    DeleteObject(button_hover_brush_);
  }
  if (primary_button_hover_brush_) {
    DeleteObject(primary_button_hover_brush_);
  }
  if (pin_field_brush_) {
    DeleteObject(pin_field_brush_);
  }

  background_brush_ = CreateSolidBrush(background_color_);
  border_brush_ =
      CreateSolidBrush(dark_ ? RGB(70, 70, 70) : RGB(226, 226, 226));
  track_brush_ =
      CreateSolidBrush(dark_ ? RGB(64, 64, 64) : RGB(228, 228, 228));
  fill_brush_ = CreateSolidBrush(accent_color_);
  button_brush_ =
      CreateSolidBrush(dark_ ? RGB(58, 58, 58) : RGB(236, 236, 236));
  button_hover_brush_ =
      CreateSolidBrush(dark_ ? RGB(76, 76, 76) : RGB(224, 224, 224));
  primary_button_hover_brush_ =
      CreateSolidBrush(AdjustColor(accent_color_, -16));
  pin_field_brush_ =
      CreateSolidBrush(dark_ ? RGB(45, 45, 45) : RGB(255, 255, 255));
}

void TransferProgressWindow::PositionBottomRight() {
  HMONITOR monitor = MonitorFromWindow(owner_, MONITOR_DEFAULTTONEAREST);
  if (!monitor) {
    monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
  }

  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return;
  }

  const int width = Scale(360);
  const int height = Scale(HeightForMode());
  const int margin = Scale(12);
  // Leave some room above the work area so an auto-hiding taskbar cannot cover the card.
  const int bottom_offset = Scale(48);
  anchor_right_ = monitor_info.rcWork.right - margin;
  anchor_bottom_ = monitor_info.rcWork.bottom - margin - bottom_offset;
  anchor_valid_ = true;
  SetWindowPos(hwnd_, HWND_TOPMOST, anchor_right_ - width,
               anchor_bottom_ - height, width, height, SWP_NOACTIVATE);
}

void TransferProgressWindow::ResizeForMode() {
  if (!hwnd_) {
    return;
  }

  const int width = Scale(360);
  const int height = Scale(HeightForMode());

  if (!user_positioned_ && anchor_valid_) {
    // Keep the anchored bottom-right corner fixed instead of reading the current
    // rect, which would accumulate rounding drift while the height changes.
    SetWindowPos(hwnd_, nullptr, anchor_right_ - width,
                 anchor_bottom_ - height, width, height,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  } else {
    RECT current = {};
    GetWindowRect(hwnd_, &current);
    if (current.right > current.left && current.bottom > current.top) {
      // Keep the bottom-right corner fixed when the mode changes the height.
      SetWindowPos(hwnd_, nullptr, current.right - width,
                   current.bottom - height, width, height,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    } else {
      SetWindowPos(hwnd_, nullptr, 0, 0, width, height,
                   SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }
  UpdateLayoutMetrics();
}

void TransferProgressWindow::UpdateLayoutMetrics() {
  if (!hwnd_) {
    return;
  }

  RECT client = {};
  GetClientRect(hwnd_, &client);
  const int width = client.right;
  const int height = client.bottom;
  close_rect_ = {width - Scale(30), Scale(3), width - Scale(6), Scale(27)};

  if (mode_ == Mode::waiting) {
    const int padding = Scale(16);
    const int gap = Scale(10);
    const int button_height = Scale(32);
    const int button_top = height - Scale(14) - button_height;
    const int button_width = (width - padding * 2 - gap) / 2;
    decline_rect_ = {padding, button_top, padding + button_width,
                     button_top + button_height};
    accept_rect_ = {padding + button_width + gap, button_top, width - padding,
                    button_top + button_height};
    pin_edit_rect_ = {};
  } else if (mode_ == Mode::pin) {
    const int padding = Scale(16);
    const int gap = Scale(10);
    const int button_height = Scale(32);
    const int button_top = height - Scale(14) - button_height;
    const int button_width = (width - padding * 2 - gap) / 2;
    decline_rect_ = {padding, button_top, padding + button_width,
                     button_top + button_height};
    accept_rect_ = {padding + button_width + gap, button_top, width - padding,
                    button_top + button_height};
    pin_edit_rect_ = {padding, Scale(124), width - padding, Scale(150)};
    if (pin_edit_) {
      MoveWindow(pin_edit_, pin_edit_rect_.left, pin_edit_rect_.top,
                 pin_edit_rect_.right - pin_edit_rect_.left,
                 pin_edit_rect_.bottom - pin_edit_rect_.top, TRUE);
    }
  } else {
    accept_rect_ = {};
    decline_rect_ = {};
    pin_edit_rect_ = {};
  }
}

void TransferProgressWindow::Paint(HDC dc) {
  RECT client = {};
  GetClientRect(hwnd_, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  if (width <= 0 || height <= 0) {
    return;
  }

  UpdateLayoutMetrics();

  HDC memory = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, width, height);
  HGDIOBJ old_bitmap = SelectObject(memory, bitmap);

  FillRect(memory, &client, background_brush_);
  FrameRect(memory, &client, border_brush_);

  SetBkMode(memory, TRANSPARENT);
  SetTextColor(memory, foreground_color_);

  if (title_font_) {
    SelectObject(memory, title_font_);
  }
  RECT title_rect = {Scale(16), Scale(10), width - Scale(40), Scale(34)};
  DrawTextPair(memory, title_, title_rect, true);

  if (mode_ == Mode::waiting) {
    PaintWaiting(memory, width, height);
  } else if (mode_ == Mode::pin) {
    PaintPin(memory, width, height);
  } else {
    PaintProgress(memory, width, height);
  }

  PaintCloseButton(memory);

  BitBlt(dc, 0, 0, width, height, memory, 0, 0, SRCCOPY);

  SelectObject(memory, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

void TransferProgressWindow::PaintProgress(HDC dc, int width, int height) {
  const int text_left = Scale(16);
  const int text_right = width - Scale(16);
  const int track_top = Scale(66);
  const int track_bottom = track_top + Scale(6);

  HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
  HGDIOBJ old_brush = SelectObject(dc, track_brush_);
  RoundRect(dc, text_left, track_top, text_right, track_bottom, Scale(3),
            Scale(3));

  const int fill_right =
      text_left + static_cast<int>((text_right - text_left) * displayed_progress_);
  if (fill_right > text_left) {
    SelectObject(dc, fill_brush_);
    RoundRect(dc, text_left, track_top, fill_right, track_bottom, Scale(3),
              Scale(3));
  }
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);

  SetTextColor(dc, secondary_color_);
  if (!text_lines_.empty()) {
    if (text_font_) {
      SelectObject(dc, text_font_);
    }
    RECT line_rect = {text_left, Scale(40), text_right, Scale(62)};
    DrawTextPair(dc, text_lines_[0], line_rect, true);
  }
  if (text_lines_.size() > 1) {
    if (small_font_) {
      SelectObject(dc, small_font_);
    }
    RECT line_rect = {text_left, Scale(78), text_right, Scale(98)};
    DrawTextPair(dc, text_lines_[1], line_rect, false);
  }
}

void TransferProgressWindow::PaintWaiting(HDC dc, int width, int height) {
  if (small_font_) {
    SelectObject(dc, small_font_);
  }
  SetTextColor(dc, secondary_color_);
  int y = Scale(38);
  for (const std::wstring& line : text_lines_) {
    if (y + Scale(20) > height - Scale(54)) {
      break;
    }
    RECT line_rect = {Scale(16), y, width - Scale(16), y + Scale(20)};
    DrawTextW(dc, line.c_str(), -1, &line_rect,
              DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX |
                  DT_NOCLIP);
    y += Scale(20);
  }

  PaintButton(dc, decline_rect_, decline_label_, false, hovered_control_ == 2);
  PaintButton(dc, accept_rect_, accept_label_, true, hovered_control_ == 1);
}

void TransferProgressWindow::PaintPin(HDC dc, int width, int height) {
  if (small_font_) {
    SelectObject(dc, small_font_);
  }
  SetTextColor(dc, secondary_color_);
  int y = Scale(38);
  for (const std::wstring& line : text_lines_) {
    if (y + Scale(20) > Scale(98)) {
      break;
    }
    RECT line_rect = {Scale(16), y, width - Scale(16), y + Scale(20)};
    DrawTextW(dc, line.c_str(), -1, &line_rect,
              DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX |
                  DT_NOCLIP);
    y += Scale(20);
  }

  if (!pin_error_.empty()) {
    SetTextColor(dc, RGB(209, 52, 56));
    RECT error_rect = {Scale(16), Scale(98), width - Scale(16), Scale(118)};
    DrawTextW(dc, pin_error_.c_str(), -1, &error_rect,
              DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX |
                  DT_NOCLIP);
    SetTextColor(dc, secondary_color_);
  }

  PaintButton(dc, decline_rect_, pin_cancel_label_, false, hovered_control_ == 2);
  PaintButton(dc, accept_rect_, pin_confirm_label_, true, hovered_control_ == 1);
}

void TransferProgressWindow::DrawTextPair(HDC dc, const std::wstring& line,
                                          const RECT& rect, bool primary) {
  const UINT flags =
      DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX | DT_NOCLIP;
  const size_t tab = line.find(L'\t');
  const std::wstring left =
      tab == std::wstring::npos ? line : line.substr(0, tab);
  const std::wstring right =
      tab == std::wstring::npos ? std::wstring() : line.substr(tab + 1);

  const size_t marker = left.find(L'\x01');
  const std::wstring main =
      marker == std::wstring::npos ? left : left.substr(0, marker);
  const std::wstring muted =
      marker == std::wstring::npos ? std::wstring() : left.substr(marker + 1);

  RECT left_rect = rect;
  SIZE main_size = {};
  if (!main.empty()) {
    SetTextColor(dc, primary ? foreground_color_ : secondary_color_);
    DrawTextW(dc, main.c_str(), -1, &left_rect, DT_LEFT | flags);
    GetTextExtentPoint32W(dc, main.c_str(), static_cast<int>(main.size()),
                          &main_size);
  }

  if (!muted.empty()) {
    SetTextColor(dc, secondary_color_);
    HGDIOBJ previous_font = small_font_ ? SelectObject(dc, small_font_) : nullptr;
    RECT muted_rect = left_rect;
    muted_rect.left += main_size.cx + Scale(6);
    DrawTextW(dc, muted.c_str(), -1, &muted_rect, DT_LEFT | flags);
    if (previous_font) {
      SelectObject(dc, previous_font);
    }
  }

  if (!right.empty()) {
    SetTextColor(dc, secondary_color_);
    RECT right_rect = rect;
    DrawTextW(dc, right.c_str(), -1, &right_rect, DT_RIGHT | flags);
  }
}

void TransferProgressWindow::PaintButton(HDC dc, const RECT& rect,
                                         const std::wstring& label, bool primary,
                                         bool hovered) {
  HBRUSH background = nullptr;
  if (primary) {
    background = hovered ? primary_button_hover_brush_ : fill_brush_;
  } else {
    background = hovered ? button_hover_brush_ : button_brush_;
  }

  HGDIOBJ old_brush = SelectObject(dc, background);
  HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, Scale(6),
            Scale(6));
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);

  if (!primary) {
    HGDIOBJ outline_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
    HPEN border_pen = CreatePen(
        PS_SOLID, 1, dark_ ? RGB(96, 96, 96) : RGB(200, 200, 200));
    HGDIOBJ old_border_pen = SelectObject(dc, border_pen);
    RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, Scale(6),
              Scale(6));
    SelectObject(dc, old_border_pen);
    DeleteObject(border_pen);
    SelectObject(dc, outline_brush);
  }

  if (button_font_) {
    SelectObject(dc, button_font_);
  } else if (text_font_) {
    SelectObject(dc, text_font_);
  }
  SetTextColor(dc, primary
                       ? (IsLightColor(accent_color_) ? RGB(20, 20, 20)
                                                      : RGB(255, 255, 255))
                       : foreground_color_);
  RECT text_rect = rect;
  DrawTextW(dc, label.c_str(), -1, &text_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                DT_NOPREFIX);
}

void TransferProgressWindow::PaintCloseButton(HDC dc) {
  if (!mouse_inside_) {
    return;
  }

  HPEN pen = CreatePen(PS_SOLID, 1, foreground_color_);
  HGDIOBJ old = SelectObject(dc, pen);
  const int inset = Scale(8);
  const int center_y = (close_rect_.top + close_rect_.bottom) / 2;
  MoveToEx(dc, close_rect_.left + inset, center_y, nullptr);
  LineTo(dc, close_rect_.right - inset, center_y);
  SelectObject(dc, old);
  DeleteObject(pen);
}

int TransferProgressWindow::HitTest(POINT point) const {
  if (mouse_inside_ && PtInRect(&close_rect_, point)) {
    return 3;
  }
  if (mode_ == Mode::waiting || mode_ == Mode::pin) {
    if (PtInRect(&accept_rect_, point)) {
      return 1;
    }
    if (PtInRect(&decline_rect_, point)) {
      return 2;
    }
  }
  return 0;
}

void TransferProgressWindow::NotifyAction(const char* action) {
  if (action_handler_) {
    action_handler_(action);
  }
}

void TransferProgressWindow::StartProgressAnimation() {
  if (!hwnd_) {
    return;
  }
  if (!IsWindowVisible(hwnd_) ||
      std::abs(progress_ - displayed_progress_) < 0.001) {
    // Jump to the target while the window is still hidden, so the fade-in does
    // not start from a stale value.
    displayed_progress_ = progress_;
    return;
  }
  SetTimer(hwnd_, kProgressTimerId, kProgressIntervalMs, nullptr);
}

LRESULT CALLBACK TransferProgressWindow::PinEditProc(HWND window,
                                                     UINT message,
                                                     WPARAM wparam,
                                                     LPARAM lparam) {
  auto* self = reinterpret_cast<TransferProgressWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self) {
    if (message == WM_KEYDOWN) {
      if (wparam == VK_RETURN) {
        self->SubmitPin();
        return 0;
      }
      if (wparam == VK_ESCAPE) {
        self->CancelPin();
        return 0;
      }
    } else if (message == WM_CHAR && wparam == L'\r') {
      // The character must not reach the edit control after VK_RETURN was handled.
      return 0;
    }
    if (self->pin_edit_proc_) {
      return CallWindowProcW(self->pin_edit_proc_, window, message, wparam,
                             lparam);
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void TransferProgressWindow::CreatePinEdit() {
  if (!hwnd_ || pin_edit_) {
    return;
  }

  pin_edit_ = CreateWindowExW(
      0, L"EDIT", L"",
      WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_PASSWORD | WS_TABSTOP, 0, 0,
      10, 10, hwnd_, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!pin_edit_) {
    return;
  }

  SendMessageW(pin_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(text_font_),
               TRUE);
  SendMessageW(pin_edit_, EM_SETLIMITTEXT, 32, 0);
  SendMessageW(pin_edit_, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN,
               MAKELPARAM(Scale(6), Scale(6)));
  SetWindowLongPtrW(pin_edit_, GWLP_USERDATA,
                    reinterpret_cast<LONG_PTR>(this));
  pin_edit_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
      pin_edit_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(PinEditProc)));
}

void TransferProgressWindow::SubmitPin() {
  if (mode_ != Mode::pin || !pin_edit_) {
    return;
  }

  const int length = GetWindowTextLengthW(pin_edit_);
  if (length <= 0) {
    // An empty PIN is never submitted; the user can still cancel.
    return;
  }

  std::wstring value(static_cast<size_t>(length) + 1, L'\0');
  GetWindowTextW(pin_edit_, value.data(), length + 1);
  value.resize(static_cast<size_t>(length));

  auto handler = std::move(pin_handler_);
  pin_handler_ = nullptr;
  ExitPinMode();
  if (handler) {
    handler(WideToUtf8(value));
  }
}

void TransferProgressWindow::CancelPin() {
  if (mode_ != Mode::pin) {
    return;
  }

  auto handler = std::move(pin_handler_);
  pin_handler_ = nullptr;
  ExitPinMode();
  if (handler) {
    // The sender treats an empty answer as "canceled".
    handler(std::nullopt);
  }
}

void TransferProgressWindow::ExitPinMode() {
  if (pin_edit_) {
    ShowWindow(pin_edit_, SW_HIDE);
    DestroyWindow(pin_edit_);
    pin_edit_ = nullptr;
    pin_edit_proc_ = nullptr;
  }
  if (hwnd_) {
    // Back to a non-activating popup: only the PIN prompt needs focus.
    const LONG_PTR ex_style = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    SetWindowLongPtrW(hwnd_, GWL_EXSTYLE,
                      ex_style | static_cast<LONG_PTR>(WS_EX_NOACTIVATE));
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
  mode_ = Mode::progress;
  pin_error_.clear();
  pin_confirm_label_.clear();
  pin_cancel_label_.clear();
  pin_handler_ = nullptr;
}

void TransferProgressWindow::StartShowAnimation() {
  if (!hwnd_) {
    return;
  }

  if (animating_) {
    KillTimer(hwnd_, kAnimationTimerId);
    animating_ = false;
    hiding_ = false;
  }

  // The slide is a visual offset around the resting position. Deriving the base
  // from the anchor (instead of the current rect) keeps positioning independent
  // from the animation, so repeated show/hide cycles cannot drift.
  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  const int width = rect.right > rect.left ? rect.right - rect.left : Scale(360);
  const int height = rect.bottom > rect.top ? rect.bottom - rect.top : Scale(HeightForMode());
  if (!user_positioned_ && anchor_valid_) {
    animation_base_x_ = anchor_right_ - width;
    animation_base_y_ = anchor_bottom_ - height;
  } else {
    animation_base_x_ = rect.left;
    animation_base_y_ = rect.top;
  }

  SetLayeredWindowAttributes(hwnd_, 0, 0, LWA_ALPHA);
  SetWindowPos(hwnd_, HWND_TOPMOST, animation_base_x_,
               animation_base_y_ + Scale(kAnimationSlide), width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);

  animation_step_ = 0;
  animating_ = true;
  hiding_ = false;
  SetTimer(hwnd_, kAnimationTimerId, kAnimationIntervalMs, nullptr);
}

void TransferProgressWindow::StartHideAnimation() {
  if (!hwnd_ || !IsWindowVisible(hwnd_)) {
    return;
  }

  if (animating_) {
    KillTimer(hwnd_, kAnimationTimerId);
    animating_ = false;
    hiding_ = false;
    SetLayeredWindowAttributes(hwnd_, 0, kWindowAlpha, LWA_ALPHA);
  }

  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  const int width = rect.right > rect.left ? rect.right - rect.left : Scale(360);
  const int height = rect.bottom > rect.top ? rect.bottom - rect.top : Scale(HeightForMode());
  if (!user_positioned_ && anchor_valid_) {
    animation_base_x_ = anchor_right_ - width;
    animation_base_y_ = anchor_bottom_ - height;
  } else {
    animation_base_x_ = rect.left;
    animation_base_y_ = rect.top;
  }
  // Start the fade from the resting position even if the last cycle left the
  // hidden window below its anchor.
  SetWindowPos(hwnd_, nullptr, animation_base_x_, animation_base_y_, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

  animation_step_ = 0;
  animating_ = true;
  hiding_ = true;
  SetTimer(hwnd_, kAnimationTimerId, kAnimationIntervalMs, nullptr);
}

void TransferProgressWindow::ReleaseResources() {
  if (title_font_) {
    DeleteObject(title_font_);
    title_font_ = nullptr;
  }
  if (text_font_) {
    DeleteObject(text_font_);
    text_font_ = nullptr;
  }
  if (small_font_) {
    DeleteObject(small_font_);
    small_font_ = nullptr;
  }
  if (button_font_) {
    DeleteObject(button_font_);
    button_font_ = nullptr;
  }
  if (background_brush_) {
    DeleteObject(background_brush_);
    background_brush_ = nullptr;
  }
  if (border_brush_) {
    DeleteObject(border_brush_);
    border_brush_ = nullptr;
  }
  if (track_brush_) {
    DeleteObject(track_brush_);
    track_brush_ = nullptr;
  }
  if (fill_brush_) {
    DeleteObject(fill_brush_);
    fill_brush_ = nullptr;
  }
  if (button_brush_) {
    DeleteObject(button_brush_);
    button_brush_ = nullptr;
  }
  if (button_hover_brush_) {
    DeleteObject(button_hover_brush_);
    button_hover_brush_ = nullptr;
  }
  if (primary_button_hover_brush_) {
    DeleteObject(primary_button_hover_brush_);
    primary_button_hover_brush_ = nullptr;
  }
  if (pin_field_brush_) {
    DeleteObject(pin_field_brush_);
    pin_field_brush_ = nullptr;
  }
}

int TransferProgressWindow::Scale(int value) const {
  return MulDiv(value, static_cast<int>(dpi_), 96);
}

int TransferProgressWindow::HeightForMode() const {
  switch (mode_) {
    case Mode::waiting:
      return kWaitingHeight;
    case Mode::pin:
      return kPinHeight;
    case Mode::progress:
      return kProgressHeight;
  }
  return kProgressHeight;
}

LRESULT CALLBACK TransferProgressWindow::WndProc(HWND window, UINT message,
                                                 WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    auto* self =
        reinterpret_cast<TransferProgressWindow*>(create->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = window;
  }

  auto* self = reinterpret_cast<TransferProgressWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (self) {
    return self->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT TransferProgressWindow::MessageHandler(HWND window, UINT message,
                                               WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // A PIN prompt needs focus; everything else stays out of the way.
      return mode_ == Mode::pin ? MA_ACTIVATE : MA_NOACTIVATE;
    case WM_CTLCOLOREDIT: {
      HDC dc = reinterpret_cast<HDC>(wparam);
      if (pin_edit_ && reinterpret_cast<HWND>(lparam) == pin_edit_) {
        SetTextColor(dc, foreground_color_);
        SetBkColor(dc, dark_ ? RGB(45, 45, 45) : RGB(255, 255, 255));
        return reinterpret_cast<LRESULT>(pin_field_brush_);
      }
      break;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_TIMER:
      if (wparam == kProgressTimerId) {
        const double delta = progress_ - displayed_progress_;
        if (std::abs(delta) < 0.005) {
          displayed_progress_ = progress_;
          KillTimer(window, kProgressTimerId);
        } else {
          displayed_progress_ += delta * kProgressEase;
        }
        InvalidateRect(window, nullptr, FALSE);
        return 0;
      }
      if (wparam == kAnimationTimerId) {
        animation_step_++;
        const int elapsed = animation_step_ * kAnimationIntervalMs;
        const double raw = std::min(
            1.0, static_cast<double>(elapsed) / kAnimationDurationMs);
        const double eased = EaseOutCubic(raw);
        const int slide = static_cast<int>(Scale(kAnimationSlide) * eased);

        if (hiding_) {
          SetLayeredWindowAttributes(
              window, 0, static_cast<BYTE>(kWindowAlpha * (1.0 - eased)),
              LWA_ALPHA);
          SetWindowPos(window, nullptr, animation_base_x_,
                       animation_base_y_ + slide, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
          if (raw >= 1.0) {
            KillTimer(window, kAnimationTimerId);
            ShowWindow(window, SW_HIDE);
            SetLayeredWindowAttributes(window, 0, kWindowAlpha, LWA_ALPHA);
            animating_ = false;
            hiding_ = false;
          }
        } else {
          SetLayeredWindowAttributes(window, 0,
                                     static_cast<BYTE>(kWindowAlpha * eased),
                                     LWA_ALPHA);
          SetWindowPos(window, nullptr, animation_base_x_,
                       animation_base_y_ + Scale(kAnimationSlide) - slide, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
          if (raw >= 1.0) {
            KillTimer(window, kAnimationTimerId);
            SetLayeredWindowAttributes(window, 0, kWindowAlpha, LWA_ALPHA);
            animating_ = false;
          }
        }
        return 0;
      }
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC dc = BeginPaint(window, &paint);
      Paint(dc);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_MOUSEMOVE: {
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT track = {};
        track.cbSize = sizeof(track);
        track.dwFlags = TME_LEAVE;
        track.hwndTrack = window;
        TrackMouseEvent(&track);
        tracking_mouse_ = true;
        mouse_inside_ = true;
        InvalidateRect(window, nullptr, FALSE);
      }

      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      UpdateLayoutMetrics();
      const int hit = HitTest(point);
      if (hit != hovered_control_) {
        hovered_control_ = hit;
        InvalidateRect(window, nullptr, FALSE);
      }

      if (pressed_ && !dragging_) {
        const int dx = point.x - press_point_.x;
        const int dy = point.y - press_point_.y;
        const int threshold = Scale(4);
        if (dx * dx + dy * dy > threshold * threshold) {
          dragging_ = true;
          pressed_ = false;
          ReleaseCapture();
          SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        }
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      tracking_mouse_ = false;
      mouse_inside_ = false;
      hovered_control_ = 0;
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    case WM_LBUTTONDOWN: {
      UpdateLayoutMetrics();
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const int hit = HitTest(point);
      if (hit == 3) {
        if (mode_ == Mode::pin) {
          CancelPin();
        } else {
          NotifyAction("hide");
        }
        return 0;
      }
      if (hit == 1) {
        NotifyAction("accept");
        return 0;
      }
      if (hit == 2) {
        NotifyAction("decline");
        return 0;
      }

      press_point_ = point;
      pressed_ = true;
      dragging_ = false;
      SetCapture(window);
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!pressed_) {
        return 0;
      }
      pressed_ = false;
      ReleaseCapture();

      UpdateLayoutMetrics();
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (HitTest(point) == 0 && mode_ != Mode::pin) {
        NotifyAction("open");
      }
      return 0;
    }
    case WM_CAPTURECHANGED:
      pressed_ = false;
      dragging_ = false;
      return 0;
    case WM_SETCURSOR: {
      POINT point = {};
      GetCursorPos(&point);
      ScreenToClient(window, &point);
      UpdateLayoutMetrics();
      if (mouse_inside_ && HitTest(point) != 0) {
        SetCursor(LoadCursorW(nullptr, IDC_HAND));
        return TRUE;
      }
      break;
    }
    case WM_EXITSIZEMOVE:
      user_positioned_ = true;
      return 0;
    case WM_DPICHANGED: {
      dpi_ = static_cast<UINT>(HIWORD(wparam));
      UpdateDpiAndFonts();
      if (user_positioned_) {
        const RECT* suggested = reinterpret_cast<const RECT*>(lparam);
        SetWindowPos(window, nullptr, suggested->left, suggested->top,
                     suggested->right - suggested->left,
                     suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      } else {
        SetWindowPos(window, HWND_TOPMOST, 0, 0, Scale(360),
                     Scale(HeightForMode()), SWP_NOMOVE | SWP_NOACTIVATE);
        PositionBottomRight();
      }
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    case WM_SETTINGCHANGE:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    case WM_DESTROY:
      KillTimer(window, kAnimationTimerId);
      ReleaseResources();
      hwnd_ = nullptr;
      return 0;
    default:
      break;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
