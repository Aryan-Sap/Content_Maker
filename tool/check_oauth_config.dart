import 'dart:convert';
import 'dart:io';

const _defaultPath = 'oauth.local.json';

const _requiredKeys = {
  'YouTube': ['YOUTUBE_CLIENT_ID', 'YOUTUBE_CLIENT_SECRET'],
  'TikTok': ['TIKTOK_CLIENT_KEY', 'TIKTOK_CLIENT_SECRET'],
};

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/check_oauth_config.dart [youtube|tiktok|all] [path]',
    );
    exitCode = 64;
    return;
  }

  final path = options.path;
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('Missing $path. Copy oauth.local.example.json to $path.');
    exitCode = 66;
    return;
  }

  final Map<String, dynamic> config;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('root must be a JSON object');
    }
    config = decoded;
  } on FormatException catch (error) {
    stderr.writeln('Could not parse $path: ${error.message}');
    exitCode = 65;
    return;
  }

  var ready = true;
  stdout.writeln('Checking $path');

  for (final entry in options.platforms.map(
    (name) => MapEntry(name, _requiredKeys[name]!),
  )) {
    final platform = entry.key;
    final missing = <String>[];
    final configured = <String>[];

    for (final key in entry.value) {
      final value = config[key];
      if (value is! String || !_isConfigured(value)) {
        missing.add(key);
      } else {
        configured.add(key);
      }
    }

    if (missing.isEmpty) {
      stdout.writeln('[ok] $platform credentials are present.');
    } else {
      ready = false;
      stdout.writeln('[missing] $platform: ${missing.join(', ')}');
    }

    for (final key in configured) {
      final warning = _formatWarning(key, config[key] as String);
      if (warning != null) {
        stdout.writeln('[warning] $warning');
      }
    }
  }

  if (ready) {
    stdout.writeln('Ready. Run: flutter run -d windows');
  } else {
    stdout.writeln(
      'Fill the missing values, then run this check again. No secrets were printed.',
    );
    exitCode = 1;
  }
}

_CheckOptions? _parseOptions(List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    return null;
  }
  if (arguments.length > 2) {
    return null;
  }

  var path = _defaultPath;
  var platforms = _requiredKeys.keys.toList(growable: false);

  for (final argument in arguments) {
    final normalized = argument.toLowerCase();
    switch (normalized) {
      case 'youtube':
      case 'yt':
        platforms = const ['YouTube'];
      case 'tiktok':
      case 'tt':
        platforms = const ['TikTok'];
      case 'all':
        platforms = _requiredKeys.keys.toList(growable: false);
      default:
        if (argument.startsWith('-') || path != _defaultPath) {
          return null;
        }
        path = argument;
    }
  }

  return _CheckOptions(path: path, platforms: platforms);
}

class _CheckOptions {
  const _CheckOptions({required this.path, required this.platforms});

  final String path;
  final List<String> platforms;
}

bool _isConfigured(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty && !trimmed.startsWith('REPLACE_WITH');
}

String? _formatWarning(String key, String value) {
  final trimmed = value.trim();
  if (key == 'YOUTUBE_CLIENT_ID' &&
      !trimmed.endsWith('.apps.googleusercontent.com')) {
    return '$key usually ends with .apps.googleusercontent.com';
  }
  return null;
}
