/// Android's "Share → Notelore" (#211): the platform side of [ShareDelivery],
/// a method channel to MainActivity.kt that `flutter test` cannot reach.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'session.dart';
import 'share_in.dart';

// coverage:ignore-start
/// Checks for a share now and on every return to the front, for as long as
/// the app runs.
void listenForShares(Session session) {
  const channel = MethodChannel('io.github.mfozmen.notelore/share');
  final delivery = ShareDelivery(
    session,
    () => channel.invokeMethod<Map<Object?, Object?>>('take'),
  );
  AppLifecycleListener(onResume: delivery.check);
  unawaited(delivery.check());
}
// coverage:ignore-end
