import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/brand.dart';
import '../../application/manage_accounts.dart';
import '../../application/publish_export.dart';
import '../../domain/publishing/auth/oauth_authenticator.dart';
import '../../domain/publishing/publish_job.dart';
import '../../domain/publishing/publish_metadata.dart';
import '../../domain/publishing/publish_target.dart';
import '../../infrastructure/notifications/desktop_notifier.dart';
import '../../infrastructure/publishing/publishing_registry.dart';

/// One-click publishing surface shown after a render completes. Lets the user
/// pick destinations, edit shared metadata, connect accounts, and publish.
class PublishPanel extends StatefulWidget {
  const PublishPanel({
    super.key,
    required this.videoPath,
    this.registry,
    this.defaultTitle,
  });

  final String videoPath;

  /// Injectable for tests; defaults to the real adapters.
  final PublishingRegistry? registry;

  final String? defaultTitle;

  @override
  State<PublishPanel> createState() => _PublishPanelState();
}

class _PublishPanelState extends State<PublishPanel> {
  late final PublishingRegistry _registry;
  late final PublishExport _publishExport;
  late final ManageAccounts _accounts;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _hashtagController = TextEditingController();

  final Set<PublishTarget> _selected = {PublishTarget.youtubeShort};
  final Map<PublishTarget, bool> _connected = {};
  final Map<PublishTarget, PublishProgress> _progress = {};
  final Set<PublishTarget> _busyConnecting = {};

