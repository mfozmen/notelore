/// The platform's notifications for reminders (#431), through
/// flutter_local_notifications: native glue `flutter test` cannot load, kept
/// thin; the scheduling around it is tested with a fake.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_notifier.dart';
import 'strings.dart';

// coverage:ignore-start
/// This device's notifications where the app has them: Android, Windows, macOS.
/// None under `flutter test`: the Windows plugin holds files a test must delete.
ReminderNotifier? platformNotifier() =>
    (Platform.isAndroid || Platform.isWindows || Platform.isMacOS) &&
        !Platform.environment.containsKey('FLUTTER_TEST')
    ? PluginNotifier()
    : null;

/// A notification's Done or Snooze 1 hour on Android while the app is not
/// running (#801): the plugin starts this in an isolate of its own.
@pragma('vm:entry-point')
Future<void> reminderActionInBackground(NotificationResponse response) =>
    actOnReminder(PluginNotifier(), response.actionId, response.payload, now: DateTime.now());

/// The platform's notifications, through flutter_local_notifications. Thin
/// glue `flutter test` cannot load; everything around it is tested with a fake.
class PluginNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  late final Future<void> _ready = _setUp();

  Future<void> _setUp() async {
    // macOS fixes its buttons' words at start: the system's language.
    final words = stringsFor(AppLanguage.system, PlatformDispatcher.instance.locale.languageCode);
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Asked for when the first reminder needs it, not at start.
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(doneAction, words.reminderDone),
                DarwinNotificationAction.plain(snoozeAction, words.reminderSnooze),
              ],
            ),
          ],
        ),
        windows: const WindowsInitializationSettings(
          appName: 'Notelore',
          appUserModelId: 'io.github.mfozmen.notelore',
          guid: '21c33f16-810c-4a91-a6d3-613a5d8c3e7c',
        ),
      ),
      onDidReceiveNotificationResponse: _respond,
      onDidReceiveBackgroundNotificationResponse: reminderActionInBackground,
    );
    // A desktop app a button started: its action, once set up.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.notificationResponse case final response? when launch!.didNotificationLaunchApp) {
      _respond(response);
    }
  }

  static const _category = 'reminder';

  void _respond(NotificationResponse response) =>
      unawaited(actOnReminder(this, response.actionId, response.payload, now: DateTime.now()));

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
  Future<void> schedule(DueReminder reminder, ReminderActions actions) async {
    await _ready;
    final payload = reminderPayload(reminder, actions);
    // Exactly at its minute where the user allows exact alarms; otherwise
    // Android may deliver it a little later.
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.note,
      body: reminder.text,
      // As a UTC instant, so no timezone database is shipped.
      scheduledDate: tz.TZDateTime.from(reminder.at.toUtc(), tz.UTC),
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          channelDescription: 'Reminders from your notes, at their time',
          importance: Importance.high,
          priority: Priority.high,
          // A lock screen set to hide sensitive content hides it (#431).
          visibility: NotificationVisibility.private,
          // Handled in the background, without opening the app or its lock.
          actions: [
            AndroidNotificationAction(doneAction, actions.done),
            AndroidNotificationAction(snoozeAction, actions.snooze),
          ],
        ),
        macOS: const DarwinNotificationDetails(categoryIdentifier: _category),
        windows: WindowsNotificationDetails(
          actions: [
            WindowsAction(content: actions.done, arguments: actionArguments(payload, doneAction)),
            WindowsAction(
              content: actions.snooze,
              arguments: actionArguments(payload, snoozeAction),
            ),
          ],
        ),
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
