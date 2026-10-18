/// The platform's notifications for reminders (#431), through
/// flutter_local_notifications: native glue `flutter test` cannot load, kept
/// thin; the scheduling around it is tested with a fake.
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_notifier.dart';

// coverage:ignore-start
/// This device's notifications where the app has them: Android, Windows, macOS.
ReminderNotifier? platformNotifier() =>
    Platform.isAndroid || Platform.isWindows || Platform.isMacOS ? PluginNotifier() : null;

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