  PublishPrivacy _privacy = PublishPrivacy.private;
  bool _madeForKids = false;
  bool _publishing = false;
  String? _message;
  StreamSubscription<PublishProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    _registry = widget.registry ?? PublishingRegistry();
    _publishExport = PublishExport(
      publishers: _registry.publishers,
      authenticators: _registry.authenticators,
      tokenStore: _registry.tokenStore,
    );
    _accounts = ManageAccounts(
      authenticators: _registry.authenticators,
      tokenStore: _registry.tokenStore,
    );
    _titleController.text = widget.defaultTitle ?? '';
    _refreshConnections();
  }

  @override
  void didUpdateWidget(PublishPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      setState(_progress.clear);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _hashtagController.dispose();
    super.dispose();
  }

  Future<void> _refreshConnections() async {
    for (final target in PublishTarget.values) {
      bool connected;
      try {
        connected = await _accounts.isConnected(target);
      } catch (_) {
        _showMessage(
          'Account status could not be read. Try connecting the channel again.',
        );
        continue;
      }
      if (!mounted) {
        return;
      }
      setState(() => _connected[target] = connected);
    }
  }

  bool get _hasAutomatedSelection =>
      _selected.any((target) => target.supportsAutomatedPublish);

  bool get _canPublish =>
      !_publishing &&
      _busyConnecting.isEmpty &&
      _selected
          .where((t) => t.supportsAutomatedPublish)
          .every(_registry.configuredTargets.contains) &&
      _selected.any((target) => _progress[target]?.isSuccess != true) &&
      _selected.isNotEmpty &&
      _titleController.text.trim().isNotEmpty;

  PublishMetadata _buildMetadata() {
    return PublishMetadata(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      hashtags: _parseHashtags(_hashtagController.text),
      privacy: _privacy,
      madeForKids: _madeForKids,
    );
  }

  List<String> _parseHashtags(String raw) {
    return raw
        .split(RegExp(r'[\s,]+'))
        .map((tag) => tag.replaceAll(RegExp(r'^#+'), '').trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
  }

  Future<void> _connect(PublishTarget target) async {
    if (!_registry.configuredTargets.contains(target)) {
      _showMessage(
        '${target.label} connection is unavailable in this build. Choose another destination or use the exported file.',
      );
      return;
    }
    setState(() => _busyConnecting.add(target));
    try {
      await _accounts.connect(target);
      if (!mounted) {
        return;
      }
      setState(() => _connected[target] = true);
    } on OAuthException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage(
        'Could not connect this channel. Check your connection and try Connect again.',
      );
    } finally {
      if (mounted) {
        setState(() => _busyConnecting.remove(target));
      }
    }
  }

  Future<void> _disconnect(PublishTarget target) async {
    try {
      await _accounts.disconnect(target);
    } catch (_) {
      _showMessage('Could not disconnect this channel. Please try again.');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _connected[target] = false);
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    final metadata = _buildMetadata();
    final validationError = metadata.validate();
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    // Preserve successful destinations on retry: never post them twice.
    final pending = _selected
        .where((target) => _progress[target]?.isSuccess != true)
        .toSet();
    setState(() {
      _publishing = true;
      _message = null;
    });
    try {
      if (!await File(widget.videoPath).exists()) {
        if (mounted) {
          setState(() {
            _publishing = false;
            _message =
                'The exported video is missing. Render it again before publishing.';
          });
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _publishing = false;
          _message =
              'The exported video could not be read. Check file permissions and retry.';
        });
      }
      return;
    }
    if (!mounted) return;
    final jobs = pending
        .map(
          (target) => PublishJob(
            videoPath: widget.videoPath,
            target: target,
            metadata: metadata,
          ),
        )
        .toList();

    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _publishing = true;
      _progress.addEntries(
        pending.map(
          (target) => MapEntry(
            target,
            PublishProgress(
              target: target,
              status: PublishJobStatus.queued,
              message: 'Queued',
            ),
          ),
        ),
      );
    });

    _subscription = _publishExport(jobs).listen(
      (progress) {
        if (!mounted) return;
        final previous = _progress[progress.target];
        setState(() => _progress[progress.target] = progress);
        if (progress.isTerminal && !(previous?.isTerminal ?? false)) {
          _notifyPublishResult(progress);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        _showMessage(
          'Publishing was interrupted. Check your connection and retry failed destinations.',
        );
        setState(() => _publishing = false);
      },
      onDone: () {
        if (mounted) {
          setState(() => _publishing = false);
        }
        _refreshConnections();
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _message = message);
  }

  void _notifyPublishResult(PublishProgress progress) {
    final completed = progress.status == PublishJobStatus.completed;
    final handoff = !progress.target.supportsAutomatedPublish;
    final url = progress.remoteUrl;
    unawaited(
      DesktopNotifier.show(
        title: completed
            ? '${handoff ? 'Handoff ready' : 'Upload complete'} — ${progress.target.label}'
            : 'Upload failed — ${progress.target.label}',
        body: completed
            ? (url == null
                  ? 'Your video is ready. Check the destination status.'
                  : 'Upload complete. Visibility follows your selected setting: $url')
            : progress.message,
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          completed
              ? '${progress.target.label}: ${handoff ? 'ready for manual posting' : 'upload complete'}.'
              : '${progress.target.label}: ${progress.message}',
        ),
        action: completed && url != null
            ? SnackBarAction(label: 'Open', onPressed: () => _openUrl(url))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Brand.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.ios_share_outlined),
                const SizedBox(width: 10),
                Text(
                  'Publish',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Choose channels, review visibility, then send your finished video.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Brand.muted),
            ),
            const SizedBox(height: 18),
            if (_message != null) ...[
              Semantics(
                liveRegion: true,
                child: _InfoBanner(icon: Icons.info_outline, text: _message!),
              ),
              const SizedBox(height: 12),
            ],
            Text('Destinations', style: theme.textTheme.titleMedium),
            for (final target in _selected.where(
              (t) =>
                  t.supportsAutomatedPublish &&
                  !_registry.configuredTargets.contains(t),
            ))
              _InfoBanner(
                icon: Icons.info_outline,
                text:
                    '${target.label} publishing is not configured in this build. Deselect it to publish to other channels.',
              ),
            const SizedBox(height: 10),
            _DestinationList(
              selected: _selected,
              connected: _connected,
              connectableTargets: _registry.authenticators.keys.toSet(),
              busyConnecting: _busyConnecting,
              enabled: !_publishing,
              onToggle: (target, value) {
                setState(() {
                  if (value) {
                    _selected.add(target);
                  } else {
                    _selected.remove(target);
                  }
                });
              },
              onConnect: _connect,
              onDisconnect: _disconnect,
            ),
            const SizedBox(height: 18),
            Text('Details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              enabled: !_publishing,
              maxLength: PublishMetadata.maxTitleLength,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Title / caption',
                prefixIcon: Icon(Icons.title_outlined),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descriptionController,
              enabled: !_publishing,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hashtagController,
              enabled: !_publishing,
              decoration: const InputDecoration(
                labelText: 'Hashtags (space or comma separated)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<PublishPrivacy>(
                    initialValue: _privacy,
                    decoration: const InputDecoration(
                      labelText: 'Visibility',
                      prefixIcon: Icon(Icons.visibility_outlined),
                    ),
                    items: [
                      for (final value in PublishPrivacy.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: _publishing
                        ? null
                        : (value) =>
                              setState(() => _privacy = value ?? _privacy),
                  ),
                ),
              ],
            ),
            if (_selected.contains(PublishTarget.youtubeShort))
              SwitchListTile(
                value: _madeForKids,
                onChanged: _publishing
                    ? null
                    : (value) => setState(() => _madeForKids = value),
                title: const Text('Made for kids (YouTube)'),
                subtitle: const Text('Required COPPA self-declaration'),
                secondary: const Icon(Icons.child_care_outlined),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 8),
            if (_selected.contains(PublishTarget.instagramReel))
              const _InfoBanner(
                icon: Icons.info_outline,
                text:
                    'Instagram uses manual handoff in this app, including connected professional accounts. '
                    'The video opens in Explorer and the caption is copied. Complete the post in Instagram.',
              ),
            if (_selected.contains(PublishTarget.tiktok))
              const _InfoBanner(
                icon: Icons.info_outline,
                text:
                    'TikTok posts privately until your developer app passes '
                    'TikTok\'s content-posting audit.',
              ),
            FilledButton.icon(
              onPressed: _canPublish ? _publish : null,
              icon: _publishing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(
                _publishing
                    ? 'Publishing'
                    : _hasAutomatedSelection
                    ? (_progress.values.any(
                            (p) => p.status == PublishJobStatus.failed,
                          )
                          ? 'Retry failed destinations'
                          : _selected.every(
                              (t) => _progress[t]?.isSuccess == true,
                            )
                          ? 'Upload complete'
                          : 'Publish now')
                    : 'Prepare',
              ),
            ),
            if (_progress.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final target in PublishTarget.values)
                if (_progress[target] case final progress?)
                  Semantics(
                    liveRegion: true,
                    child: _ProgressRow(progress: progress),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestinationList extends StatelessWidget {
  const _DestinationList({
    required this.selected,
    required this.connected,
    required this.connectableTargets,
    required this.busyConnecting,
    required this.enabled,
    required this.onToggle,
    required this.onConnect,
    required this.onDisconnect,
  });

  final Set<PublishTarget> selected;
  final Map<PublishTarget, bool> connected;
  final Set<PublishTarget> connectableTargets;
  final Set<PublishTarget> busyConnecting;
  final bool enabled;
  final void Function(PublishTarget, bool) onToggle;
  final void Function(PublishTarget) onConnect;
  final void Function(PublishTarget) onDisconnect;

  IconData _iconFor(PublishTarget target) {
    return switch (target) {
      PublishTarget.youtubeShort => Icons.smart_display_outlined,
      PublishTarget.tiktok => Icons.music_note_outlined,
      PublishTarget.instagramReel => Icons.camera_alt_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final target in PublishTarget.values)
          _DestinationTile(
            target: target,
            icon: _iconFor(target),
            selected: selected.contains(target),
            requiresConnection: connectableTargets.contains(target),
            connected: connected[target] ?? false,
            busy: busyConnecting.contains(target),
            enabled: enabled,
            onToggle: (value) => onToggle(target, value),
            onConnect: () => onConnect(target),
            onDisconnect: () => onDisconnect(target),
          ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.target,
    required this.icon,
    required this.selected,
    required this.requiresConnection,
    required this.connected,
    required this.busy,
    required this.enabled,
    required this.onToggle,
    required this.onConnect,
    required this.onDisconnect,
  });

  final PublishTarget target;
  final IconData icon;
  final bool selected;
  final bool requiresConnection;
  final bool connected;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showConnect = requiresConnection && selected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Brand.surfaceSunken,
          border: Border.all(color: Brand.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled ? (value) => onToggle(value ?? false) : null,
              ),
              Icon(icon, size: 20, color: Brand.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(target.label),
                    if (showConnect)
                      Text(
                        connected ? 'Connected' : 'Not connected',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: connected ? Brand.success : Brand.faint,
                        ),
                      )
                    else if (!requiresConnection && selected)
                      Text(
                        'Manual hand-off',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Brand.faint,
                        ),
                      ),
                  ],
                ),
              ),
              if (showConnect)
                busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : connected
                    ? TextButton(
                        onPressed: enabled ? onDisconnect : null,
                        child: const Text('Disconnect'),
                      )
                    : OutlinedButton(
                        onPressed: enabled ? onConnect : null,
                        child: const Text('Connect'),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.progress});

  final PublishProgress progress;

  Color _statusColor() {
    return switch (progress.status) {
      PublishJobStatus.completed => Brand.success,
      PublishJobStatus.failed => Brand.danger,
      _ => Brand.muted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = progress.remoteUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.target.label,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                progress.status.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _statusColor(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (!progress.isTerminal)
            LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: 6),
          Text(
            progress.message,
            style: theme.textTheme.bodySmall?.copyWith(color: Brand.muted),
          ),
          if (url != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => _openUrl(url),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.open_in_new_outlined,
                          size: 14,
                          color: Brand.blueSoft,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            url,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Brand.blueSoft,
                              decoration: TextDecoration.underline,
                              decorationColor: Brand.blueSoft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Brand.surfaceRaised,
          border: Border.all(color: Brand.lineStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}
