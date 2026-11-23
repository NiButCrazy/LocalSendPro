#ifndef RUNNER_TRANSFER_PROGRESS_WINDOW_H_
#define RUNNER_TRANSFER_PROGRESS_WINDOW_H_

#include <windows.h>

#include <functional>
#include <optional>
#include <string>
#include <vector>

// An always-on-top, non-activating popup that shows transfer state.
//
// It is a plain Win32 window painted with GDI, deliberately independent of the Flutter
// window: it must stay visible while the main window is hidden in the tray, and it must not
// add a second Flutter engine. Three modes exist: a progress bar, a waiting state with
// accept/decline buttons for incoming requests, and a PIN prompt for outgoing requests that
// the receiver protects with a PIN.
class TransferProgressWindow {
 public:
  explicit TransferProgressWindow(HWND owner);
  ~TransferProgressWindow();

  TransferProgressWindow(const TransferProgressWindow&) = delete;
  TransferProgressWindow& operator=(const TransferProgressWindow&) = delete;

  void Show(const std::string& title, const std::string& text, double progress);
  void Update(const std::string& title, const std::string& text, double progress);
  void ShowWaiting(const std::string& title, const std::string& text,
                   const std::string& accept_label,
                   const std::string& decline_label);
  void ShowPin(const std::string& title, const std::string& text, bool invalid,
               const std::string& confirm_label,
               const std::string& cancel_label);
  void Hide();
  // Hides progress and waiting states. A PIN prompt is left alone.
  void HideProgressOnly();
  void Destroy();

  void SetActionHandler(std::function<void(const std::string&)> handler);
  void SetPinHandler(
      std::function<void(const std::optional<std::string>&)> handler);
  bool IsPinActive() const;
  void SetTheme(bool dark, int background, int foreground, int accent);

 private:
  enum class Mode { progress, waiting, pin };

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  static LRESULT CALLBACK PinEditProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam);

  LRESULT MessageHandler(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  bool EnsureCreated();
  void SetContent(const std::string& title, const std::string& text,
                  double progress);
  void UpdateDpiAndFonts();
  void RecreateBrushes();
  void PositionBottomRight();
  void ResizeForMode();
  void UpdateLayoutMetrics();
  void Paint(HDC dc);
  void PaintProgress(HDC dc, int width, int height);
  void PaintWaiting(HDC dc, int width, int height);
  void PaintPin(HDC dc, int width, int height);
  void PaintCloseButton(HDC dc);
  void DrawTextPair(HDC dc, const std::wstring& line, const RECT& rect,
                    bool primary);
  void PaintButton(HDC dc, const RECT& rect, const std::wstring& label,
                   bool primary, bool hovered);
  int HitTest(POINT point) const;
  void NotifyAction(const char* action);
  void CreatePinEdit();
  void SubmitPin();
  void CancelPin();
  void ExitPinMode();
  void StartShowAnimation();
  void StartHideAnimation();
  void StartProgressAnimation();
  void ReleaseResources();
  int Scale(int value) const;
  int HeightForMode() const;

  HWND owner_;
  HWND hwnd_ = nullptr;
  Mode mode_ = Mode::progress;
  std::wstring title_;
  std::vector<std::wstring> text_lines_;
  std::wstring accept_label_;
  std::wstring decline_label_;
  std::wstring pin_error_;
  std::wstring pin_confirm_label_;
  std::wstring pin_cancel_label_;
  double progress_ = 0.0;
  double displayed_progress_ = 0.0;  // animated toward progress_ for smooth updates
  UINT dpi_ = 96;
  bool user_positioned_ = false;
  bool dark_ = false;
  bool animating_ = false;
  bool hiding_ = false;
  int animation_step_ = 0;
  // Animation-only offset base, always derived from the anchor (or the dragged rect).
  int animation_base_x_ = 0;
  int animation_base_y_ = 0;
  // Fixed bottom-right anchor (outer window coordinates) while the card is not dragged.
  int anchor_right_ = 0;
  int anchor_bottom_ = 0;
  bool anchor_valid_ = false;
  COLORREF background_color_ = RGB(245, 245, 245);
  COLORREF foreground_color_ = RGB(31, 31, 31);
  COLORREF accent_color_ = RGB(0, 120, 212);
  COLORREF secondary_color_ = RGB(100, 100, 100);
  bool tracking_mouse_ = false;
  bool mouse_inside_ = false;
  bool pressed_ = false;
  bool dragging_ = false;
  POINT press_point_ = {};
  int hovered_control_ = 0;  // 0 = none, 1 = accept/confirm, 2 = decline/cancel, 3 = close
  RECT accept_rect_ = {};
  RECT decline_rect_ = {};
  RECT close_rect_ = {};
  RECT pin_edit_rect_ = {};
  HWND pin_edit_ = nullptr;
  WNDPROC pin_edit_proc_ = nullptr;
  std::function<void(const std::string&)> action_handler_;
  std::function<void(const std::optional<std::string>&)> pin_handler_;
  HFONT title_font_ = nullptr;
  HFONT text_font_ = nullptr;
  HFONT small_font_ = nullptr;
  HFONT button_font_ = nullptr;
  HBRUSH background_brush_ = nullptr;
  HBRUSH border_brush_ = nullptr;
  HBRUSH track_brush_ = nullptr;
  HBRUSH fill_brush_ = nullptr;
  HBRUSH button_brush_ = nullptr;
  HBRUSH button_hover_brush_ = nullptr;
  HBRUSH primary_button_hover_brush_ = nullptr;
  HBRUSH pin_field_brush_ = nullptr;
};

#endif  // RUNNER_TRANSFER_PROGRESS_WINDOW_H_
