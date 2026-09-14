import 'package:content_maker/src/application/app_session_store.dart';

class MemorySessionStore extends AppSessionStore {
  List<UserProfile> profiles = [];
  List<ProjectSummary> projects = [];
  bool tutorialCompleted = false;
  bool failLoad = false;
  bool failSave = false;
  @override
  Future<({List<UserProfile> profiles, List<ProjectSummary> projects})> load() async {
    if (failLoad) throw StateError('simulated storage failure');
    return (profiles: profiles, projects: projects);
  }
  @override
  Future<void> save({required List<UserProfile> profiles, required List<ProjectSummary> projects}) async {
    if (failSave) throw StateError('simulated storage failure');
    this.profiles = profiles;
    this.projects = projects;
  }
  @override
  Future<bool> hasCompletedTutorial() async => tutorialCompleted;
  @override
  Future<void> markTutorialCompleted() async { tutorialCompleted = true; }
}
