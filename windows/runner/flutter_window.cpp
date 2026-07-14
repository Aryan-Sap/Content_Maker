#include "flutter_window.h"

#include <commdlg.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
constexpr wchar_t kVideoFilter[] =
    L"Video files (*.mp4;*.mov;*.mkv;*.avi;*.webm)\0"
    L"*.mp4;*.mov;*.mkv;*.avi;*.webm\0"
    L"All files (*.*)\0"
    L"*.*\0";

constexpr wchar_t kAudioFilter[] =
    L"Audio files (*.mp3;*.wav;*.m4a;*.aac;*.flac;*.ogg)\0"
    L"*.mp3;*.wav;*.m4a;*.aac;*.flac;*.ogg\0"
    L"All files (*.*)\0"
    L"*.*\0";

constexpr wchar_t kProjectFilter[] =
    L"Content Maker projects (*.cmproj)\0"
    L"*.cmproj\0"
    L"All files (*.*)\0"
    L"*.*\0";

std::optional<std::string> PickFile(HWND owner, const wchar_t* filter) {
  std::vector<wchar_t> file_path(UNICODE_STRING_MAX_CHARS, L'\0');

  OPENFILENAMEW dialog_options = {};
  dialog_options.lStructSize = sizeof(dialog_options);
  dialog_options.hwndOwner = owner;
  dialog_options.lpstrFile = file_path.data();
  dialog_options.nMaxFile = static_cast<DWORD>(file_path.size());
  dialog_options.lpstrFilter = filter;
  dialog_options.nFilterIndex = 1;
  dialog_options.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                         OFN_NOCHANGEDIR | OFN_EXPLORER;

  if (::GetOpenFileNameW(&dialog_options) != TRUE) {
    return std::nullopt;
  }

  return Utf8FromUtf16(file_path.data());
}

std::vector<std::string> PickFiles(HWND owner, const wchar_t* filter) {
  std::vector<wchar_t> file_path(65536, L'\0');

  OPENFILENAMEW dialog_options = {};
  dialog_options.lStructSize = sizeof(dialog_options);
  dialog_options.hwndOwner = owner;
  dialog_options.lpstrFile = file_path.data();
  dialog_options.nMaxFile = static_cast<DWORD>(file_path.size());
  dialog_options.lpstrFilter = filter;
  dialog_options.nFilterIndex = 1;
  dialog_options.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                         OFN_NOCHANGEDIR | OFN_EXPLORER |
                         OFN_ALLOWMULTISELECT;

  if (::GetOpenFileNameW(&dialog_options) != TRUE) {
    return {};
  }

  const wchar_t* cursor = file_path.data();
  std::wstring first = cursor;
  cursor += first.size() + 1;

  if (*cursor == L'\0') {
    return {Utf8FromUtf16(first.c_str())};
  }

  std::vector<std::string> paths;
  while (*cursor != L'\0') {
    std::wstring filename = cursor;
    std::wstring full_path = first;
    if (!full_path.empty() && full_path.back() != L'\\' &&
        full_path.back() != L'/') {
      full_path += L'\\';
    }
    full_path += filename;
    paths.push_back(Utf8FromUtf16(full_path.c_str()));
    cursor += filename.size() + 1;
  }
  return paths;
}

std::optional<std::string> SaveFile(HWND owner, const wchar_t* filter,
                                    const wchar_t* default_extension) {
  std::vector<wchar_t> file_path(UNICODE_STRING_MAX_CHARS, L'\0');

  OPENFILENAMEW dialog_options = {};
  dialog_options.lStructSize = sizeof(dialog_options);
  dialog_options.hwndOwner = owner;
  dialog_options.lpstrFile = file_path.data();
  dialog_options.nMaxFile = static_cast<DWORD>(file_path.size());
  dialog_options.lpstrFilter = filter;
  dialog_options.lpstrDefExt = default_extension;
  dialog_options.nFilterIndex = 1;
  dialog_options.Flags =
      OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR | OFN_EXPLORER | OFN_OVERWRITEPROMPT;

  if (::GetSaveFileNameW(&dialog_options) != TRUE) {
    return std::nullopt;
  }

  return Utf8FromUtf16(file_path.data());
}

std::optional<std::string> PickVideoFile(HWND owner) {
  return PickFile(owner, kVideoFilter);
}

std::vector<std::string> PickVideoFiles(HWND owner) {
  return PickFiles(owner, kVideoFilter);
}

std::optional<std::string> PickAudioFile(HWND owner) {
  return PickFile(owner, kAudioFilter);
}

std::optional<std::string> PickProjectFile(HWND owner) {
  return PickFile(owner, kProjectFilter);
}

std::optional<std::string> SaveProjectFile(HWND owner) {
  return SaveFile(owner, kProjectFilter, L"cmproj");
}
}  // namespace

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

  file_picker_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "content_maker/file_picker",
          &flutter::StandardMethodCodec::GetInstance());
  file_picker_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "pickVideo" &&
            call.method_name() != "pickVideos" &&
            call.method_name() != "pickAudio" &&
            call.method_name() != "pickProject" &&
            call.method_name() != "saveProject") {
          result->NotImplemented();
          return;
        }

        std::optional<std::string> selected_path;
        if (call.method_name() == "pickVideos") {
          const auto selected_paths = PickVideoFiles(GetHandle());
          flutter::EncodableList encoded_paths;
          for (const auto& path : selected_paths) {
            encoded_paths.push_back(flutter::EncodableValue(path));
          }
          result->Success(flutter::EncodableValue(encoded_paths));
          return;
        } else if (call.method_name() == "pickAudio") {
          selected_path = PickAudioFile(GetHandle());
        } else if (call.method_name() == "pickProject") {
          selected_path = PickProjectFile(GetHandle());
        } else if (call.method_name() == "saveProject") {
          selected_path = SaveProjectFile(GetHandle());
        } else {
          selected_path = PickVideoFile(GetHandle());
        }
        if (selected_path.has_value()) {
          result->Success(flutter::EncodableValue(selected_path.value()));
          return;
        }

        if (::CommDlgExtendedError() == 0) {
          result->Success(flutter::EncodableValue());
          return;
        }

        result->Error("dialog_error", "Could not open the video picker.");
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  file_picker_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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
