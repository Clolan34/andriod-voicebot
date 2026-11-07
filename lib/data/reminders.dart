import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'models.dart';
import 'store.dart';

class ReminderService {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  bool available = false;
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_book'),
        ),
      );
      available = true;
    } catch (_) {
      available = false;
    }
  }

  Future<bool> enable() async {
    if (!available) return false;
    return await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> rebuild(StudyStore store) async {
    if (!available) return;
    // Cancel first: stable IDs and a full rebuild prevent stale or duplicate jobs.
    await plugin.cancelAll();
    if (await store.setting('reminders') != 'yes') return;
    try {
      tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()),
      );
    } catch (_) {
      // UTC preserves the instant even if the device's zone is unsupported.
      tz.setLocalLocation(tz.UTC);
    }
    final entries = await store.entries();
    for (final e in entries) {
      if (!['session', 'assignment'].contains(e.kind) ||
          e.data['done'] == true) {
        continue;
      }
      final raw = e.data[e.kind == 'session' ? 'start' : 'due'] as String?;
      if (raw == null) continue;
      final at = DateTime.parse(raw).subtract(const Duration(minutes: 10));
      if (!at.isAfter(DateTime.now())) continue;
      await _schedule(e, at);
    }
  }

  Future<void> _schedule(Entry e, DateTime at) async {
    // FNV-1a style deterministic identifier independent of Dart hash seeds.
    var id = 2166136261;
    for (final c in e.id.codeUnits) {
      id = ((id ^ c) * 16777619) & 0x7fffffff;
    }
    await plugin.zonedSchedule(
      id,
      'StudyForge • ${e.kind == 'session' ? 'Study time' : 'Deadline'}',
      e.title,
      tz.TZDateTime.from(at, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'study_reminders',
          'Study reminders',
          channelDescription: 'Upcoming sessions and deadlines',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
