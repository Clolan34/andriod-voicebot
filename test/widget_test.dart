import 'dart:io';
import 'dart:ffi' show DynamicLibrary;
import 'package:sqlite3/open.dart' as sqlite;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studyforge/application.dart';
import 'package:studyforge/data/files.dart';
import 'package:studyforge/data/reminders.dart';
import 'package:studyforge/data/store.dart';
import 'package:studyforge/main.dart';
import 'package:crypto/crypto.dart';
import 'package:studyforge/data/ai_model.dart';
import 'package:studyforge/data/models.dart';
import 'package:studyforge/data/local_ai.dart';
import 'package:studyforge/ui/ai.dart';
import 'support/fake_ai.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    sqlite.open.overrideFor(
      sqlite.OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  sqfliteFfiInit();
  late StudyAppState app;
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('studyforge-ui-');
    final store = await StudyStore.open(
      path: '${root.path}/db',
      factory: databaseFactoryFfiNoIsolate,
    );
    final files = DocumentFiles(Directory('${root.path}/docs'));
    await files.root.create();
    app = StudyAppState(store, files, ReminderService());
    app.onboarded = true;
  });
  tearDown(() async {
    await app.store.db.close();
    app.dispose();
    app.store.dispose();
    await root.delete(recursive: true);
  });
  testWidgets('All primary screens work at 320 pixels with 1.6x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(StudyForge(app: app));
    await settle(tester);
    expect(find.textContaining('Hello'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Review cards'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(find.text('Review cards'));
    await settle(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'card'},
    );
    expect(tester.takeException(), isNull);
    for (final label in [
      'Courses',
      'Planner',
      'Practice',
      'Progress',
      'Home',
    ]) {
      final target = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      await tester.tap(target);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Make it yours'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('First launch can skip onboarding without loading samples', (
    tester,
  ) async {
    app.onboarded = false;
    await tester.pumpWidget(StudyForge(app: app));
    await settle(tester);
    await tester.ensureVisible(find.text('Skip introduction'));
    await tester.tap(find.text('Skip introduction'));
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(await app.store.courses(), isEmpty);
    expect(await app.store.setting('onboarded'), 'yes');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Creating a course and note refreshes the visible course immediately',
    (tester) async {
      await tester.pumpWidget(StudyForge(app: app));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Courses'),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Add course'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Economics');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Economics'), findsOneWidget);
      await tester.tap(find.text('Economics'));
      await settle(tester);
      await tester.tap(find.text('Add note or PDF'));
      await settle(tester);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Supply and demand',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'A locally stored study note.',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Supply and demand'), findsOneWidget);
      expect(
        (await app.store.entries(kind: 'note')).single.body,
        'A locally stored study note.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('AI setup is accessible without an API key at narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(home: StudyAiPage(
      model: AiModelFile(Directory('${root.path}/ai')),
      ai: LocalStudyAi(FakeEngine()),
    )));
    await settle(tester);
    expect(find.text('Set up offline AI'), findsOneWidget);
    await tester.ensureVisible(find.text('Download free model'));
    await tester.tap(find.text('Download free model'));
    await settle(tester);
    expect(find.text('Download the free model?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AI summary returns generated text and switching modes clears it', (tester) async {
    final bytes = [1, 2, 3, 4];
    final model = AiModelFile(Directory('${root.path}/ai'),
      expectedHash: sha256.convert(bytes).toString());
    await model.root.create();
    await model.file.writeAsBytes(bytes);
    final engine = FakeEngine();
    await tester.pumpWidget(MaterialApp(home: StudyAiPage(
      initialText: 'Photosynthesis converts light into chemical energy.',
      model: model, ai: LocalStudyAi(engine),
    )));
    await settle(tester);
    await tester.ensureVisible(find.text('Summarize on this phone'));
    await tester.tap(find.text('Summarize on this phone'));
    await settle(tester);
    expect(find.text('An explanation.'), findsOneWidget);
    expect(engine.prompt, contains('Photosynthesis'));
    await tester.ensureVisible(find.text('Tutor'));
    await tester.tap(find.text('Tutor'));
    await settle(tester);
    expect(find.text('An explanation.'), findsNothing);
    expect(find.text('Ask tutor'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('An AI response can be explicitly saved as a course note', (tester) async {
    await app.store.saveCourse(const Course(id: 'ai-course', name: 'Biology'));
    final bytes = [1, 2, 3];
    final model = AiModelFile(Directory('${root.path}/ai'), expectedHash: sha256.convert(bytes).toString());
    await model.root.create();
    await model.file.writeAsBytes(bytes);
    await tester.pumpWidget(AppScope(app: app, child: MaterialApp(home: StudyAiPage(
      initialText: 'Cells are the basic units of life.', courseId: 'ai-course',
      model: model, ai: LocalStudyAi(FakeEngine()),
    ))));
    await settle(tester);
    await tester.ensureVisible(find.text('Summarize on this phone'));
    await tester.tap(find.text('Summarize on this phone'));
    await settle(tester);
    await tester.ensureVisible(find.text('Save as course note'));
    await tester.tap(find.text('Save as course note'));
    await settle(tester);
    await tester.tap(find.text('• Biology'));
    await settle(tester);
    final entries = await app.store.entries(kind: 'note');
    expect(entries.single.body, contains('An explanation.'));
    expect(entries.single.body, contains('Generated locally with SmolLM2'));
    expect(entries.single.courseId, 'ai-course');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Dashboard screenshot uses real empty data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      if (sdk == null) return;
      for (final item in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(item.key)
          ..addFont(
            File(
              '$sdk/bin/cache/artifacts/material_fonts/${item.value}',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: StudyForge(app: app),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await render.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('build/screenshots');
      await out.create(recursive: true);
      await File(
        '${out.path}/StudyForge-home.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      img.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
