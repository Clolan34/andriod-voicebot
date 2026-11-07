import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'store.dart';

class DocumentFiles {
  final Directory root;
  DocumentFiles(this.root);
  static Future<DocumentFiles> open() async {
    final root = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'documents'),
    );
    await root.create(recursive: true);
    return DocumentFiles(root);
  }

  File file(String name) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+\.pdf$').hasMatch(name)) {
      throw const FormatException('Unsafe document name');
    }
    return File(p.join(root.path, name));
  }

  Future<String?> importPdf() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    if (selection == null) return null;
    final picked = selection.files.single;
    if (picked.size > 30 * 1024 * 1024) {
      throw const FormatException('Please choose a PDF smaller than 30 MB.');
    }
    final bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('This file is not a supported PDF.');
    }
    final doc = await PdfDocument.openData(bytes);
    try {
      if (doc.pagesCount < 1) {
        throw const FormatException('The PDF has no pages.');
      }
      final page = await doc.getPage(1);
      try {
        await page.render(width: 100, height: 140);
      } finally {
        await page.close();
      }
    } finally {
      await doc.close();
    }
    final name = '${uuid.v4()}.pdf';
    await file(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<void> collect(StudyStore store) async {
    final entries = await store.entries();
    final used = <String>{};
    for (final e in entries) {
      for (final key in ['file', 'guide']) {
        if (e.data[key] is String) used.add(e.data[key] as String);
      }
    }
    await for (final entity in root.list()) {
      if (entity is File && !used.contains(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  }

  Future<void> exportBytes(Uint8List bytes, String name) async {
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save StudyForge backup',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes,
    );
  }
}
