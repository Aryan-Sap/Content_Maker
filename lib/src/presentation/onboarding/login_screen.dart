import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../application/app_session_store.dart';
import 'project_hub_screen.dart';

/// Entry point of the app: pick (or create) a local profile, then move on to
/// the project hub. Profiles are stored locally — no network account needed.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.store = const AppSessionStore(),
    this.startGuidedTour = false,
    this.onGuidedTourCompleted,
  });

  final AppSessionStore store;
  final bool startGuidedTour;
  final Future<void> Function()? onGuidedTourCompleted;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();

  List<UserProfile> _profiles = const [];
  List<ProjectSummary> _projects = const [];
  bool _loading = true;
  String? _error;

  AppSessionStore get _store => widget.store;

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
        builder: (_) => ProjectHubScreen(
          profile: profile,
          store: _store,
          startGuidedTour: widget.startGuidedTour,
          onGuidedTourCompleted: widget.onGuidedTourCompleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 56 : 24,
                    vertical: 32,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 64,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: wide
                            ? Row(
                                children: [
                                  const Expanded(
                                    flex: 6,
                                    child: BrandEntrance(child: _LoginStory()),
                                  ),
                                  const SizedBox(width: 64),
                                  Expanded(
                                    flex: 5,
                                    child: BrandEntrance(
                                      delay: const Duration(milliseconds: 100),
                                      child: _buildAccessPanel(context),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const BrandEntrance(
                                    child: _LoginStory(compact: true),
                                  ),
                                  const SizedBox(height: 28),
                                  BrandEntrance(
                                    delay: const Duration(milliseconds: 100),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 520,
                                      ),
                                      child: _buildAccessPanel(context),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Brand.line),
        boxShadow: const [
          BoxShadow(color: Brand.shadow, blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Brand.lime,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.person_outline, color: Brand.ink),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCAL WORKSPACE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Brand.lime,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Continue to your studio.',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Profiles and projects are stored only on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Brand.muted),
          ),
          const SizedBox(height: 22),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_profiles.isNotEmpty) ...[
              Text(
                'WELCOME BACK',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Brand.faint,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final profile in _profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _ProfileTile(
                    profile: profile,
                    projectCount: _projects
                        .where((project) => project.ownerId == profile.id)
                        .length,
                    onOpen: () => _enter(profile),
                    onRemove: () => _removeProfile(profile),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'CREATE A NEW PROFILE',
                        style: TextStyle(
                          color: Brand.faint,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _nameController,
              autofocus: _profiles.isEmpty,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Creator name',
                hintText: 'What should we call you?',
                prefixIcon: Icon(Icons.person_add_alt_outlined),
              ),
              onSubmitted: (_) => _createProfile(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _createProfile,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Enter Content Maker'),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: Brand.faint),
                SizedBox(width: 6),
                Text(
                  'Local profile · no account required',
                  style: TextStyle(color: Brand.faint, fontSize: 11),
                ),
              ],
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
    );
  }
}

class _LoginStory extends StatelessWidget {
  const _LoginStory({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 620 : 680),
      child: Column(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: 54),
              const SizedBox(width: 14),
              const BrandWordmark(size: 21, showMark: false),
            ],
          ),
          SizedBox(height: compact ? 22 : 38),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'A good story.\n'),
                TextSpan(
                  text: 'Your cut.',
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: Brand.lime,
                  ),
                ),
              ],
            ),
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: compact ? 38 : 54,
              height: 1,
              letterSpacing: -1.25,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Import, arrange, render and publish in one considered desktop '
            'workspace. Your footage remains under your control.',
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Brand.muted,
              height: 1.55,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 30),
          const _CreationRail(),
        ],
      ),
    );
  }
}

class _CreationRail extends StatelessWidget {
  const _CreationRail();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _CreationStep(number: '01', label: 'EDIT', icon: Icons.content_cut),
        _CreationStep(number: '02', label: 'RENDER', icon: Icons.bolt),
        _CreationStep(
          number: '03',
          label: 'PUBLISH',
          icon: Icons.upload_outlined,
        ),
      ],
    );
  }
}

class _CreationStep extends StatelessWidget {
  const _CreationStep({
    required this.number,
    required this.label,
    required this.icon,
  });

  final String number;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: Brand.blueSoft,
              fontFamily: Brand.displayFont,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 9),
          Icon(icon, size: 17, color: Brand.lime),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Brand.cream,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.inkDeep, Brand.surface, Brand.surfaceSunken],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatefulWidget {
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
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: _hovered
              ? Brand.lime.withValues(alpha: 0.08)
              : Brand.surfaceSunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hovered ? Brand.lime : Brand.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Brand.surfaceHover,
                  foregroundColor: Brand.lime,
                  child: Text(
                    widget.profile.name.isEmpty
                        ? '?'
                        : widget.profile.name.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${widget.projectCount} project${widget.projectCount == 1 ? '' : 's'} · local workspace',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Brand.faint,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove profile',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
                const Icon(Icons.arrow_forward, size: 18, color: Brand.lime),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
