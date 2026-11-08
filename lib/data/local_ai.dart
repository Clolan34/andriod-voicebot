import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/ai_prompts.dart';

abstract class StudyAiEngine {
  Future<void> load(String path);
  Future<int> tokenCount(String prompt);
  Future<String> complete(String prompt);
  Future<void> stop();
  Future<void> close();
}

class PhoneAiEngine implements StudyAiEngine {
  static const _channel = MethodChannel('org.studyforge/local_ai');
  static int _nextSession = 0;
  final int _session = ++_nextSession;
  bool _loaded = false;

  @override
  Future<void> load(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('On-device AI is available in the Android app.');
    }
    if (_loaded) return;
    await _channel.invokeMethod<void>('load', {'path': path, 'session': _session});
    _loaded = true;
  }

  @override
  Future<int> tokenCount(String prompt) async {
    final count = await _channel.invokeMethod<int>('tokenCount', {'prompt': prompt, 'session': _session});
    if (count == null) throw StateError('Could not check the input size.');
    return count;
  }

  @override
  Future<String> complete(String prompt) async {
    final text = await _channel.invokeMethod<String>('generate', {'prompt': prompt, 'session': _session});
    if (text == null || text.trim().isEmpty) {
      throw StateError('No answer was produced. Try a shorter question.');
    }
    return text.trim();
  }

  @override
  Future<void> stop() async {
    if (_loaded) await _channel.invokeMethod<void>('stop', {'session': _session});
  }

  @override
  Future<void> close() async {
    if (_loaded) {
      await _channel.invokeMethod<void>('close', {'session': _session});
      _loaded = false;
    }
  }
}

class LocalStudyAi {
  final StudyAiEngine engine;
  Future<String>? _pending;
  bool _closed = false;
  bool _stopped = false;
  LocalStudyAi(this.engine);

  bool get stopped => _stopped;

  Future<String> answer({
    required String modelPath,
    required StudyAiMode mode,
    required String input,
    String notes = '',
    List<StudyAiTurn> history = const [],
  }) {
    if (_closed || _pending != null) throw StateError('AI is busy or closed.');
    if (input.trim().isEmpty) throw const FormatException('Enter some text first.');
    if (input.length > 6000 || notes.length > 6000) {
      throw const FormatException('Use a shorter passage (up to 6,000 characters).');
    }
    _stopped = false;
    final task = _answer(modelPath, mode, input, notes, history);
    _pending = task;
    return task.whenComplete(() => _pending = null);
  }

  Future<String> _answer(String path, StudyAiMode mode, String input,
      String notes, List<StudyAiTurn> history) async {
    await engine.load(path);
    var recent = history.length > 2 ? history.sublist(history.length - 2) : [...history];
    while (true) {
      if (_stopped || _closed) throw StateError('Generation stopped.');
      final prompt = studyAiPrompt(mode: mode, input: input.trim(), notes: notes, history: recent);
      if (await engine.tokenCount(prompt) <= 1500) {
        if (_stopped || _closed) throw StateError('Generation stopped.');
        return engine.complete(prompt);
      }
      if (recent.isEmpty || mode == StudyAiMode.summary) {
        throw const FormatException('This passage is too long for the phone model. Split it into smaller sections.');
      }
      recent = recent.sublist(1);
    }
  }

  Future<void> stop() async {
    _stopped = true;
    await engine.stop();
  }

  Future<void> close() async {
    _closed = true;
    _stopped = true;
    try {
      await engine.stop();
    } catch (_) {
      // A failed stop must not skip context release.
    }
    try {
      await _pending;
    } catch (_) {
      // Release even when a pending load or generation fails.
    }
    await engine.close();
  }
}
