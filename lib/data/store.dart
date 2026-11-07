import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/study_rules.dart';
import 'models.dart';

const uuid = Uuid();
const backupTables = [
  'courses',
  'entries',
  'attempts',
  'answers',
  'reviews',
  'focus',
  'settings',
];

class StudyStore extends ChangeNotifier {
  final Database db;
  StudyStore(this.db);
  static Future<StudyStore> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path ?? p.join(await getDatabasesPath(), 'studyforge.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE courses (id TEXT PRIMARY KEY, name TEXT NOT NULL, code TEXT NOT NULL, color INTEGER NOT NULL, topics TEXT NOT NULL)',
          );
          await db.execute(
            "CREATE TABLE entries (id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('note','session','assignment','question','card','paper')), course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE, topic TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, data TEXT NOT NULL)",
          );
          await db.execute(
            'CREATE INDEX entries_course_kind ON entries(course_id, kind)',
          );
          await db.execute(
            'CREATE TABLE attempts (id TEXT PRIMARY KEY, at TEXT NOT NULL, correct INTEGER NOT NULL, total INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE answers (id TEXT PRIMARY KEY, attempt_id TEXT NOT NULL REFERENCES attempts(id) ON DELETE CASCADE, question_id TEXT, course_id TEXT REFERENCES courses(id) ON DELETE CASCADE, topic TEXT NOT NULL, title TEXT NOT NULL, chosen INTEGER, correct INTEGER NOT NULL, explanation TEXT NOT NULL, options TEXT NOT NULL, expected INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE reviews (id TEXT PRIMARY KEY, card_id TEXT REFERENCES entries(id) ON DELETE CASCADE, course_id TEXT REFERENCES courses(id) ON DELETE CASCADE, topic TEXT NOT NULL, at TEXT NOT NULL, grade TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE focus (id TEXT PRIMARY KEY, at TEXT NOT NULL, minutes INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await _indexes(db);
        },
        onUpgrade: (db, old, next) async {
          if (old < 2) await _indexes(db);
        },
      ),
    );
    return StudyStore(database);
  }

  static Future<void> _indexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS answers_topic ON answers(course_id, topic)',
    );
    await db.execute('CREATE INDEX IF NOT EXISTS reviews_at ON reviews(at)');
  }

  Future<List<Course>> courses() async => (await db.query(
    'courses',
    orderBy: 'name COLLATE NOCASE',
  )).map(Course.fromRow).toList();
  Future<void> saveCourse(Course course) async {
    // REPLACE deletes the existing parent and would cascade child rows.
    await db.transaction((tx) async {
      if (await tx.update(
            'courses',
            course.toRow(),
            where: 'id = ?',
            whereArgs: [course.id],
          ) ==
          0) {
        await tx.insert('courses', course.toRow());
      }
    });
    notifyListeners();
  }

  Future<void> deleteCourse(String id) async {
    await db.delete('courses', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<List<Entry>> entries({
    String? kind,
    String? courseId,
    String search = '',
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (courseId != null) {
      where.add('course_id = ?');
      args.add(courseId);
    }
    if (search.trim().isNotEmpty) {
      where.add(
        '(instr(lower(title), lower(?)) > 0 OR instr(lower(body), lower(?)) > 0)',
      );
      args.addAll([search.trim(), search.trim()]);
    }
    return (await db.query(
      'entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'title COLLATE NOCASE',
    )).map(Entry.fromRow).toList();
  }

  Future<void> save(Entry entry) async {
    await db.transaction((tx) async {
      if (await tx.update(
            'entries',
            entry.toRow(),
            where: 'id = ?',
            whereArgs: [entry.id],
          ) ==
          0) {
        await tx.insert('entries', entry.toRow());
      }
    });
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<String> setting(String key, [String fallback = '']) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> recordQuiz(List<Entry> questions, List<int?> given) async {
    final result = QuizScore.calculate(
      questions.map((q) => q.data['correct'] as int).toList(),
      given,
    );
    final id = uuid.v4();
    await db.transaction((tx) async {
      await tx.insert('attempts', {
        'id': id,
        'at': DateTime.now().toUtc().toIso8601String(),
        'correct': result.correct,
        'total': result.total,
      });
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        await tx.insert('answers', {
          'id': uuid.v4(),
          'attempt_id': id,
          'question_id': q.id,
          'course_id': q.courseId,
          'topic': q.topic,
          'title': q.title,
          'chosen': given[i],
          'correct': given[i] == q.data['correct'] ? 1 : 0,
          'explanation': q.body,
          'options': jsonEncode(q.data['options']),
          'expected': q.data['correct'],
        });
      }
    });
    notifyListeners();
  }

  Future<void> review(Entry card, String grade, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final next = ReviewSchedule.next(
      at,
      (card.data['interval'] as int?) ?? 0,
      (card.data['reviews'] as int?) ?? 0,
      grade,
    );
    await db.transaction((tx) async {
      await tx.update(
        'entries',
        card.withData({
          'due': next.due.toUtc().toIso8601String(),
          'interval': next.intervalDays,
          'reviews': next.reviews,
        }).toRow(),
        where: 'id = ?',
        whereArgs: [card.id],
      );
      await tx.insert('reviews', {
        'id': uuid.v4(),
        'card_id': card.id,
        'course_id': card.courseId,
        'topic': card.topic,
        'at': at.toUtc().toIso8601String(),
        'grade': grade,
      });
    });
    notifyListeners();
  }

  Future<void> recordFocus(FocusClock clock, DateTime now) async {
    if (clock.remaining(now) > 0) return;
    await db.transaction((tx) async {
      await tx.insert('focus', {
        'id': clock.id,
        'at': now.toUtc().toIso8601String(),
        'minutes': clock.durationSeconds ~/ 60,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.insert('settings', {
        'key': 'focusClock',
        'value': jsonEncode({...clock.toJson(), 'recorded': true}),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    clock.recorded = true;
    notifyListeners();
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    return db.transaction(
      (tx) async => {
        for (final table in backupTables)
          table: (await tx.query(
            table,
          )).map((row) => Map<String, Object?>.from(row)).toList(),
      },
    );
  }

  Future<void> replace(Map<String, List<Map<String, Object?>>> tables) async {
    await db.transaction((tx) async {
      for (final table in backupTables.reversed) {
        await tx.delete(table);
      }
      for (final table in backupTables) {
        for (final row in tables[table]!) {
          await tx.insert(table, row);
        }
      }
      final invalid = await tx.rawQuery('PRAGMA foreign_key_check');
      if (invalid.isNotEmpty) {
        throw const FormatException('Broken record relationships');
      }
    });
    notifyListeners();
  }

  Future<void> clear() async {
    await db.transaction((tx) async {
      for (final table in backupTables.reversed) {
        await tx.delete(table);
      }
    });
    notifyListeners();
  }

  Future<void> loadSamples() async {
    if (await setting('samples') == 'yes') return;
    await db.transaction((tx) async {
      final demo = [
        (
          'Programming foundations',
          'DEMO-CS',
          'Variables',
          'What does a variable store?',
          ['A value', 'Only images', 'A keyboard', 'A network'],
          0,
          'A variable is a named place for a value.',
        ),
        (
          'Basic mathematics',
          'DEMO-MA',
          'Algebra',
          'If 2x + 3 = 11, what is x?',
          ['2', '3', '4', '7'],
          2,
          'Subtract 3, then divide by 2: x = 4.',
        ),
        (
          'Study skills',
          'DEMO-SS',
          'Recall',
          'Which activity practises active recall?',
          [
            'Rereading without pausing',
            'Answering from memory',
            'Highlighting every line',
            'Copying the textbook',
          ],
          1,
          'Retrieving an answer from memory practises active recall.',
        ),
      ];
      for (final s in demo) {
        final c = Course(id: uuid.v4(), name: s.$1, code: s.$2, topics: s.$3);
        await tx.insert('courses', c.toRow());
        await tx.insert(
          'entries',
          Entry(
            id: uuid.v4(),
            kind: 'question',
            courseId: c.id,
            topic: s.$3,
            title: s.$4,
            body: s.$7,
            data: {'options': s.$5, 'correct': s.$6, 'sample': true},
          ).toRow(),
        );
        await tx.insert(
          'entries',
          Entry(
            id: uuid.v4(),
            kind: 'card',
            courseId: c.id,
            topic: s.$3,
            title: s.$4,
            body: s.$5[s.$6],
            data: {
              'due': DateTime.now().toUtc().toIso8601String(),
              'interval': 0,
              'reviews': 0,
              'sample': true,
            },
          ).toRow(),
        );
      }
      await tx.insert('settings', {
        'key': 'samples',
        'value': 'yes',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    notifyListeners();
  }
}
