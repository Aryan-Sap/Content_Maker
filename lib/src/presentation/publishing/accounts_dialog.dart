import 'package:flutter/material.dart';

import '../../application/manage_accounts.dart';
import '../../domain/publishing/auth/oauth_authenticator.dart';
import '../../domain/publishing/publish_target.dart';
import '../../infrastructure/publishing/publishing_registry.dart';

/// Connect / disconnect platform accounts outside of a publish run.
class AccountsDialog extends StatefulWidget {
  const AccountsDialog({super.key, this.registry});

  final PublishingRegistry? registry;

  static Future<void> show(
    BuildContext context, {
    PublishingRegistry? registry,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AccountsDialog(registry: registry),
    );
  }

  @override
  State<AccountsDialog> createState() => _AccountsDialogState();
}

class _AccountsDialogState extends State<AccountsDialog> {
  late final ManageAccounts _accounts;
  late final Set<PublishTarget> _configured;
  String? _error;
  final Map<PublishTarget, bool> _connected = {};
  final Set<PublishTarget> _busy = {};

  static const _targets = PublishTarget.values;

  @override
  void initState() {
    super.initState();
    final registry = widget.registry ?? PublishingRegistry();
    _configured = registry.configuredTargets;
    _accounts = ManageAccounts(
      authenticators: registry.authenticators,
      tokenStore: registry.tokenStore,
    );
    _refresh();
  }

  Future<void> _refresh() async {
    for (final target in _targets) {
      bool connected;
      try {
        connected = await _accounts.isConnected(target);
      } catch (_) {
        _notify(
          'Account status could not be read. Close this panel and retry.',
        );
        continue;
      }
      if (!mounted) {
        return;
      }
      setState(() => _connected[target] = connected);
    }
  }

  Future<void> _connect(PublishTarget target) async {
    setState(() => _busy.add(target));
    try {
      await _accounts.connect(target);
      if (mounted) {
        setState(() => _connected[target] = true);
      }
    } on OAuthException catch (error) {
      _notify(error.message);
    } catch (_) {
      _notify(
        'Could not connect this channel. Check your connection and try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy.remove(target));
      }
    }
  }

  Future<void> _disconnect(PublishTarget target) async {
    try {
      await _accounts.disconnect(target);
    } catch (_) {
      _notify('Could not disconnect this channel. Please try again.');
      return;
    }
    if (mounted) {
      setState(() => _connected[target] = false);
    }
  }

  void _notify(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connected accounts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
          for (final target in _targets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(target.label),
              subtitle: Text(
                (_connected[target] ?? false)
                    ? 'Connected'
                    : !_configured.contains(target)
                    ? 'Connection unavailable in this build'
                    : target == PublishTarget.instagramReel
                    ? 'Professional account required'
                    : 'Not connected',
              ),
              trailing: _busy.contains(target)
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : (_connected[target] ?? false)
                  ? TextButton(
                      onPressed: () => _disconnect(target),
                      child: const Text('Disconnect'),
                    )
                  : OutlinedButton(
                      onPressed: _configured.contains(target)
                          ? () => _connect(target)
                          : null,
                      child: const Text('Connect'),
                    ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
