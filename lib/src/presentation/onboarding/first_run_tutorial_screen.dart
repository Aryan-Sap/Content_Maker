import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../application/app_session_store.dart';
import 'login_screen.dart';

/// Reads the one-time tour preference and hands it into the real product flow.
/// The tour itself is rendered over the controls the creator is using.
class AppEntryGate extends StatefulWidget {
  const AppEntryGate({super.key, this.store = const AppSessionStore()});

  final AppSessionStore store;

  @override
  State<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<AppEntryGate> {
  bool? _tutorialCompleted;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var completed = false;
    try {
      completed = await widget.store.hasCompletedTutorial();
    } catch (_) {
      // If local state cannot be read, leave the hands-on tour available.
    }
    if (mounted) setState(() => _tutorialCompleted = completed);
  }

  Future<void> _completeTutorial() async {
    try {
      await widget.store.markTutorialCompleted();
    } catch (_) {
      // A storage failure should never trap the creator inside onboarding.
    } finally {
      if (mounted) setState(() => _tutorialCompleted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _tutorialCompleted;
    if (completed == null) {
      return const Scaffold(
        body: Center(
          child: BrandEntrance(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogo(size: 72),
                SizedBox(height: 18),
                BrandWordmark(size: 20, showMark: false),
                SizedBox(height: 24),
                SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return LoginScreen(
      store: widget.store,
      startGuidedTour: !completed,
      onGuidedTourCompleted: _completeTutorial,
    );
  }
}
