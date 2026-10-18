/// The device's own notifications for the reminders in the notes (#431):
/// an Android alarm, a Windows toast, a macOS notification, at a reminder's
/// time. The notes are the only record; this keeps the device's schedule
/// equal to them.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:timezone/timezone.dart' as tz;

/// What the device can do with a reminder; a fake in tests.
abstract interface class ReminderNotifier {
  /// Whether Notelore may show notifications now.
  Future<bool> isAllowed();

  /// Asks the user; whether they allowed it.
  Future<bool> ask();

  /// The ids of the reminders scheduled now.
  Future<Set<int>> ids();

  Future<void> schedule(DueReminder reminder);
  Future<void> cancel(int id);
}

/// Schedules exactly [due]: a reminder already scheduled stays as it is, one
/// no note has any more is cancelled, so processing the notes again never
/// doubles a notification.
Future<void> scheduleReminders(ReminderNotifier device, List<DueReminder> due) async {
  final scheduled = await device.ids();
  final wanted = {for (final reminder in due) reminder.id};
  for (final id in scheduled.difference(wanted)) {
    await device.cancel(id);
  }
  for (final reminder in due.where((r) => !scheduled.contains(r.id))) {
    await device.schedule(reminder);
  }
}

// coverage:ignore-start
/// The platform's notifications, through flutter_local_notifications. Thin
/// glue `flutter test` cannot load; everything around it is tested with a fake.
class PluginNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  late final Future<void> _ready = _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      // Asked for when the first reminder needs it, not at start.
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'Notelore',
        appUserModelId: 'io.github.mfozmen.notelore',
        guid: '21c33f16-810c-4a91-a6d3-613a5d8c3e7c',
      ),
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  MacOSFlutterLocalNotificationsPlugin? get _macos =>
      _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> isAllowed() async {
    await _ready;
    if (Platform.isAndroid) return await _android?.areNotificationsEnabled() ?? false;
    if (Platform.isMacOS) return (await _macos?.checkPermissions())?.isEnabled ?? false;
    return true; // Windows: the user turns toasts off in the system settings
  }

  @override
  Future<bool> ask() async {
    await _ready;
    if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? false;
    if (Platform.isMacOS) {
      return await _macos?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  @override
  Future<Set<int>> ids() async {
    await _ready;
    return {for (final request in await _plugin.pendingNotificationRequests()) request.id};
  }

  @override
  Future<void> schedule(DueReminder reminder) async {
    await _ready;
    // Exactly at its minute where the user allows exact alarms; otherwise
    // Android may deliver it a little later.
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.note,
      body: reminder.text,
      // The local minute as an instant: the timezone database is not needed.
      scheduledDate: tz.TZDateTime.from(reminder.at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription: 'Reminders from your notes, at their time',
          importance: Importance.high,
          priority: Priority.high,
        ),
        macOS: DarwinNotificationDetails(),
        windows: WindowsNotificationDetails(),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _ready;
    await _plugin.cancel(id: id);
  }
}

// coverage:ignore-end
