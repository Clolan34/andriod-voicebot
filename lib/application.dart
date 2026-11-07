import 'dart:convert';
import 'package:flutter/material.dart';
import 'domain/study_rules.dart';
import 'data/backup.dart';
import 'data/files.dart';
import 'data/reminders.dart';
import 'data/store.dart';

class StudyAppState extends ChangeNotifier {
  final StudyStore store;
  final DocumentFiles files;
  final ReminderService reminders;
  late final BackupService backups = BackupService(store, files);
  String name = '';
  ThemeMode theme = ThemeMode.system;
  bool onboarded = false;
  StudyAppState(this.store, this.files, this.reminders) {
    store.addListener(notifyListeners);
  }
  @override
  void dispose() {
    store.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> refreshPreferences() async {
    name = await store.setting('name');
    onboarded = await store.setting('onboarded') == 'yes';
    theme = switch (await store.setting('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> reconcileTimer() async {
    final raw = await store.setting('focusClock');
    if (raw.isEmpty) return;
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final clock = FocusClock.fromJson(data);
    if (data['isBreak'] != true &&
        !clock.recorded &&
        clock.remaining(DateTime.now()) == 0) {
      await store.recordFocus(clock, DateTime.now());
    }
  }

  Future<void> changed() async {
    await reconcileTimer();
    try {
      await files.collect(store);
    } catch (_) {
      /* Retry orphan cleanup at next launch. */
    }
    try {
      await reminders.rebuild(store);
    } catch (_) {
      /* Planning works without reminders. */
    }
    notifyListeners();
  }
}

class AppScope extends InheritedWidget {
  final StudyAppState app;
  const AppScope({required this.app, required super.child, super.key});
  static StudyAppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.app;
  @override
  bool updateShouldNotify(AppScope old) => true;
}
