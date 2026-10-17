/// What another app shares to Notelore (#211): Android's "Share → Notelore"
/// with a link or some text reaches the chat as a message, and the assistant
/// files it. The desktop has no share target; a link pasted into the chat
/// works the same.
///
/// Notelore asks for what was shared (at start and each time it comes to the
/// front) instead of being told, so the app lock has already been checked:
/// a share is sent only once the app is set up and unlocked, and waits until
/// then.
library;

import 'dart:async';

import 'session.dart';

/// One message from a share: its subject (a page's title, say) when the text
/// does not hold it already, then the text; null when nothing came.
String? sharedMessage(Map<Object?, Object?>? shared) {
  final text = '${shared?['text'] ?? ''}'.trim();
  final subject = '${shared?['subject'] ?? ''}'.trim();
  if (text.isEmpty) return subject.isEmpty ? null : subject;
  if (subject.isEmpty || text.contains(subject)) return text;
  return '$subject\n$text';
}

/// Hands what [take] returns to [session] as chat messages, as soon as the
/// session is ready and not locked.
class ShareDelivery {
  ShareDelivery(this.session, this.take) {
    session.addListener(_deliver);
  }

  final Session session;

  /// What was shared since the last call ({text, subject}), or null.
  final Future<Map<Object?, Object?>?> Function() take;

  final _waiting = <String>[];

  /// Asks for a share; call at start and whenever the app comes to the front.
  Future<void> check() async {
    if (sharedMessage(await take()) case final message?) _waiting.add(message);
    _deliver();
  }

  void _deliver() {
    if (!session.ready || session.lock.locked) return;
    while (_waiting.isNotEmpty) {
      unawaited(session.send(_waiting.removeAt(0)));
    }
  }

  void dispose() => session.removeListener(_deliver);
}
