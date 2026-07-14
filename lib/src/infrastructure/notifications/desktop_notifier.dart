import 'dart:async';
import 'dart:io';

/// Fires a native desktop notification (best effort, never throws).
///
/// Windows uses a WinRT toast raised through PowerShell so no plugin or
/// package dependency is needed; macOS uses `osascript`; Linux uses
/// `notify-send`. Callers should pair this with an in-app status update —
/// the toast is a convenience for when the app is in the background during
/// long renders/uploads.
class DesktopNotifier {
  const DesktopNotifier._();

  static Future<void> show({required String title, required String body}) async {
    try {
      if (Platform.isWindows) {
        await _showWindowsToast(title: title, body: body);
      } else if (Platform.isMacOS) {
        await Process.run('osascript', <String>[
          '-e',
          'display notification "${_escapeAppleScript(body)}" '
              'with title "${_escapeAppleScript(title)}"',
        ]);
      } else if (Platform.isLinux) {
        await Process.run('notify-send', <String>[title, body]);
      }
    } catch (_) {
      // Notifications are non-critical; never let them break a render flow.
    }
  }

  static Future<void> _showWindowsToast({
    required String title,
    required String body,
  }) async {
    final script =
        r'$null = [Windows.UI.Notifications.ToastNotificationManager, '
        r'Windows.UI.Notifications, ContentType = WindowsRuntime];'
        r'$xml = New-Object Windows.Data.Xml.Dom.XmlDocument;'
        '\$xml.LoadXml(\'<toast><visual><binding template="ToastGeneric">'
        '<text>${_escapeXml(title)}</text>'
        '<text>${_escapeXml(body)}</text>'
        '</binding></visual></toast>\');'
        r'$toast = New-Object Windows.UI.Notifications.ToastNotification $xml;'
        '[Windows.UI.Notifications.ToastNotificationManager]::'
        "CreateToastNotifier('Content Maker').Show(\$toast);";
    await Process.run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      script,
    ]);
  }

  static String _escapeXml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll("'", '&apos;')
        .replaceAll('"', '&quot;');
  }

  static String _escapeAppleScript(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
}
