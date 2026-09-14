import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/brand.dart';
import '../../../theme/studio_theme.dart';
import '../../../theme/editor_theme.dart';
import '../publishing/accounts_dialog.dart';
import '../widgets/studio_signature.dart';
import '../../application/app_session_store.dart';
import '../render_home_screen.dart';
import 'guided_tour_overlay.dart';
import 'login_screen.dart';

/// After login: create a project in the Auto or Custom pipeline
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
  _LibraryPhase _phase = _LibraryPhase.loading;
  bool _saving = false;
  bool _showComposer = false;
  String _query = '';
  ProjectPipeline? _filter;
  final _searchController = TextEditingController();
  Timer? _skeletonTimer;
  bool _showSkeleton = false;
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
    _skeletonTimer = Timer(StudioTheme.loadingDelay, () {
      if (mounted && _phase == _LibraryPhase.loading) {
        setState(() => _showSkeleton = true);
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _skeletonTimer?.cancel();
    _searchController.dispose();
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
        _phase = _LibraryPhase.ready;
        _error = null;
        _guidedTourActive = widget.startGuidedTour;
        _showComposer = _guidedTourActive;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _LibraryPhase.failed;
        _error =
            'Your library could not be loaded. Check access to your app data folder and retry.';
      });
    }
  }

  Future<void> _persist() {
    return _store.save(profiles: _profiles, projects: _projects);
  }

  Future<void> _createProject() async {
    if (_saving) return;
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
      _saving = true;
      _error = null;
    });
    try {
      await _store.save(profiles: _profiles, projects: [..._projects, project]);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Project could not be saved. Check disk access, then try again.';
          _saving = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _projects = [..._projects, project];
      _nameController.clear();
      _saving = false;
      _showComposer = false;
    });
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
          initialProjectPath: project.projectFilePath,
          onProjectSaved: (path) async {
            final updated = [
              for (final p in _projects)
                p.id == project.id ? p.copyWith(projectFilePath: path) : p,
            ];
            await _store.save(profiles: _profiles, projects: updated);
            if (mounted) setState(() => _projects = updated);
          },
          initialPipeline: project.projectFilePath == null
              ? project.pipeline
              : ProjectPipeline.custom,
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
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final undoDuration = MediaQuery.accessibleNavigationOf(context)
        ? StudioTheme.accessibleUndoDuration
        : StudioTheme.undoDuration;
    final previous = List<ProjectSummary>.of(_projects);
    setState(() => _saving = true);
    try {
      final remaining = _projects
          .where((item) => item.id != project.id)
          .toList();
      await _store.save(profiles: _profiles, projects: remaining);
      if (!mounted) return;
      setState(() {
        _projects = remaining;
        _saving = false;
      });
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Removed “${project.name}” from the library. Media files are kept.',
          ),
          duration: undoDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              if (_saving) return;
              setState(() => _saving = true);
              try {
                final restored = [
                  ..._projects,
                  if (!_projects.any((p) => p.id == project.id)) project,
                ];
                await _store.save(profiles: _profiles, projects: restored);
                if (mounted) {
                  setState(() {
                    _projects = restored;
                    _saving = false;
                  });
                }
              } catch (_) {
                if (mounted) {
                  setState(() {
                    _saving = false;
                    _error = 'Could not restore the project. Retry Undo.';
                  });
                }
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _projects = previous;
          _saving = false;
          _error =
              'Could not remove the project. Check disk access and try again.';
        });
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
      _showComposer = true;
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
        actionLabel: 'Project named — continue',
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
  Widget build(BuildContext context) => Theme(
    data: buildEditorTheme(),
    child: Builder(builder: _buildWorkspace),
  );

  Widget _buildWorkspace(BuildContext context) {
    final c = StudioTheme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1060;
    final phone =
        MediaQuery.sizeOf(context).width < StudioTheme.compactBreakpoint;
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (wide) _rail(context),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Row(
                          children: [
                            if (!wide) ...[
                              BrandLogo(
                                size: 26,
                                ringColor: c.accent,
                                letterColor: c.ink,
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (!phone) ...[
                              Text(
                                'Workspace',
                                style: TextStyle(color: c.muted),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: c.muted,
                              ),
                              const SizedBox(width: 12),
                            ],
                            const Text('Projects'),
                            const Spacer(),
                            if (!wide)
                              IconButton(
                                tooltip: 'Connected accounts',
                                onPressed: () => AccountsDialog.show(context),
                                icon: const Icon(Icons.link),
                              ),
                            if (!phone)
                              Icon(
                                Icons.computer_outlined,
                                size: 16,
                                color: c.muted,
                              ),
                            const SizedBox(width: 8),
                            if (MediaQuery.sizeOf(context).width >= 800)
                              Text(
                                'Local workspace',
                                style: TextStyle(color: c.muted),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: switch (_phase) {
                          _LibraryPhase.loading =>
                            _showSkeleton
                                ? _skeleton(context)
                                : const SizedBox.expand(),
                          _LibraryPhase.failed => Center(
                            child: _message(
                              context,
                              Icons.folder_off_outlined,
                              'Library unavailable',
                              _error!,
                              'Retry',
                              _load,
                            ),
                          ),
                          _LibraryPhase.ready => _library(context),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_guidedTourActive && _phase == _LibraryPhase.ready)
          _buildGuidedTour(),
      ],
    );
  }

  Widget _rail(BuildContext context) {
    final c = StudioTheme.of(context);
    return Container(
      width: 248,
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Material(
        color: c.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BrandLogo(size: 32, ringColor: c.accent, letterColor: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Content Maker',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: StudioTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 42),
            _eyebrow(context, 'YOUR STUDIO'),
            const SizedBox(height: 14),
            ListTile(
              dense: true,
              selected: true,
              selectedColor: c.accent,
              selectedTileColor: c.selection,
              shape: const RoundedRectangleBorder(
                borderRadius: StudioTheme.controlRadius,
              ),
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Projects'),
              trailing: Text('${_myProjects.length}'),
              onTap: () => setState(() {
                _filter = null;
                _query = '';
                _searchController.clear();
              }),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.link),
              title: const Text('Connected accounts'),
              onTap: () => AccountsDialog.show(context),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.help_outline),
              title: const Text('Guided walkthrough'),
              onTap: _showTutorial,
            ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).height >= 820)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.canvas,
                  borderRadius: StudioTheme.panelRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: c.accent, size: 20),
                    const SizedBox(height: 10),
                    const Text(
                      'Your footage. Your device.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Editing and rendering happen locally. Connect a channel when you are ready to publish.',
                      style: TextStyle(color: c.muted, height: 1.6),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: c.selection,
                child: Text(
                  widget.profile.name.isEmpty
                      ? 'C'
                      : widget.profile.name[0].toUpperCase(),
                  style: TextStyle(color: c.accent),
                ),
              ),
              title: Text(widget.profile.name, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Local profile'),
              trailing: IconButton(
                tooltip: 'Switch profile',
                onPressed: _signOut,
                icon: const Icon(Icons.logout, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _library(BuildContext context) {
    final c = StudioTheme.of(context);
    final phone =
        MediaQuery.sizeOf(context).width < StudioTheme.compactBreakpoint;
    final projects = _myProjects
        .where(
          (p) =>
              (_filter == null || p.pipeline == _filter) &&
              p.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return SingleChildScrollView(
      padding: EdgeInsets.all(phone ? StudioTheme.compactPagePadding : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flex(
            direction: phone ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: phone ? 0 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Every frame,\nyour point of view.',
                      style: TextStyle(
                        fontFamily: StudioTheme.displayFont,
                        fontSize: StudioTheme.titleSize,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick up an edit, or give your next idea a place to start.',
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 1200) ...[
                const SizedBox(width: 40),
                const SizedBox(width: 310, child: StudioSignature()),
              ],
              SizedBox(width: phone ? 0 : 16, height: phone ? 20 : 0),
              FilledButton.icon(
                onPressed: () => setState(() => _showComposer = !_showComposer),
                icon: Icon(_showComposer ? Icons.close : Icons.add),
                label: Text(_showComposer ? 'Close' : 'New project'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Your projects',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (MediaQuery.sizeOf(context).width < 1060)
                TextButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Switch profile'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (_showComposer) ...[
            _composer(context),
            const SizedBox(height: 28),
          ],
          if (_error != null) ...[
            Semantics(
              liveRegion: true,
              child: MaterialBanner(
                backgroundColor: c.panel,
                leading: Icon(Icons.error_outline, color: c.danger),
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final choice in <ProjectPipeline?>[
                null,
                ...ProjectPipeline.values,
              ])
                ChoiceChip(
                  label: Text(
                    choice == null
                        ? 'All projects'
                        : choice == ProjectPipeline.simple
                        ? 'Auto Render'
                        : 'Custom Timeline',
                  ),
                  selected: _filter == choice,
                  onSelected: (_) => setState(() => _filter = choice),
                ),
              SizedBox(
                width: phone
                    ? MediaQuery.sizeOf(context).width -
                          (StudioTheme.compactPagePadding * 2)
                    : 260,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search projects',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              color: c.panel,
              border: Border.all(color: c.line),
              borderRadius: StudioTheme.panelRadius,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _eyebrow(context, 'PROJECT / WORKFLOW')),
                      if (MediaQuery.sizeOf(context).width > 700)
                        _eyebrow(context, 'LAST OPENED'),
                      if (!phone) const SizedBox(width: 100),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (projects.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(
                      phone ? StudioTheme.compactPagePadding : 36,
                    ),
                    child: _message(
                      context,
                      _myProjects.isEmpty
                          ? Icons.video_collection_outlined
                          : Icons.search_off,
                      _myProjects.isEmpty
                          ? 'Your next edit starts here'
                          : 'No matching projects',
                      _myProjects.isEmpty
                          ? 'Create a project to format a clip or build a full timeline.'
                          : 'Try another name or clear your filters.',
                      _myProjects.isEmpty
                          ? 'Create a project'
                          : 'Clear filters',
                      () => setState(() {
                        if (_myProjects.isEmpty) {
                          _showComposer = true;
                        } else {
                          _filter = null;
                          _query = '';
                          _searchController.clear();
                        }
                      }),
                    ),
                  )
                else
                  for (final project in projects) _projectRow(context, project),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              '${projects.length} ${projects.length == 1 ? 'project' : 'projects'} · Media files stay in their original location',
              style: TextStyle(color: c.muted),
            ),
          ),
          const SizedBox(height: 34),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.subdirectory_arrow_right, size: 20, color: c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A simple path to a finished video: import footage → edit → render → publish.\nAuto Render formats clips quickly. Custom Timeline gives you control over every layer.',
                  style: TextStyle(color: c.muted, height: 1.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final c = StudioTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: StudioTheme.panelRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New project', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          TextField(
            key: _projectNameTourKey,
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Project name',
              hintText: 'e.g. Weekend highlights',
            ),
            onSubmitted: (_) {
              if (!_guidedTourActive) _createProject();
            },
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          for (final pipeline in ProjectPipeline.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _pipeline == pipeline ? c.selection : c.canvas,
                shape: RoundedRectangleBorder(
                  borderRadius: StudioTheme.controlRadius,
                  side: BorderSide(
                    color: _pipeline == pipeline ? c.accent : c.line,
                  ),
                ),
                child: ListTile(
                  key: pipeline == ProjectPipeline.simple
                      ? _autoPipelineTourKey
                      : null,
                  leading: Icon(
                    pipeline == ProjectPipeline.simple
                        ? Icons.auto_fix_high_outlined
                        : Icons.view_timeline_outlined,
                  ),
                  title: Text(
                    pipeline == ProjectPipeline.simple
                        ? 'Auto Render'
                        : 'Custom Timeline',
                  ),
                  subtitle: Text(
                    pipeline == ProjectPipeline.simple
                        ? 'Format, style and export a clip in a guided workflow.'
                        : 'Arrange video, audio and text on a multi-track timeline.',
                  ),
                  trailing: Icon(
                    _pipeline == pipeline
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  onTap: () {
                    setState(() => _pipeline = pipeline);
                    if (_guidedTourActive && _guidedTourStep == 1) {
                      _advanceGuidedTour();
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: _startProjectTourKey,
              onPressed: _saving ? null : _createProject,
              icon: const Icon(Icons.arrow_forward),
              label: Text(_saving ? 'Saving project…' : 'Create project'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectRow(BuildContext context, ProjectSummary project) {
    final c = StudioTheme.of(context);
    final phone = MediaQuery.sizeOf(context).width < 600;
    final date = project.lastOpenedAt;
    return Column(
      children: [
        InkWell(
          onTap: _saving ? null : () => _openProject(project),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: phone ? 12 : 22,
              vertical: 20,
            ),
            child: Row(
              children: [
                Container(
                  width: phone ? 40 : 58,
                  height: 52,
                  decoration: BoxDecoration(
                    color: c.inset,
                    borderRadius: StudioTheme.controlRadius,
                  ),
                  child: Icon(
                    project.pipeline == ProjectPipeline.simple
                        ? Icons.movie_outlined
                        : Icons.view_timeline_outlined,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        project.pipeline == ProjectPipeline.simple
                            ? 'Auto Render'
                            : 'Custom Timeline',
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width > 700)
                  Text(
                    '${date.day}/${date.month}/${date.year}',
                    style: TextStyle(color: c.muted),
                  ),
                const SizedBox(width: 16),
                if (!phone)
                  IconButton(
                    tooltip: 'Open ${project.name}',
                    onPressed: _saving ? null : () => _openProject(project),
                    icon: const Icon(Icons.arrow_outward, size: 20),
                  ),
                IconButton(
                  tooltip: 'Remove ${project.name} from library',
                  onPressed: _saving ? null : () => _deleteProject(project),
                  icon: Icon(Icons.close, size: 18, color: c.muted),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _eyebrow(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      color: StudioTheme.of(context).muted,
      fontSize: StudioTheme.eyebrowSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.1,
    ),
  );

  Widget _message(
    BuildContext context,
    IconData icon,
    String title,
    String detail,
    String action,
    VoidCallback onAction,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 38, color: StudioTheme.of(context).accent),
      const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        detail,
        textAlign: TextAlign.center,
        style: TextStyle(color: StudioTheme.of(context).muted),
      ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: onAction, child: Text(action)),
    ],
  );

  Widget _skeleton(BuildContext context) => Semantics(
    label: 'Loading projects',
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: i == 0 ? 90 : 72,
              margin: const EdgeInsets.only(bottom: 18),
              color: StudioTheme.of(context).inset,
            ),
        ],
      ),
    ),
  );
}

enum _LibraryPhase { loading, ready, failed }
