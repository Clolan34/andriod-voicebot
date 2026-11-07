import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyforge/data/reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Initialisation never requests permission; explicit opt-in can be denied',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final calls = <String>[];
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestNotificationsPermission') return false;
            return true;
          });
      final reminders = ReminderService();
      await reminders.init();
      expect(reminders.available, true);
      expect(calls, isNot(contains('requestNotificationsPermission')));
      expect(await reminders.enable(), false);
      expect(
        calls.where((m) => m == 'requestNotificationsPermission').length,
        1,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
