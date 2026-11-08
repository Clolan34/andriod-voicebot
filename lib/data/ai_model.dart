import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Only the verified small model is accepted; arbitrary native model files
/// are not loaded. Kept outside the document/backup directory.
class AiModelFile {
  static const downloadUrl =
      'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/'
      'resolve/main/smollm2-360m-instruct-q8_0.gguf';
  static const modelPage =
      'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF';
  static const modelSha256 =
      '48ab3034d0dd401fbc721eb1df3217902fee7dab9078992d66431f09b7750201';
  static const maxBytes = 420 * 1024 * 1024;
  final Directory root;
  final String expectedHash;
  http.Client? _client;
  bool _busy = false;
  bool _cancelled = false;

  AiModelFile(this.root, {this.expectedHash = modelSha256});

  static Future<AiModelFile> open() async => AiModelFile(
    Directory(p.join((await getApplicationSupportDirectory()).path, 'ai-model')),
  );

  File get file => File(p.join(root.path, 'smollm2.gguf'));
  bool get busy => _busy;
  Future<bool> exists() => file.exists();

  Future<void> verify() async {
    final length = await file.length();
    if (length == 0 || length > maxBytes ||
        (await sha256.bind(file.openRead()).first).toString() != expectedHash) {
      throw const FormatException('Model verification failed. Remove it and download again.');
    }
  }

  /// Bounded streaming import/download with atomic promotion after verification.
  Future<void> _install(
    Future<Stream<List<int>>> Function() source,
    void Function(int bytes) onProgress,
  ) async {
    if (_busy) throw StateError('A model operation is already running.');
    _busy = true;
    _cancelled = false;
    final partial = File('${file.path}.part');
    IOSink? sink;
    try {
      await root.create(recursive: true);
      final stream = await source();
      sink = partial.openWrite();
      var bytes = 0;
      await for (final chunk in stream.timeout(const Duration(seconds: 60))) {
        if (_cancelled) throw StateError('Model setup cancelled.');
        bytes += chunk.length;
        if (bytes > maxBytes) throw const FormatException('Model file is too large.');
        sink.add(chunk);
        // Keep writes bounded rather than queuing the entire model in memory.
        await sink.flush();
        onProgress(bytes);
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw StateError('Model setup cancelled.');
      if (bytes == 0 ||
          (await sha256.bind(partial.openRead()).first).toString() != expectedHash) {
        throw const FormatException('The file is incomplete or is not the supported SmolLM2 model.');
      }
      if (_cancelled) throw StateError('Model setup cancelled.');
      await partial.rename(file.path);
    } finally {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      _client?.close();
      _client = null;
      _busy = false;
    }
  }

  Future<void> download(void Function(int) onProgress) => _install(() async {
    final client = _client = http.Client();
    final response = await client.send(
      http.Request('GET', Uri.parse(downloadUrl)),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const HttpException('Model download unavailable. Retry or import the model file.');
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw const FormatException('Model download is too large.');
    }
    return response.stream;
  }, onProgress);

  Future<void> importFile(String path, void Function(int) onProgress) =>
      _install(() async {
        if (await File(path).length() > maxBytes) {
          throw const FormatException('Model file is too large.');
        }
        return File(path).openRead();
      }, onProgress);

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  Future<void> remove() async {
    if (_busy) throw StateError('Wait for model setup to finish.');
    if (await file.exists()) await file.delete();
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();
  }
}
