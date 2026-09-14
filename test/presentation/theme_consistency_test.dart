import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:content_maker/src/app/brand.dart';
import 'package:content_maker/src/app/content_maker_app.dart';
import 'package:content_maker/src/application/app_session_store.dart';
import 'package:content_maker/src/domain/publishing/auth/oauth_credentials.dart';
import 'package:content_maker/src/domain/publishing/auth/oauth_token_store.dart';
import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/infrastructure/publishing/publishing_registry.dart';
import 'package:content_maker/src/presentation/onboarding/login_screen.dart';
import 'package:content_maker/src/presentation/render_home_screen.dart';
import 'package:content_maker/src/presentation/publishing/publish_panel.dart';
import 'package:content_maker/theme/editor_theme.dart';
import 'package:content_maker/theme/studio_theme.dart';
import '../support/memory_session_store.dart';

class _EmptyTokens implements OAuthTokenStore {
  @override
  Future<OAuthCredentials?> read(PublishTarget target) async => null;
  @override
  Future<void> write(
    PublishTarget target,
    OAuthCredentials credentials,
  ) async {}
  @override
  Future<void> delete(PublishTarget target) async {}
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  Finder? target,
}) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    target ?? find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('outputs/app-redesign/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final family in {
      'Archivo': ['400', '500', '600', '700'],
      'Bricolage Grotesque': ['600', '700', '800'],
    }.entries) {
      final loader = FontLoader(family.key);
      final fileFamily = family.key.replaceAll(' ', '');
      for (final weight in family.value) {
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/$fileFamily-$weight.ttf').readAsBytesSync(),
            ),
          ),
        );
      }
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {});

  test('chrome contrast and authored light palette stay consistent', () {
    final theme = buildEditorTheme();
    expect(theme.brightness, Brightness.light);
    expect(theme.extension<StudioTheme>()!.panel, StudioTheme.light.panel);
    expect(Brand.surface, StudioTheme.light.panel);
    expect(Brand.cream, StudioTheme.light.ink);
    expect(Brand.lime, StudioTheme.light.accent);
    for (final pair in [
      (Brand.cream, Brand.surface),
      (Brand.muted, Brand.surfaceSunken),
      (Brand.ink, Brand.lime),
    ]) {
      final a = pair.$1.computeLuminance();
      final b = pair.$2.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('app uses light theme even when the OS requests dark', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ContentMakerApp(sessionStore: MemorySessionStore()),
    );
    await tester.pump();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('capture profiles editors and publishing with the same theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemorySessionStore()
      ..profiles = [const UserProfile(id: 'review', name: 'Studio review')];
    for (final screen in <String, Widget>{
      'profiles': LoginScreen(store: store),
      'auto-editor': const RenderHomeScreen(projectName: 'Weekend highlights'),
      'manual-editor': const RenderHomeScreen(
        projectName: 'The final round',
        initialPipeline: ProjectPipeline.custom,
      ),
      'publishing': Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 720,
              child: PublishPanel(
                videoPath: 'review.mp4',
                defaultTitle: 'Weekend highlights',
                registry: PublishingRegistry(tokenStore: _EmptyTokens()),
              ),
            ),
          ),
        ),
      ),
    }.entries) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(theme: buildEditorTheme(), home: screen.value),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: screen.key);
      await _capture(tester, screen.key);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('export the approved vector mark with an alpha background', (
    tester,
  ) async {
    const key = ValueKey('logo-export');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: BrandLogo(size: 512)),
        ),
      ),
    );
    await _capture(tester, 'logo-transparent', target: find.byKey(key));
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: BrandLogo(size: 512, letterColor: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
    await _capture(tester, 'logo-launcher', target: find.byKey(key));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(rgba!.getUint8(3), 0, reason: 'Corner must be transparent');
      image.dispose();
    });
  });
}
