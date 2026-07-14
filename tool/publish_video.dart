import 'dart:convert';
import 'dart:io';

import 'package:content_maker/src/domain/publishing/auth/oauth_credentials.dart';
import 'package:content_maker/src/domain/publishing/publish_job.dart';
import 'package:content_maker/src/domain/publishing/publish_metadata.dart';
import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/loopback_redirect_server.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/oauth_config.dart';
import 'package:content_maker/src/infrastructure/publishing/oauth/pkce.dart';
import 'package:content_maker/src/infrastructure/publishing/tiktok/tiktok_publisher.dart';
import 'package:content_maker/src/infrastructure/publishing/youtube/youtube_publisher.dart';
import 'package:http/http.dart' as http;

const _defaultConfigPath = 'oauth.local.json';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printUsage();
    return;
  }

  final options = _parseOptions(arguments);
  if (options == null) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final videoFile = File(options.videoPath);
  if (!await videoFile.exists()) {
    stderr.writeln('Video file not found: ${options.videoPath}');
    exitCode = 66;
    return;
  }

  final metadata = PublishMetadata(
    title: options.title,
    description: options.description,
    hashtags: options.hashtags,
    privacy: options.privacy,
    madeForKids: options.madeForKids,
  );
  final validationError = metadata.validate();
  if (validationError != null) {
    stderr.writeln(validationError);
    exitCode = 64;
    return;
  }

  final configs = await _loadConfigs(options.configPath);
  if (configs == null) {
    exitCode = 1;
    return;
  }

  var failed = false;
  for (final target in options.targets) {
    final config = configs[target];
    if (config == null || !config.isConfigured) {
      stderr.writeln(
        '${target.label} is missing credentials in ${options.configPath}.',
      );
      failed = true;
      continue;
    }

    try {
      stdout.writeln('Authorizing ${target.label} in your browser...');
      final credentials = await _authorize(target, config);
      stdout.writeln('Uploading ${videoFile.path} to ${target.label}...');

      final job = PublishJob(
        videoPath: videoFile.path,
        target: target,
        metadata: metadata,
      );
      final publisher = switch (target) {
        PublishTarget.youtubeShort => YoutubePublisher(),
        PublishTarget.tiktok => TiktokPublisher(),
        PublishTarget.instagramReel => throw UnsupportedError(
          'Instagram is manual hand-off only.',
        ),
      };

      await for (final progress in publisher.publish(job, credentials)) {
        _printProgress(progress);
        if (progress.status == PublishJobStatus.failed) {
          failed = true;
        }
      }
    } catch (error) {
      failed = true;
      stderr.writeln('${target.label} upload failed: $error');
    }
  }

  if (failed) {
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/publish_video.dart <youtube|tiktok|both> '
    '<video.mp4> --title "Upload test" [options]\n'
    '\n'
    'Options:\n'
    '  --config <path>           OAuth config file, defaults to oauth.local.json\n'
    '  --description <text>      Description/caption body\n'
    '  --hashtags <tags>         Space or comma separated hashtags\n'
    '  --privacy <value>         public, unlisted, private, or draft '
    '(default: private)\n'
    '  --made-for-kids           YouTube COPPA self-declaration\n'
    '\n'
    'Example:\n'
    '  dart run tool/publish_video.dart youtube '
    '"build/manual/sample_video_shorts_cli.mp4" '
    '--title "Content Maker private upload test" --privacy private',
  );
}

_PublishOptions? _parseOptions(List<String> arguments) {
  final positional = <String>[];
  var configPath = _defaultConfigPath;
  var title = '';
  var description = '';
  var hashtags = const <String>[];
  var privacy = PublishPrivacy.private;
  var madeForKids = false;

  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    switch (arg) {
      case '--config':
        if (i + 1 >= arguments.length) {
          return null;
        }
        configPath = arguments[++i];
      case '--title':
        if (i + 1 >= arguments.length) {
          return null;
        }
        title = arguments[++i];
      case '--description':
        if (i + 1 >= arguments.length) {
          return null;
        }
        description = arguments[++i];
      case '--hashtags':
        if (i + 1 >= arguments.length) {
          return null;
        }
        hashtags = _parseHashtags(arguments[++i]);
      case '--privacy':
        if (i + 1 >= arguments.length) {
          return null;
        }
        final parsed = _parsePrivacy(arguments[++i]);
        if (parsed == null) {
          return null;
        }
        privacy = parsed;
      case '--made-for-kids':
        madeForKids = true;
      default:
        if (arg.startsWith('--')) {
          return null;
        }
        positional.add(arg);
    }
  }

  if (positional.length != 2 || title.trim().isEmpty) {
    return null;
  }

  final targets = _parseTargets(positional[0]);
  if (targets.isEmpty) {
    return null;
  }

  return _PublishOptions(
    targets: targets,
    videoPath: positional[1],
    configPath: configPath,
    title: title.trim(),
    description: description.trim(),
    hashtags: hashtags,
    privacy: privacy,
    madeForKids: madeForKids,
  );
}

List<PublishTarget> _parseTargets(String raw) {
  return switch (raw.toLowerCase()) {
    'youtube' ||
    'youtube-short' ||
    'youtube-shorts' => [PublishTarget.youtubeShort],
    'tiktok' => [PublishTarget.tiktok],
    'both' => [PublishTarget.youtubeShort, PublishTarget.tiktok],
    _ => const [],
  };
}

