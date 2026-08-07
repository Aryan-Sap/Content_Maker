import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../application/app_session_store.dart';
import '../render_home_screen.dart';
import 'guided_tour_overlay.dart';
import 'login_screen.dart';

/// After login: create a new project (choosing the Simple or Custom pipeline)
/// or reopen a recent one.
class ProjectHubScreen extends StatefulWidget {
  const ProjectHubScreen({
    super.key,
    required this.profile,
    this.store = const AppSessionStore(),
    this.startGuidedTour = false,
    this.onGuidedTourCompleted,
  });

  final UserProfile profile;
  final AppSessionStore store;
  final bool startGuidedTour;
  final Future<void> Function()? onGuidedTourCompleted;

  @override
  State<ProjectHubScreen> createState() => _ProjectHubScreenState();
}

class _ProjectHubScreenState extends State<ProjectHubScreen> {
  final _nameController = TextEditingController();
  final _projectNameTourKey = GlobalKey();
  final _autoPipelineTourKey = GlobalKey();
  final _startProjectTourKey = GlobalKey();

  List<UserProfile> _profiles = const [];
  List<ProjectSummary> _projects = const [];
  ProjectPipeline _pipeline = ProjectPipeline.simple;
  bool _loading = true;
  String? _error;
  bool _guidedTourActive = false;
  int _guidedTourStep = 0;

  AppSessionStore get _store => widget.store;

