import 'dart:async';
import 'package:studyforge/data/local_ai.dart';

class FakeEngine implements StudyAiEngine {
  int completions = 0;
  int stops = 0;
  bool closed = false;
  String prompt = '';
  int Function(String) count = (_) => 50;
  Completer<String>? pending;
  @override
  Future<void> load(String path) async {}
  @override
  Future<int> tokenCount(String prompt) async => count(prompt);
  @override
  Future<String> complete(String value) async {
    completions++;
    prompt = value;
    if (pending != null) return pending!.future;
    return 'An explanation.';
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pending != null && !pending!.isCompleted) {
      pending!.complete('Partial answer');
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
