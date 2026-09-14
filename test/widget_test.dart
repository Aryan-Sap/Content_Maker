import 'support/memory_session_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/app/content_maker_app.dart';
import 'package:content_maker/src/application/app_session_store.dart';
import 'package:content_maker/src/presentation/render_home_screen.dart';

void main() {
  testWidgets('starts the hands-on tour inside the real project flow', (
    WidgetTester tester,
  ) async {
    final store = MemorySessionStore();

    await tester.pumpWidget(ContentMakerApp(sessionStore: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('CONTENT MAKER'), findsOneWidget);
    expect(
      find.text('Profiles and projects are stored only on this device.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'Tour Creator');
    await tester.ensureVisible(find.text('Enter Content Maker'));
    await tester.tap(find.text('Enter Content Maker'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Name a real project'), findsOneWidget);
    expect(find.text('STEP 1 OF 13'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Project name'),
      'My guided edit',
    );
    await tester.pump();
    await tester.tap(find.text('Project named — continue'));
    await tester.pump();

    expect(find.text('Choose Auto Render'), findsOneWidget);
    await tester.tap(find.text('Skip tour'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(await store.hasCompletedTutorial(), isTrue);
  });

  testWidgets('shows renderer workspace', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RenderHomeScreen(projectName: 'My Short')),
    );

    expect(find.text('My Short'), findsOneWidget);
    expect(find.text('Automatic renderer'), findsOneWidget);
    expect(find.text('Selected video'), findsOneWidget);
    expect(find.text('Add Videos'), findsOneWidget);
    expect(find.text('Output mp4 path or batch folder'), findsOneWidget);
    expect(find.text('Start (m:ss)'), findsOneWidget);
    expect(find.text('End (m:ss)'), findsOneWidget);
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
    expect(find.byTooltip('Add text'), findsOneWidget);
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

  testWidgets('adds a text overlay with styling and timing controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: RenderHomeScreen(initialPipeline: ProjectPipeline.custom),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add text'));
    await tester.pumpAndSettle();

    expect(find.text('Text inspector'), findsOneWidget);
    expect(find.text('Font size'), findsOneWidget);
    expect(find.text('Text colour'), findsOneWidget);
    expect(find.text('Visible for'), findsOneWidget);
    expect(find.text('Fade out'), findsOneWidget);
  });
}
