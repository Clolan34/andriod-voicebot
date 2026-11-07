import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:sqlite3/open.dart' as sqlite;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studyforge/data/backup.dart';
import 'package:studyforge/data/files.dart';
import 'package:studyforge/data/models.dart';
import 'package:studyforge/data/store.dart';
import 'package:studyforge/domain/study_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    sqlite.open.overrideFor(
      sqlite.OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  sqfliteFfiInit();
  late StudyStore store;
  late Directory root;
  late DocumentFiles files;
  late BackupService backups;
  const course = Course(
    id: 'c1',
    name: 'Mathematics',
    code: 'M101',
    topics: 'Algebra',
  );
  Entry entry(
    String kind, {
    String id = 'e1',
    Map<String, dynamic> data = const {},
  }) => Entry(
    id: id,
    kind: kind,
    courseId: 'c1',
    title: 'Question',
    body: 'Explanation',
    topic: 'Algebra',
    data: data,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('studyforge-test-');
    store = await StudyStore.open(
      path: '${root.path}/test.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    files = DocumentFiles(Directory('${root.path}/documents'));
    await files.root.create();
    backups = BackupService(store, files);
    await store.saveCourse(course);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'Create, edit, search, favourite and delete notes; update preserves children',
    () async {
      await store.save(entry('note'));
      await store.saveCourse(const Course(id: 'c1', name: 'Renamed'));
      expect((await store.entries()).length, 1);
      await store.save(entry('note').withData({'favorite': true}));
      expect(
        (await store.entries(search: 'explanation')).single.data['favorite'],
        true,
      );
      expect(await store.entries(search: '%'), isEmpty);
      await store.delete('e1');
      expect(await store.entries(), isEmpty);
    },
  );
  test(
    'Foreign keys enforce relationships and course deletion cascades',
    () async {
      await store.save(
        entry('card', data: {'due': DateTime.now().toIso8601String()}),
      );
      await store.review((await store.entries()).single, 'Good');
      await store.deleteCourse('c1');
      expect(await store.entries(), isEmpty);
      expect(await store.db.query('reviews'), isEmpty);
      await expectLater(
        store.save(entry('note')),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test(
    'Quiz attempts save snapshots and wrong answers; edits preserve history',
    () async {
      final q = entry(
        'question',
        data: {
          'options': ['a', 'b', 'c', 'd'],
          'correct': 2,
        },
      );
      await store.save(q);
      await store.recordQuiz([q], [0]);
      await store.recordQuiz([q], [2]);
      final attempts = await store.db.query('attempts', orderBy: 'rowid');
      expect(attempts.map((a) => a['correct']).toList(), [0, 1]);
      await store.delete(q.id);
      final answers = await store.db.query('answers');
      expect(answers.length, 2);
      expect(answers.first['explanation'], 'Explanation');
    },
  );
  test('Reviews update schedule and record actual history', () async {
    final now = DateTime.utc(2026, 1, 1);
    final card = entry(
      'card',
      data: {'due': now.toIso8601String(), 'interval': 0, 'reviews': 0},
    );
    await store.save(card);
    await store.review(card, 'Easy', now: now);
    final saved = (await store.entries()).single;
    expect(saved.data['interval'], 4);
    expect(saved.data['reviews'], 1);
    expect(
      DateTime.parse(saved.data['due'] as String),
      now.add(const Duration(days: 4)),
    );
    expect((await store.db.query('reviews')).single['grade'], 'Easy');
  });
  test(
    'Focus completion is idempotent even across recovered timer objects',
    () async {
      final now = DateTime.utc(2026, 1, 1);
      final clock = FocusClock(id: 'unique', durationSeconds: 1500)..start(now);
      final finish = now.add(const Duration(minutes: 25));
      await store.recordFocus(clock, finish);
      await store.recordFocus(
        FocusClock(id: 'unique', durationSeconds: 1500, remainingSeconds: 0),
        finish,
      );
      expect((await store.db.query('focus')).length, 1);
      expect((await store.db.query('focus')).single['minutes'], 25);
      expect(jsonDecode(await store.setting('focusClock'))['recorded'], true);
    },
  );
  test(
    'Durable storage survives database close/reopen, v1 indexes migrate',
    () async {
      await store.save(entry('note'));
      final path = store.db.path;
      await store.db.execute('DROP INDEX answers_topic');
      await store.db.execute('PRAGMA user_version = 1');
      await store.db.close();
      store.dispose();
      store = await StudyStore.open(
        path: path,
        factory: databaseFactoryFfiNoIsolate,
      );
      expect((await store.entries()).single.title, 'Question');
      expect(
        await store.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'answers_topic'",
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'Samples opt in without fake activity and do not reload twice',
    () async {
      expect(await store.entries(), isEmpty);
      await store.loadSamples();
      await store.loadSamples();
      expect((await store.courses()).length, 4);
      expect((await store.entries(kind: 'question')).length, 3);
      expect(await store.db.query('attempts'), isEmpty);
      expect(await store.db.query('focus'), isEmpty);
    },
  );
  test(
    'Versioned backup restores rows and files under fresh private names',
    () async {
      await files.file('test.pdf').writeAsBytes(utf8.encode('%PDF-1.4 test'));
      await store.save(entry('note', data: {'file': 'test.pdf'}));
      final bytes = await backups.export();
      await store.clear();
      await backups.restore(bytes);
      final saved = (await store.entries()).single;
      expect(saved.data['file'], isNot('test.pdf'));
      expect(
        await files.file(saved.data['file'] as String).readAsString(),
        '%PDF-1.4 test',
      );
      expect(await files.file('test.pdf').exists(), false);
    },
  );
  Uint8List zip(dynamic manifest, {String? name}) {
    final a = Archive();
    final b = utf8.encode(jsonEncode(manifest));
    a.addFile(ArchiveFile('manifest.json', b.length, b));
    if (name != null) a.addFile(ArchiveFile(name, 1, [1]));
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  test(
    'Traversal, unknown versions and missing documents preserve current data',
    () async {
      await store.save(entry('note'));
      final tables = await store.snapshot();
      final manifest = {'format': 'StudyForge', 'version': 1, 'tables': tables};
      await expectLater(
        backups.restore(zip(manifest, name: '../escape')),
        throwsFormatException,
      );
      await expectLater(
        backups.restore(zip({...manifest, 'version': 9})),
        throwsFormatException,
      );
      tables['entries']!.first['data'] = jsonEncode({'file': 'missing.pdf'});
      await expectLater(backups.restore(zip(manifest)), throwsFormatException);
      expect((await store.entries()).single.id, 'e1');
    },
  );
  test('Transaction failure rolls back rows and staged files', () async {
    await store.save(entry('note'));
    final tables = await store.snapshot();
    tables['entries']!.first['course_id'] = 'missing-course';
    tables['entries']!.first['data'] = jsonEncode({'file': 'a.pdf'});
    final a = Archive();
    final manifest = utf8.encode(
      jsonEncode({'format': 'StudyForge', 'version': 1, 'tables': tables}),
    );
    final pdf = utf8.encode('%PDF-1.4 staged');
    a.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    a.addFile(ArchiveFile('files/a.pdf', pdf.length, pdf));
    await expectLater(
      backups.restore(Uint8List.fromList(ZipEncoder().encode(a))),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.entries()).single.courseId, 'c1');
    expect(await files.root.list().toList(), isEmpty);
  });
  test('Delete all data clears every table and collects files', () async {
    await files.file('unused.pdf').writeAsString('%PDF-test');
    await store.save(entry('note'));
    await store.set('name', 'Ama');
    await store.clear();
    await files.collect(store);
    for (final table in backupTables) {
      expect(await store.db.query(table), isEmpty);
    }
    expect(await files.root.list().toList(), isEmpty);
  });
}
