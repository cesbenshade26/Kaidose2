import 'package:package_info_plus/package_info_plus.dart';

/// The app's real version, read from the installed app (it comes from
/// pubspec.yaml's `version: 1.0.0+1`, so there's nothing to update here).
/// Shown in Help & About and attached to problem reports.
class AppVersion {
  AppVersion._();

  static Future<String>? _label;

  /// "1.0.0 (1)": version and build number.
  static Future<String> label() => _label ??= _read();

  static Future<String> _read() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '';
    }
  }
}