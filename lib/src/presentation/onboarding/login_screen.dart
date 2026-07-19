import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../application/app_session_store.dart';
import 'project_hub_screen.dart';

/// Entry point of the app: pick (or create) a local profile, then move on to
/// the project hub. Profiles are stored locally — no network account needed.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _store = const AppSessionStore();
  final _nameController = TextEditingController();

  List<UserProfile> _profiles = const [];
  List<ProjectSummary> _projects = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final session = await _store.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = session.profiles;
        _projects = session.projects;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load profiles: $error';
      });
    }
  }

  Future<void> _createProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name to create a profile.');
      return;
    }
    final profile = UserProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
    );
    final nextProfiles = [..._profiles, profile];
    try {
      await _store.save(profiles: nextProfiles, projects: _projects);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the profile: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = nextProfiles;
      _error = null;
      _nameController.clear();
    });
    _enter(profile);
  }

  Future<void> _removeProfile(UserProfile profile) async {
    final nextProfiles = _profiles
        .where((candidate) => candidate.id != profile.id)
        .toList();
    final nextProjects = _projects
        .where((project) => project.ownerId != profile.id)
        .toList();
    try {
      await _store.save(profiles: nextProfiles, projects: nextProjects);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not remove the profile: $error');
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = nextProfiles;
      _projects = nextProjects;
    });
  }

  void _enter(UserProfile profile) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProjectHubScreen(profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: BrandEntrance(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandEntrance(
                      delay: Duration(milliseconds: 80),
                      child: Center(child: BrandWordmark(size: 24)),
                    ),
                    const SizedBox(height: 14),
                    BrandEntrance(
                      delay: const Duration(milliseconds: 160),
                      child: Center(
                        child: Wrap(
                          spacing: 14,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: const [
                            BrandSticker(
                              label: 'MAKE CONTENT EASY',
                              rotationDegrees: -3,
                            ),
                            BrandSticker(
                              label: '100% FREE',
                              rotationDegrees: 2,
                              color: Brand.blue,
                              textColor: Brand.cream,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Sign in with a local profile to continue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      for (final profile in _profiles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ProfileTile(
                            profile: profile,
                            projectCount: _projects
                                .where((p) => p.ownerId == profile.id)
                                .length,
                            onOpen: () => _enter(profile),
                            onRemove: () => _removeProfile(profile),
                          ),
                        ),
                      if (_profiles.isNotEmpty) const Divider(height: 28),
                      TextField(
                        controller: _nameController,
                        autofocus: _profiles.isEmpty,
                        decoration: const InputDecoration(
                          labelText: 'New profile name',
                          prefixIcon: Icon(Icons.person_add_alt_outlined),
                        ),
                        onSubmitted: (_) => _createProfile(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _createProfile,
                        icon: const Icon(Icons.login_outlined),
                        label: const Text('Create profile & continue'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.projectCount,
    required this.onOpen,
    required this.onRemove,
  });

  final UserProfile profile;
  final int projectCount;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(
                  profile.name.isEmpty
                      ? '?'
                      : profile.name.characters.first.toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$projectCount project${projectCount == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove profile',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
              const Icon(Icons.chevron_right_outlined),
            ],
          ),
        ),
      ),
    );
  }
}