  List<ProjectSummary> get _myProjects {
    final projects = _projects
        .where((project) => project.ownerId == widget.profile.id)
        .toList();
    projects.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return projects;
  }

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
        _guidedTourActive = widget.startGuidedTour;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Could not load projects: $error';
      });
    }
  }

  Future<void> _persist() {
    return _store.save(profiles: _profiles, projects: _projects);
  }

  Future<void> _createProject() async {
    final launchGuidedTour = _guidedTourActive && _guidedTourStep == 2;
    final rawName = _nameController.text.trim();
    final name = rawName.isEmpty
        ? 'Project ${_myProjects.length + 1}'
        : rawName;
    final now = DateTime.now();
    final project = ProjectSummary(
      id: now.microsecondsSinceEpoch.toString(),
      name: name,
      pipeline: _pipeline,
      ownerId: widget.profile.id,
      createdAt: now,
      lastOpenedAt: now,
    );
    setState(() {
      _projects = [..._projects, project];
      _nameController.clear();
      _error = null;
    });
    try {
      await _persist();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save the project: $error');
      }
    }
    if (mounted) {
      if (launchGuidedTour) {
        setState(() => _guidedTourActive = false);
      }
      _openProject(project, guidedTour: launchGuidedTour);
    }
  }

  Future<void> _openProject(
    ProjectSummary project, {
    bool guidedTour = false,
  }) async {
    setState(() {
      _projects = [
        for (final candidate in _projects)
          candidate.id == project.id
              ? candidate.copyWith(lastOpenedAt: DateTime.now())
              : candidate,
      ];
    });
    unawaited(_persist().catchError((_) {}));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RenderHomeScreen(
          projectName: project.name,
          initialPipeline: project.pipeline,
          guidedTour: guidedTour,
          onGuidedTourFinished: widget.onGuidedTourCompleted,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteProject(ProjectSummary project) async {
    setState(() {
      _projects = _projects
          .where((candidate) => candidate.id != project.id)
          .toList();
    });
    try {
      await _persist();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not delete the project: $error');
      }
    }
  }

  void _signOut() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => LoginScreen(store: _store)),
    );
  }

  void _showTutorial() {
    setState(() {
      _guidedTourActive = true;
      _guidedTourStep = 0;
      _nameController.clear();
    });
  }

  Future<void> _finishGuidedTour() async {
    if (mounted) setState(() => _guidedTourActive = false);
    await widget.onGuidedTourCompleted?.call();
  }

  void _advanceGuidedTour() {
    if (!_guidedTourActive || _guidedTourStep >= 2) return;
    setState(() => _guidedTourStep++);
  }

  Widget _buildGuidedTour() {
    return switch (_guidedTourStep) {
      0 => GuidedTourOverlay(
        targetKey: _projectNameTourKey,
        step: 1,
        totalSteps: 13,
        title: 'Name a real project',
        description:
            'Type a name into the highlighted field. This project will be saved in your studio and used for the hands-on tour.',
        onSkip: _finishGuidedTour,
        actionLabel: 'Next',
        onAction: _advanceGuidedTour,
      ),
      1 => GuidedTourOverlay(
        targetKey: _autoPipelineTourKey,
        step: 2,
        totalSteps: 13,
        title: 'Choose Auto Render',
        description:
            'Click the highlighted workflow card. You are choosing the actual editing mode for this project.',
        onSkip: _finishGuidedTour,
        onNext: _advanceGuidedTour,
      ),
      _ => GuidedTourOverlay(
        targetKey: _startProjectTourKey,
        step: 3,
        totalSteps: 13,
        title: 'Open the real workspace',
        description:
            'Start the project. The next steps happen inside Auto Render and then the Custom Timeline.',
        onSkip: _finishGuidedTour,
        actionLabel: 'Open workspace',
        onAction: _createProject,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myProjects = _myProjects;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const BrandWordmark(size: 15),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    widget.profile.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _showTutorial,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text('Quick tour'),
              ),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout_outlined, size: 18),
                label: const Text('Sign out'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildStudio(context, myProjects),
        ),
        if (_guidedTourActive && !_loading) _buildGuidedTour(),
      ],
    );
  }

  Widget _buildStudio(BuildContext context, List<ProjectSummary> myProjects) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandEntrance(
                child: _StudioHero(
                  creatorName: widget.profile.name,
                  projectCount: myProjects.length,
                ),
              ),
              const SizedBox(height: 22),
              BrandEntrance(
                delay: const Duration(milliseconds: 80),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final composer = _buildProjectComposer(context);
                    const map = _WorkflowMap();
                    return wide
                        ? Row(
                            children: [
                              Expanded(flex: 7, child: composer),
                              const SizedBox(width: 18),
                              const Expanded(flex: 3, child: map),
                            ],
                          )
                        : Column(
                            children: [
                              composer,
                              const SizedBox(height: 18),
                              map,
                            ],
                          );
                  },
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Text('Your projects', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 10),
                  _CountBadge(count: myProjects.length),
                  const Spacer(),
                  Text(
                    'Saved locally on this device',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.faint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (myProjects.isEmpty)
                const _EmptyProjectShelf()
              else
                for (var i = 0; i < myProjects.length; i++)
                  BrandEntrance(
                    delay: Duration(milliseconds: 130 + i * 45),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _ProjectTile(
                        project: myProjects[i],
                        onOpen: () => _openProject(myProjects[i]),
                        onDelete: () => _deleteProject(myProjects[i]),
                      ),
                    ),
                  ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectComposer(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.lineStrong),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Brand.lime,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add, color: Brand.ink),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create something new',
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    'Name the idea, then choose how hands-on you want to be.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            key: _projectNameTourKey,
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'e.g. Ranked clutch · Episode 04',
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
            onSubmitted: (_) {
              if (_guidedTourActive && _guidedTourStep == 0) {
                if (_nameController.text.trim().isNotEmpty) {
                  _advanceGuidedTour();
                }
                return;
              }
              _createProject();
            },
            onChanged: (_) {
              if (_guidedTourActive && _guidedTourStep == 0) setState(() {});
            },
          ),
          const SizedBox(height: 18),
          Text(
            'CHOOSE YOUR EDITING METHOD',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Brand.faint,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 620;
              final cards = [
                KeyedSubtree(
                  key: _autoPipelineTourKey,
                  child: _PipelineCard(
                    title: 'Auto Render',
                    tag: 'FASTEST',
                    subtitle:
                        'Turn gameplay into a polished Short in one guided pass.',
                    steps: const ['Import', 'Style', 'Render'],
                    accent: Brand.lime,
                    icon: Icons.auto_awesome_outlined,
                    selected: _pipeline == ProjectPipeline.simple,
                    onTap: () {
                      setState(() => _pipeline = ProjectPipeline.simple);
                      if (_guidedTourActive && _guidedTourStep == 1) {
                        _advanceGuidedTour();
                      }
                    },
                  ),
                ),
                _PipelineCard(
                  title: 'Custom Timeline',
                  tag: 'FULL CONTROL',
                  subtitle:
                      'Build a layered edit with precision tools and a live preview.',
                  steps: const ['Arrange', 'Polish', 'Export'],
                  accent: Brand.blue,
                  icon: Icons.timeline_outlined,
                  selected: _pipeline == ProjectPipeline.custom,
                  onTap: () =>
                      setState(() => _pipeline = ProjectPipeline.custom),
                ),
              ];
              return wide
                  ? Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    )
                  : Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 12),
                        cards[1],
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: _startProjectTourKey,
              onPressed: _createProject,
              icon: Icon(
                _pipeline == ProjectPipeline.simple
                    ? Icons.bolt
                    : Icons.movie_creation_outlined,
              ),
              label: Text(
                _pipeline == ProjectPipeline.simple
                    ? 'Start an Auto Render project'
                    : 'Open a Custom Timeline',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudioHero extends StatelessWidget {
  const _StudioHero({required this.creatorName, required this.projectCount});

  final String creatorName;
  final int projectCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = creatorName.trim().split(' ').first;
    return Container(
      decoration: BoxDecoration(
        color: Brand.blue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.blueSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Brand.cream.withValues(alpha: 0.22),
                  width: 2,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WELCOME TO THE STUDIO, ${firstName.toUpperCase()}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFDFE4FF),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'What are we making today?',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: Brand.cream,
                          fontSize: 34,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start fast with Auto Render or take the controls in the Custom Timeline.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFDFE4FF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Brand.ink.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Brand.cream.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$projectCount',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: Brand.lime,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        projectCount == 1 ? 'PROJECT' : 'PROJECTS',
                        style: const TextStyle(
                          color: Brand.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowMap extends StatelessWidget {
  const _WorkflowMap();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Brand.ink,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.lineStrong),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandSticker(label: 'ONE APP · TWO PATHS', rotationDegrees: -2),
          const SizedBox(height: 20),
          Text('From raw clip to ready.', style: theme.textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(
            'Every project follows the same creative rhythm. You choose how much control each step needs.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Brand.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          const _MapStep(
            number: '01',
            title: 'EDIT',
            detail: 'Auto or timeline',
          ),
          const _MapConnector(),
          const _MapStep(
            number: '02',
            title: 'RENDER',
            detail: 'Local · 60 fps',
          ),
          const _MapConnector(),
          const _MapStep(
            number: '03',
            title: 'PUBLISH',
            detail: 'One connected flow',
          ),
          const SizedBox(height: 24),
          const Text(
            'TIP · You can switch editing methods inside a project.',
            style: TextStyle(
              color: Brand.blueSoft,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStep extends StatelessWidget {
  const _MapStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Brand.lime,
          foregroundColor: Brand.ink,
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(color: Brand.faint, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapConnector extends StatelessWidget {
  const _MapConnector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 17, top: 5, bottom: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 2,
          height: 15,
          child: ColoredBox(color: Brand.lineStrong),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Brand.lime,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Brand.ink,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyProjectShelf extends StatelessWidget {
  const _EmptyProjectShelf();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Brand.surfaceSunken,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          const BrandLogo(size: 46, ringColor: Brand.blueSoft),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your first timeline starts above.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Give the idea a name, choose a method, and Content Maker will open the right workspace.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Brand.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineCard extends StatefulWidget {
  const _PipelineCard({
    required this.title,
    required this.tag,
    required this.subtitle,
    required this.steps,
    required this.accent,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String tag;
  final String subtitle;
  final List<String> steps;
  final Color accent;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PipelineCard> createState() => _PipelineCardState();
}

class _PipelineCardState extends State<_PipelineCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final borderColor = selected
        ? widget.accent
        : _hovered
        ? theme.colorScheme.outline
        : theme.colorScheme.outlineVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Material(
          color: selected
              ? widget.accent.withValues(alpha: 0.09)
              : Brand.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 1.7 : 1,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          color: widget.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(widget.icon, size: 22, color: Brand.ink),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? widget.accent : Brand.line,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          selected ? 'SELECTED' : widget.tag,
                          style: TextStyle(
                            color: selected ? Brand.ink : Brand.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < widget.steps.length; i++)
                        _PipelineStepChip(
                          number: i + 1,
                          label: widget.steps[i],
                          color: widget.accent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PipelineStepChip extends StatelessWidget {
  const _PipelineStepChip({
    required this.number,
    required this.label,
    required this.color,
  });

  final int number;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Brand.ink,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Brand.line),
      ),
      child: Text(
        '$number  $label',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.onOpen,
    required this.onDelete,
  });

  final ProjectSummary project;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String _relativeTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} h ago';
    }
    return '${difference.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSimple = project.pipeline == ProjectPipeline.simple;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSimple
                    ? Icons.auto_awesome_outlined
                    : Icons.timeline_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${project.pipeline.label} · opened '
                      '${_relativeTime(project.lastOpenedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete project',
                onPressed: onDelete,
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
