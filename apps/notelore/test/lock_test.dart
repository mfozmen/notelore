import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/lock_state.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openLock(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('App lock'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  Future<void> restart(WidgetTester tester, Harness harness) async {
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness);
  }

  Finder dot(int number) => find.bySemanticsLabel('Dot $number');

  /// Taps the dots in turn, then Done: the way without dragging.
  Future<void> tapPattern(WidgetTester tester, List<int> dots) async {
    for (final number in dots) {
      await tester.tap(dot(number));
      await tester.pump();
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  /// Draws through the dots with one finger.
  Future<void> drawPattern(WidgetTester tester, List<int> dots) async {
    final gesture = await tester.startGesture(tester.getCenter(dot(dots.first)));
    for (final number in dots.skip(1)) {
      await gesture.moveTo(tester.getCenter(dot(number)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('lock: the device lock is recommended; it opens Notelore by itself (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openLock(tester);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.text('How should Notelore lock?'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    // Called off in the device's prompt: still off, and it says so.
    harness.deviceAuth.answers.add(false);
    await tester.tap(find.text("Your device's lock"));
    await tester.pumpAndSettle();
    expect(find.text('The app lock is still off.'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Your device's lock"));
    await tester.pumpAndSettle();
    expect(find.text("On: your device's lock opens Notelore."), findsOneWidget);

    // The next start: the device's prompt comes up at once; called off, the
    // button brings it back.
    harness.deviceAuth.answers.add(false);
    await restart(tester, harness);
    expect(find.text('Notelore is locked'), findsOneWidget);
    expect(find.byKey(const Key('message')), findsNothing);
    await tester.tap(find.byKey(const Key('unlock-device')));
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsNothing);
    expect(harness.deviceAuth.reasons, [
      'Turn on the app lock', // called off
      'Turn on the app lock',
      'Unlock Notelore',
      'Unlock Notelore',
    ]);

    // Off, when the device says yes.
    await openLock(tester);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.textContaining('opens without asking'), findsOneWidget);
    expect(harness.deviceAuth.reasons.last, 'Turn off the app lock');
  });

  testWidgets('lock: a device without a lock of its own says so and offers the others (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..deviceAuth.hasLock = false;
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openLock(tester);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no screen lock set up'), findsOneWidget);
    expect(find.text('Recommended'), findsNothing);
    expect(tester.widget<ListTile>(find.byKey(const Key('lock-device'))).enabled, isFalse);
    expect(tester.widget<ListTile>(find.byKey(const Key('lock-pattern'))).enabled, isTrue);
  });

  test('the PINs and patterns people try first are too easy (#412)', () {
    for (final pin in ['0000', '1111', '1234', '4321', '9876', '0123', '56789']) {
      expect(weakPin(pin), isTrue, reason: pin);
    }
    for (final pin in ['2468', '1357', '1235', '0012', '9087']) {
      expect(weakPin(pin), isFalse, reason: pin);
    }
    // An L, a Z, a U, a C, a 7 and the ring, either way round.
    for (final pattern in [
      '0-3-6-7-8',
      '8-7-6-3-0',
      '0-1-2-4-6-7-8',
      '0-3-6-7-8-5-2',
      '2-1-0-3-6-7-8',
      '0-1-2-5-8',
      '0-1-2-5-8-7-6-3',
    ]) {
      expect(weakPattern(pattern), isTrue, reason: pattern);
    }
    for (final pattern in ['0-4-8-5', '1-5-9-6', '3-0-4-8-7']) {
      expect(weakPattern(pattern), isFalse, reason: pattern);
    }
  });

  testWidgets('lock: a PIN or pattern that is too easy is refused, and why (#412)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openLock(tester);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A PIN for Notelore'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lock-new')), '1234');
    await tester.enterText(find.byKey(const Key('lock-repeat')), '1234');
    await tester.pump();
    expect(find.textContaining('Too easy to guess'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A pattern for Notelore'));
    await tester.pumpAndSettle();
    await tapPattern(tester, [1, 4, 7, 8, 9]); // an L
    expect(find.textContaining('one of the first people try'), findsOneWidget);
    expect(find.text('Draw the same pattern again.'), findsNothing);
    expect(session.lock.enabled, isFalse);
  });

  testWidgets('lock: a pattern, set by tapping the dots, opened by drawing them (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openLock(tester);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A pattern for Notelore'));
    await tester.pumpAndSettle();
    expect(find.text('Draw a pattern through at least 4 dots.'), findsOneWidget);
    // Three dots are too few: Done waits for a fourth.
    for (final number in [1, 2, 3]) {
      await tester.tap(dot(number));
      await tester.pump();
    }
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Done')).onPressed,
      isNull,
    );
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tapPattern(tester, [1, 5, 9, 6]);
    expect(find.text('Draw the same pattern again.'), findsOneWidget);
    await tapPattern(tester, [1, 5, 9, 8]); // not the same: start over
    expect(find.text('That was a different pattern. Start again.'), findsOneWidget);
    await tapPattern(tester, [1, 5, 9, 6]);
    await tapPattern(tester, [1, 5, 9, 6]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('On: a pattern opens Notelore.'), findsOneWidget);

    await restart(tester, harness);
    expect(find.text('Notelore is locked'), findsOneWidget);
    await drawPattern(tester, [1, 2, 3, 6]);
    expect(find.text("That's not it. Try again."), findsOneWidget);
    await drawPattern(tester, [1, 2]); // too short: nothing is tried
    expect(find.text('Notelore is locked'), findsOneWidget);
    await drawPattern(tester, [1, 5, 9, 6]);
    expect(find.text('Notelore is locked'), findsNothing);

    // Off with the pattern; a wrong one keeps it.
    await openLock(tester);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    await tapPattern(tester, [2, 5, 8, 9]);
    expect(find.text("That's not it. Try again."), findsOneWidget);
    await tapPattern(tester, [1, 5, 9, 6]);
    expect(find.textContaining('opens without asking'), findsOneWidget);
  });

  testWidgets('lock: an older password lock keeps working and offers a switch (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final first = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await first.lock.set('open sesame');
    await const FlutterSecureStorage().delete(key: 'notelore.lock.kind'); // as before #295
    await restart(tester, harness);
    expect(find.text('PIN or password'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('unlock')), 'open sesame');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Notelore is locked'), findsNothing);
    await openLock(tester);
    expect(find.textContaining('You can switch to your device'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.text('PIN or password'), findsOneWidget); // the old field, any text
    expect(harness.deviceAuth.reasons, isEmpty);
  });

  testWidgets('lock: turning a pattern off waits after wrong tries, like opening (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final first = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await first.lock.set('0-4-8-5', kind: LockKind.pattern);
    for (var i = 0; i < 5; i++) {
      expect(await first.lock.remove('wrong'), isFalse);
    }
    await tester.pumpAndSettle();
    await openLock(tester);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many tries'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  /// A small phone at double text size: the lock screen scrolls.
  void small(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets(
    'lock: on a screen that scrolls, drawing still opens it; too few dots say so (#295)',
    (tester) async {
      phone(tester);
      final harness = Harness();
      final first = await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      await first.lock.set('0-4-8-5', kind: LockKind.pattern);
      small(tester);
      await restart(tester, harness);
      expect(find.text('Draw your pattern.'), findsOneWidget);
      await drawPattern(tester, [1, 2]);
      expect(find.text('Draw a pattern through at least 4 dots.'), findsOneWidget);
      await drawPattern(tester, [1, 5, 9, 6]);
      expect(find.text('Notelore is locked'), findsNothing);
    },
  );

  testWidgets('lock: the chooser and the pattern dialog fit at double text size (#295)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    small(tester);
    await openLock(tester);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Recommended'), findsOneWidget);
    await tester.ensureVisible(find.text('A pattern for Notelore')); // the chooser scrolls
    await tester.pumpAndSettle();
    await tester.tap(find.text('A pattern for Notelore'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lock: a device prompt called off, or a device lock gone, says what to do (#295)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final first = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await first.lock.useDevice('on');
    harness.deviceAuth.answers.add(false);
    await restart(tester, harness);
    expect(find.text('Not unlocked. Tap Unlock to try again.'), findsOneWidget);
    // The phone's own screen lock was removed since: no prompt can open it.
    harness.deviceAuth.hasLock = false;
    harness.deviceAuth.answers.add(false);
    await restart(tester, harness);
    expect(find.textContaining('no screen lock any more'), findsOneWidget);
  });
}
