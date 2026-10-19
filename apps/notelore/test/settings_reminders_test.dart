import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart' show SignInFailed;

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  /// Settings, scrolled to the Reminders card.
  Future<void> openReminders(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reminders'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings: reminders come as notifications on this device (#431)', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openReminders(tester);
    expect(find.text("Notelore notifies you on this device at a reminder's time."), findsOneWidget);
    expect(find.text('Allow notifications'), findsNothing);
  });

  testWidgets('settings: notifications off says so, and Allow asks for them', (tester) async {
    phone(tester);
    final harness = Harness()..reminders.allowed = false;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openReminders(tester);
    expect(
      find.text(
        "Notifications are off for Notelore: reminders stay in your notes, but you won't be notified.",
      ),
      findsOneWidget,
    );
    harness.reminders.grant = true;
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(harness.reminders.asked, 1);
    expect(find.text("Notelore notifies you on this device at a reminder's time."), findsOneWidget);
  });

  testWidgets('settings: a refused Allow says where to turn them on; back, the card knows', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..reminders.allowed = false;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openReminders(tester);
    // Asked twice already: the system shows nothing any more.
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Turn on notifications for Notelore in the system settings.'), findsOneWidget);
    // Turned on there, then back in the app (no Drive to sync): the card follows.
    harness.reminders.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text("Notelore notifies you on this device at a reminder's time."), findsOneWidget);
  });

  testWidgets('settings: Add to Google Calendar, then Google reminds on every device (#432)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..reminders.allowed = false;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openReminders(tester);
    expect(find.text('Allow notifications'), findsOneWidget);
    await tester.tap(find.text('Add to Google Calendar'));
    await tester.pumpAndSettle();
    expect(harness.calendarAuth.granted, isTrue);
    expect(find.textContaining('in its own "Notelore" calendar'), findsOneWidget);
    // Google reminds: this device's permission is beside the point now.
    expect(find.text('Allow notifications'), findsNothing);
  });

  testWidgets('settings: a refused calendar sign-in says why, and stays off', (tester) async {
    phone(tester);
    final harness = Harness()..calendarAuth.failSignIn = const SignInFailed('access_denied');
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openReminders(tester);
    await tester.tap(find.text('Add to Google Calendar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('access_denied'), findsOneWidget);
    expect(find.text("Notelore notifies you on this device at a reminder's time."), findsOneWidget);
  });

  testWidgets('settings: a device that cannot notify offers nothing of its own notifications', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..reminders.fail = Exception('no notifications here');
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Allow notifications'), findsNothing);
    expect(find.text("Notelore notifies you on this device at a reminder's time."), findsNothing);
  });
}
