import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_session_store.dart';
import '../render_home_screen.dart';
import 'login_screen.dart';

/// After login: create a new project (choosing the Simple or Custom pipeline)
/// or reopen a recent one.
class ProjectHubScreen extends StatefulWidget {
  const ProjectHubScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProjectHubScreen> createState() => _ProjectHubScreenState();
}

class _ProjectHubScreenState extends State<ProjectHubScreen> {
  final _store = const AppSessionStore();
  final _nameController = TextEditingController();

  List<UserProfile> _profiles = const [];
  List<ProjectSummary> _projects = const [];
  ProjectPipeline _pipeline = ProjectPipeline.simple;
  bool _loading = true;
  String? _error;

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
      _openProject(project);
    }
  }

  Future<void> _openProject(ProjectSummary project) async {
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
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myProjects = _myProjects;

    return Scaffold(
      appBar: AppBar(
        title: Text('Projects — ${widget.profile.name}'),
        actions: [
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'New project',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Project name',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                onSubmitted: (_) => _createProject(),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Editing pipeline',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 10),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide = constraints.maxWidth >= 560;
                                  final cards = [
                                    _PipelineCard(
                                      title: 'Simple',
                                      subtitle:
                                          'One-click auto render: drop in '
                                          'gameplay, get a polished short.',
                                      icon: Icons.auto_awesome_outlined,
                                      selected:
                                          _pipeline == ProjectPipeline.simple,
                                      onTap: () => setState(
                                        () =>
                                            _pipeline = ProjectPipeline.simple,
                                      ),
                                    ),
                                    _PipelineCard(
                                      title: 'Custom',
                                      subtitle:
                                          'Full timeline editor: multi-track '
                                          'clips, grading, transitions.',
                                      icon: Icons.timeline_outlined,
                                      selected:
                                          _pipeline == ProjectPipeline.custom,
                                      onTap: () => setState(
                                        () =>
                                            _pipeline = ProjectPipeline.custom,
                                      ),
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
                              FilledButton.icon(
                                onPressed: _createProject,
                                icon: const Icon(Icons.add_outlined),
                                label: const Text('Create project'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (myProjects.isNotEmpty) ...[
                        Text(
                          'Recent projects',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final project in myProjects)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ProjectTile(
                              project: project,
                              onOpen: () => _openProject(project),
                              onDelete: () => _deleteProject(project),
                            ),
                          ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
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
            ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
            ],
          ),
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
