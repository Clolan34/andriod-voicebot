import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'files.dart';
import 'store.dart';

/// A backup is a ZIP with a versioned JSON manifest and flat UUID-named PDFs.
/// Files stage under fresh names first; one SQLite transaction swaps records.
/// Old files are collected only after commit. A failure leaves old data intact.
class BackupService {
  final StudyStore store;
  final DocumentFiles files;
  BackupService(this.store, this.files);
  Future<Uint8List> export() async {
    final tables = await store.snapshot();
    final names = <String>{};
    for (final r in tables['entries']!) {
      final data = jsonDecode(r['data'] as String) as Map;
      for (final key in ['file', 'guide']) {
        if (data[key] is String) names.add(data[key] as String);
      }
    }
    final archive = Archive();
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'StudyForge',
        'version': 1,
        'created': DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      }),
    );
    if (manifest.length > 10 * 1024 * 1024) {
      throw const FormatException(
        'Records exceed the 10 MB backup manifest limit.',
      );
    }
    var expanded = manifest.length;
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    for (final name in names) {
      final size = await files.file(name).length();
      expanded += size;
      if (expanded > 100 * 1024 * 1024) {
        throw const FormatException(
          'Documents exceed the 100 MB expanded backup limit.',
        );
      }
      final bytes = await files.file(name).readAsBytes();
      archive.addFile(ArchiveFile('files/$name', bytes.length, bytes));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    if (encoded.length > 50 * 1024 * 1024) {
      throw const FormatException('Backup exceeds the 50 MB archive limit.');
    }
    return encoded;
  }

  static Map<String, List<Map<String, Object?>>> validateManifest(
    dynamic value,
  ) {
    if (value is! Map ||
        value['format'] != 'StudyForge' ||
        value['version'] != 1 ||
        value['tables'] is! Map) {
      throw const FormatException('Unsupported backup format or version.');
    }
    final result = <String, List<Map<String, Object?>>>{};
    final raw = value['tables'] as Map;
    if (raw.length != backupTables.length) {
      throw const FormatException('Unexpected tables');
    }
    const columns = {
      'courses': ['id', 'name', 'code', 'color', 'topics'],
      'entries': ['id', 'kind', 'course_id', 'topic', 'title', 'body', 'data'],
      'attempts': ['id', 'at', 'correct', 'total'],
      'answers': [
        'id',
        'attempt_id',
        'question_id',
        'course_id',
        'topic',
        'title',
        'chosen',
        'correct',
        'explanation',
        'options',
        'expected',
      ],
      'reviews': ['id', 'card_id', 'course_id', 'topic', 'at', 'grade'],
      'focus': ['id', 'at', 'minutes'],
      'settings': ['key', 'value'],
    };
    for (final table in backupTables) {
      if (raw[table] is! List || (raw[table] as List).length > 50000) {
        throw FormatException('Missing or oversized table: $table');
      }
      result[table] = (raw[table] as List).map((r) {
        if (r is! Map ||
            r.length != columns[table]!.length ||
            !columns[table]!.every(r.containsKey) ||
            r.values.any((v) => v != null && v is! String && v is! int)) {
          throw FormatException('Invalid $table record');
        }
        return Map<String, Object?>.from(r);
      }).toList();
    }
    for (final table in backupTables) {
      final integers =
          <String, Set<String>>{
            'courses': {'color'},
            'attempts': {'correct', 'total'},
            'answers': {'chosen', 'correct', 'expected'},
            'focus': {'minutes'},
          }[table] ??
          <String>{};
      for (final row in result[table]!) {
        for (final field in row.keys) {
          final v = row[field];
          if (v == null &&
              table == 'answers' &&
              ['chosen', 'question_id'].contains(field)) {
            continue;
          }
          if (integers.contains(field) ? v is! int : v is! String) {
            throw FormatException('Invalid $table.$field type');
          }
        }
        if (row.containsKey('at') &&
            DateTime.tryParse(row['at'] as String) == null) {
          throw const FormatException('Invalid activity date');
        }
        if (table == 'settings' &&
            ['studyMinutes', 'breakMinutes'].contains(row['key'])) {
          final minutes = int.tryParse(row['value'] as String);
          final limit = row['key'] == 'breakMinutes' ? 60 : 180;
          if (minutes == null || minutes < 1 || minutes > limit) {
            throw const FormatException('Invalid timer preference');
          }
        }
        if (table == 'answers') {
          final options = jsonDecode(row['options'] as String);
          if (options is! List ||
              options.length != 4 ||
              !options.every((o) => o is String) ||
              ![0, 1, 2, 3].contains(row['expected']) ||
              (row['chosen'] != null &&
                  ![0, 1, 2, 3].contains(row['chosen'])) ||
              ![0, 1].contains(row['correct'])) {
            throw const FormatException('Invalid saved quiz answer');
          }
        }
        if (table == 'attempts' &&
            ((row['total'] as int) < 1 ||
                (row['correct'] as int) < 0 ||
                (row['correct'] as int) > (row['total'] as int))) {
          throw const FormatException('Invalid quiz score');
        }
        if (table == 'focus' &&
            ((row['minutes'] as int) < 1 || (row['minutes'] as int) > 180)) {
          throw const FormatException('Invalid focus duration');
        }
      }
    }
    for (final r in result['entries']!) {
      if (r['data'] is! String) {
        throw const FormatException('Invalid entry metadata');
      }
      final d = jsonDecode(r['data'] as String);
      if (d is! Map) throw const FormatException('Invalid entry metadata');
      final kind = r['kind'];
      if (![
        'note',
        'session',
        'assignment',
        'question',
        'card',
        'paper',
      ].contains(kind)) {
        throw const FormatException('Unknown study record type');
      }
      for (final flag in ['done', 'favorite', 'sample']) {
        if (d[flag] != null && d[flag] is! bool) {
          throw const FormatException('Invalid record flag');
        }
      }
      for (final count in ['interval', 'reviews', 'completedMinutes']) {
        if (d[count] != null && (d[count] is! int || (d[count] as int) < 0)) {
          throw const FormatException('Invalid scheduling count');
        }
      }
      final requiredDate = kind == 'session'
          ? 'start'
          : ['card', 'assignment'].contains(kind)
          ? 'due'
          : null;
      if (requiredDate != null &&
          (d[requiredDate] is! String ||
              DateTime.tryParse(d[requiredDate] as String) == null)) {
        throw const FormatException('Missing required study date');
      }
      if (kind == 'session' &&
          (d['minutes'] is! int ||
              (d['minutes'] as int) < 1 ||
              (d['minutes'] as int) > 10000)) {
        throw const FormatException('Invalid study duration');
      }
      if (kind == 'assignment' &&
          !['Low', 'Normal', 'High'].contains(d['priority'])) {
        throw const FormatException('Invalid assignment priority');
      }
      if (kind == 'paper' &&
          (d['year'] is! int ||
              !['1', '2', 'Summer', 'Other'].contains(d['semester']) ||
              d['file'] is! String)) {
        throw const FormatException('Invalid paper details');
      }
      if (r['kind'] == 'question' &&
          (d['options'] is! List ||
              (d['options'] as List).length != 4 ||
              !(d['options'] as List).every((v) => v is String) ||
              d['correct'] is! int ||
              (d['correct'] as int) < 0 ||
              (d['correct'] as int) > 3)) {
        throw const FormatException('Invalid question');
      }
      for (final k in ['due', 'start']) {
        if (d[k] != null &&
            (d[k] is! String || DateTime.tryParse(d[k] as String) == null)) {
          throw const FormatException('Invalid date');
        }
      }
      for (final k in ['file', 'guide']) {
        if (d[k] != null &&
            (d[k] is! String ||
                !RegExp(r'^[a-zA-Z0-9_-]+\.pdf$').hasMatch(d[k] as String))) {
          throw const FormatException('Invalid document path');
        }
      }
    }
    // Running timers never resume from a backup made on another device.
    result['settings']!.removeWhere((r) => r['key'] == 'focusClock');
    return result;
  }

  Future<void> restore(Uint8List bytes) async {
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('Backup exceeds 50 MB.');
    }
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);
    if (decoder.directory.fileHeaders.length != archive.length) {
      throw const FormatException('Duplicate archive paths');
    }
    var total = 0;
    final names = <String>{};
    for (final f in archive) {
      if (!f.isFile ||
          f.isSymbolicLink ||
          !names.add(f.name) ||
          !(f.name == 'manifest.json' ||
              RegExp(r'^files/[a-zA-Z0-9_-]+\.pdf$').hasMatch(f.name))) {
        throw const FormatException('Unexpected or unsafe backup path.');
      }
      total += f.size;
      if (total > 100 * 1024 * 1024) {
        throw const FormatException('Expanded backup exceeds 100 MB.');
      }
    }
    for (final f in archive) {
      final content = f.content;
      if (content.length != f.size || getCrc32(content) != f.crc32) {
        throw const FormatException('Damaged backup file');
      }
    }
    final manifest = archive.findFile('manifest.json');
    if (manifest == null || manifest.size > 10 * 1024 * 1024) {
      throw const FormatException('Missing or oversized manifest.');
    }
    final tables = validateManifest(jsonDecode(utf8.decode(manifest.content)));
    final staged = <String>[];
    final renamed = <String, String>{};
    try {
      for (final row in tables['entries']!) {
        final data = Map<String, dynamic>.from(
          jsonDecode(row['data'] as String) as Map,
        );
        for (final key in ['file', 'guide']) {
          if (data[key] == null) continue;
          final old = data[key] as String;
          if (!renamed.containsKey(old)) {
            final source = archive.findFile('files/$old');
            if (source == null) {
              throw const FormatException('A referenced PDF is missing.');
            }
            final content = source.content;
            if (content.length < 5 ||
                String.fromCharCodes(content.take(5)) != '%PDF-') {
              throw const FormatException('An imported document is not a PDF.');
            }
            final name = '${uuid.v4()}.pdf';
            staged.add(name);
            await files.file(name).writeAsBytes(content, flush: true);
            renamed[old] = name;
          }
          data[key] = renamed[old];
        }
        row['data'] = jsonEncode(data);
      }
      await store.replace(tables);
    } catch (_) {
      for (final name in staged) {
        final f = files.file(name);
        if (await f.exists()) await f.delete();
      }
      rethrow;
    }
    // Cleanup is best effort after commit: it must never roll back valid data.
    try {
      await files.collect(store);
    } catch (_) {
      /* retry at next launch */
    }
  }
}