PublishPrivacy? _parsePrivacy(String raw) {
  return switch (raw.toLowerCase()) {
    'public' => PublishPrivacy.public,
    'unlisted' => PublishPrivacy.unlisted,
    'private' => PublishPrivacy.private,
    'draft' => PublishPrivacy.draft,
    _ => null,
  };
}

List<String> _parseHashtags(String raw) {
  return raw
      .split(RegExp(r'[\s,]+'))
      .map((tag) => tag.replaceAll(RegExp(r'^#+'), '').trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
}

Future<Map<PublishTarget, OAuthClientConfig>?> _loadConfigs(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('Missing $path. Copy oauth.local.example.json to $path.');
    return null;
  }

  final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('root must be a JSON object');
    }
    json = decoded;
  } on FormatException catch (error) {
    stderr.writeln('Could not parse $path: ${error.message}');
    return null;
  }

  return {
    PublishTarget.youtubeShort: OAuthConfig.fromJsonForTarget(
      PublishTarget.youtubeShort,
      json,
    )!,
    PublishTarget.tiktok: OAuthConfig.fromJsonForTarget(
      PublishTarget.tiktok,
      json,
    )!,
  };
}

Future<OAuthCredentials> _authorize(
  PublishTarget target,
  OAuthClientConfig config,
) async {
  final pkce = PkcePair.generate();
  final state = generateOAuthState();
  final server = await LoopbackRedirectServer.start();
  final redirectUri = server.redirectUri;
  final client = http.Client();

  try {
    final authUrl = _authorizationUrl(
      target: target,
      config: config,
      redirectUri: redirectUri,
      codeChallenge: pkce.challenge,
      state: state,
    );

    stdout.writeln('Authorization URL: $authUrl');
    await _openBrowser(authUrl);
    final redirect = await server.waitForCode(
      expectedState: state,
      timeout: const Duration(minutes: 15),
    );

    return _exchangeCode(
      client: client,
      target: target,
      config: config,
      code: redirect.code,
      redirectUri: redirectUri,
      codeVerifier: pkce.verifier,
    );
  } finally {
    client.close();
    await server.close();
  }
}

Uri _authorizationUrl({
  required PublishTarget target,
  required OAuthClientConfig config,
  required String redirectUri,
  required String codeChallenge,
  required String state,
}) {
  final queryParameters = switch (target) {
    PublishTarget.youtubeShort => {
      'client_id': config.clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': config.scopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
      'state': state,
    },
    PublishTarget.tiktok => {
      'client_key': config.clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': config.scopes.join(','),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
    },
    PublishTarget.instagramReel => throw UnsupportedError(
      'Instagram is manual hand-off only.',
    ),
  };

  return Uri.parse(
    config.authorizationEndpoint,
  ).replace(queryParameters: queryParameters);
}

Future<OAuthCredentials> _exchangeCode({
  required http.Client client,
  required PublishTarget target,
  required OAuthClientConfig config,
  required String code,
  required String redirectUri,
  required String codeVerifier,
}) async {
  final body = switch (target) {
    PublishTarget.youtubeShort => {
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'code': code,
      'code_verifier': codeVerifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    },
    PublishTarget.tiktok => {
      'client_key': config.clientId,
      'client_secret': config.clientSecret,
      'code': code,
      'code_verifier': codeVerifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    },
    PublishTarget.instagramReel => throw UnsupportedError(
      'Instagram is manual hand-off only.',
    ),
  };

  final response = await client.post(
    Uri.parse(config.tokenEndpoint),
    headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
    body: body,
  );

  if (response.statusCode != 200) {
    throw Exception('token request failed: ${response.body}');
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final error = json['error'];
  if (error != null && error != '' && error != 'ok') {
    throw Exception(
      'authorization failed: ${json['error_description'] ?? error}',
    );
  }

  final accessToken = json['access_token'] as String?;
  if (accessToken == null || accessToken.isEmpty) {
    throw Exception('authorization returned no access token');
  }

  final expiresIn = (json['expires_in'] as num?)?.toInt();
  final scope = json['scope'] as String?;
  return OAuthCredentials(
    accessToken: accessToken,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn)),
    scopes: scope == null
        ? config.scopes
        : scope.split(target == PublishTarget.tiktok ? ',' : ' '),
  );
}

Future<void> _openBrowser(Uri uri) async {
  final url = uri.toString();
  final ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('rundll32', [
      'url.dll,FileProtocolHandler',
      url,
    ]);
  } else if (Platform.isMacOS) {
    result = await Process.run('open', [url]);
  } else {
    result = await Process.run('xdg-open', [url]);
  }

  if (result.exitCode != 0) {
    throw Exception('could not open browser: ${result.stderr}');
  }
}

void _printProgress(PublishProgress progress) {
  final percent = progress.fraction == null
      ? ''
      : ' ${(progress.fraction! * 100).toStringAsFixed(0)}%';
  final remoteUrl = progress.remoteUrl == null ? '' : ' ${progress.remoteUrl}';
  stdout.writeln(
    '${progress.target.label}: ${progress.status.name}: '
    '${progress.message}$percent$remoteUrl',
  );
}

class _PublishOptions {
  const _PublishOptions({
    required this.targets,
    required this.videoPath,
    required this.configPath,
    required this.title,
    required this.description,
    required this.hashtags,
    required this.privacy,
    required this.madeForKids,
  });

  final List<PublishTarget> targets;
  final String videoPath;
  final String configPath;
  final String title;
  final String description;
  final List<String> hashtags;
  final PublishPrivacy privacy;
  final bool madeForKids;
}
