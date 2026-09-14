import 'package:flutter/material.dart';
import '../../theme/editor_theme.dart';
import '../../theme/studio_theme.dart';
import '../application/app_session_store.dart';
import '../presentation/onboarding/first_run_tutorial_screen.dart';

class ContentMakerApp extends StatelessWidget {
  const ContentMakerApp({
    super.key,
    this.sessionStore = const AppSessionStore(),
  });
  final AppSessionStore sessionStore;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Content Maker',
    theme: buildEditorTheme(),
    darkTheme: buildStudioTheme(Brightness.dark),
    themeMode: ThemeMode.light,
    themeAnimationStyle: AnimationStyle.noAnimation,
    home: AppEntryGate(store: sessionStore),
  );
}
