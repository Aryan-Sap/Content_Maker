import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/app/content_maker_app.dart';
import 'package:content_maker/src/application/app_session_store.dart';
import 'package:content_maker/src/presentation/render_home_screen.dart';

void main() {
  testWidgets('starts on the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ContentMakerApp());
    await tester.pumpAndSettle();

    expect(find.text('Content Maker'), findsOneWidget);
    expect(find.text('Sign in with a local profile to continue.'), findsOneWidget);
    expect(find.text('Create profile & continue'), findsOneWidget);
  });

  testWidgets('shows renderer workspace', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RenderHomeScreen(projectName: 'My Short')),
    );

    expect(find.text('My Short'), findsOneWidget);
    expect(find.text('Renderer'), findsOneWidget);
    expect(find.text('Selected video'), findsOneWidget);
    expect(find.text('Add Videos'), findsOneWidget);
    expect(find.text('Output mp4 path or batch folder'), findsOneWidget);
    expect(find.byIcon(Icons.movie_creation_outlined), findsOneWidget);
  });

  testWidgets('switches to the custom editor workspace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RenderHomeScreen()));

    await tester.tap(find.text('Custom Editor'));
    await tester.pumpAndSettle();

    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Preview'), findsWidgets);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Export Timeline'), findsOneWidget);
  });

  testWidgets('custom pipeline opens straight into the editor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RenderHomeScreen(initialPipeline: ProjectPipeline.custom),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Export Timeline'), findsOneWidget);
  });
}
