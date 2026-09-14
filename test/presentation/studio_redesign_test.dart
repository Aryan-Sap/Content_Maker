import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:content_maker/src/app/brand.dart';
import 'package:content_maker/src/application/app_session_store.dart';
import 'package:content_maker/src/presentation/onboarding/project_hub_screen.dart';
import 'package:content_maker/src/presentation/render_home_screen.dart';
import 'package:content_maker/theme/editor_theme.dart';
import 'package:content_maker/theme/studio_theme.dart';
import '../support/memory_session_store.dart';

const profile = UserProfile(id: 'review', name: 'Studio review');
MemorySessionStore storeWithProjects() {
  final store = MemorySessionStore()..profiles = [profile];
  store.projects = [
    for (var i = 0; i < 3; i++)
      ProjectSummary(
        id: '$i',
        name: ['Weekend highlights', 'The final round', 'Behind the edit'][i],
        pipeline: i == 1 ? ProjectPipeline.custom : ProjectPipeline.simple,
        ownerId: profile.id,
        createdAt: DateTime(2026, 9, 5),
        lastOpenedAt: DateTime(2026, 9, 6),
      ),
  ];
  return store;
}

Future<void> openLibrary(
  WidgetTester tester,
  MemorySessionStore store, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ProjectHubScreen(profile: profile, store: store),
    ),
  );
  await tester.pump();
  await tester.pump(StudioTheme.reveal);
}

Future<void> captureSurface(WidgetTester tester, String name) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('outputs/app-redesign').createSync(recursive: true);
    File(
      'outputs/app-redesign/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('phone library at $width supports search and project setup', (
      tester,
    ) async {
      await openLibrary(tester, storeWithProjects(), size: Size(width, 844));
      expect(tester.takeException(), isNull);
      final search = find.widgetWithText(TextField, 'Search projects');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Weekend');
      await tester.pump();
      expect(find.text('Weekend highlights'), findsOneWidget);
      expect(find.text('The final round'), findsNothing);
      final create = find.widgetWithText(FilledButton, 'New project');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Project name'),
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('library persists the saved timeline association', () {
    final original = storeWithProjects().projects.first.copyWith(
      projectFilePath: 'edits/weekend.cmproj',
    );
    final restored = ProjectSummary.fromJson(original.toJson());
    expect(restored.projectFilePath, 'edits/weekend.cmproj');
    expect(
      restored.copyWith(lastOpenedAt: DateTime(2026, 9, 7)).projectFilePath,
      restored.projectFilePath,
    );
  });
  setUpAll(() async {
    for (final entry in {
      'Archivo': [
        'assets/fonts/Archivo-400.ttf',
        'assets/fonts/Archivo-500.ttf',
        'assets/fonts/Archivo-600.ttf',
        'assets/fonts/Archivo-700.ttf',
      ],
      'Bricolage Grotesque': [
        'assets/fonts/BricolageGrotesque-600.ttf',
        'assets/fonts/BricolageGrotesque-700.ttf',
        'assets/fonts/BricolageGrotesque-800.ttf',
      ],
    }.entries) {
      final font = FontLoader(entry.key);
      for (final path in entry.value) {
        font.addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      }
      await font.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('search distinguishes no matches and clears filters', (
    tester,
  ) async {
    await openLibrary(tester, storeWithProjects());
    await tester.enterText(
      find.widgetWithText(TextField, 'Search projects'),
      'no match',
    );
    await tester.pump();
    expect(find.text('No matching projects'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Weekend highlights'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed save preserves input and does not open an unsaved project',
    (tester) async {
      final store = storeWithProjects()..failSave = true;
      await openLibrary(tester, store);
      await tester.tap(find.text('New project'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Project name'),
        'Keep my title',
      );
      await tester.ensureVisible(find.text('Create project'));
      await tester.tap(find.text('Create project'));
      await tester.pump();
      expect(find.text('Keep my title'), findsOneWidget);
      expect(find.byType(RenderHomeScreen), findsNothing);
      expect(store.projects.length, 3);
      expect(find.textContaining('Project could not be saved'), findsOneWidget);
    },
  );

  testWidgets('removal can be undone without changing media files', (
    tester,
  ) async {
    final store = storeWithProjects();
    await openLibrary(tester, store);
    await tester.tap(find.byTooltip('Remove Weekend highlights from library'));
    await tester.pump();
    await tester.pump(StudioTheme.reveal);
    expect(store.projects.length, 2);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(store.projects.length, 3);
    expect(find.text('Weekend highlights'), findsOneWidget);
  });

  testWidgets('load failure offers retry and recovers to empty library', (
    tester,
  ) async {
    final store = MemorySessionStore()..failLoad = true;
    await openLibrary(tester, store);
    expect(find.text('Library unavailable'), findsOneWidget);
    store.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Your next edit starts here'), findsOneWidget);
  });

  testWidgets('reduced motion exposes the completed entrance immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: BrandEntrance(child: Text('Ready')),
        ),
      ),
    );
    expect(find.text('Ready').hitTestable(), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow library remains usable', (tester) async {
    await openLibrary(tester, storeWithProjects(), size: const Size(640, 800));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('New project'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline contents survive switching workspaces', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEditorTheme(),
        home: const RenderHomeScreen(initialPipeline: ProjectPipeline.custom),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add text'));
    await tester.pump();
    expect(find.text('Text inspector'), findsOneWidget);
    await tester.tap(find.text('Auto Render'));
    await tester.pump();
    await tester.tap(find.text('Custom Editor').first);
    await tester.pump();
    expect(find.text('Text inspector'), findsOneWidget);
  });

  for (final pipeline in ProjectPipeline.values) {
    testWidgets('${pipeline.name} editor fits a 390px phone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(),
          home: RenderHomeScreen(initialPipeline: pipeline),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Back to studio'), findsOneWidget);
    });
  }

  testWidgets('capture phone library and auto editor for review', (
    tester,
  ) async {
    await openLibrary(tester, storeWithProjects(), size: const Size(390, 844));
    await captureSurface(tester, 'mobile-project-library');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEditorTheme(),
        home: const RenderHomeScreen(initialPipeline: ProjectPipeline.simple),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await captureSurface(tester, 'mobile-auto-editor');
  });

  testWidgets('capture the implemented studio for review', (tester) async {
    await tester.runAsync(() async {
      for (final entry in {
        'Archivo': 'Archivo-400.ttf',
        'Bricolage Grotesque': 'BricolageGrotesque-700.ttf',
      }.entries) {
        final font = FontLoader(entry.key)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/${entry.value}').readAsBytesSync(),
              ),
            ),
          );
        await font.load();
      }
    });
    await openLibrary(tester, storeWithProjects());
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('outputs/app-redesign').createSync(recursive: true);
      File(
        'outputs/app-redesign/project-library.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
