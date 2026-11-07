/// Android's home-screen widget (#799): the platform side of [QuickDelivery],
/// a method channel to MainActivity.kt that `flutter test` cannot reach.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'quick_widget.dart';
import 'session.dart';

// coverage:ignore-start
/// Checks for a tap now and on every return to the front, and draws the widget
/// at start, after each turn and sync, and when the app goes to the background.
void listenForQuickWidget(Session session) {
  const channel = MethodChannel('io.github.mfozmen.notelore/widget');
  final delivery = QuickDelivery(
    session,
    () => channel.invokeMethod<String>('take'),
    draw: (data) => unawaited(channel.invokeMethod<void>('draw', jsonEncode(data))),
  );
  AppLifecycleListener(onResume: delivery.check, onHide: delivery.redraw);
  unawaited(delivery.check());
  delivery.redraw();
}
// coverage:ignore-end
