/// Android's home-screen widget (#799): the mark and sync state, a field and
/// the mic orb that open the chat composer, and the two notes changed last.
///
/// Like a share, a tap is asked for (at start and each time the app comes to
/// the front), so it reaches the session only once the app is set up and
/// unlocked. Any app can start Notelore with such a link, so only the widget's
/// own links count, and none of them carries text for the assistant.
library;

import 'package:notelore_core/notelore_core.dart';

import 'session.dart';

/// What a tap on the widget asks for: the composer, typing or talking, or a note.
class QuickOpen {
  const QuickOpen._({this.voice = false}) : kind = null, slug = null;
  const QuickOpen.note(String this.kind, String this.slug) : voice = false;

  static const write = QuickOpen._();
  static const talk = QuickOpen._(voice: true);

  /// Talking instead of typing: voice mode starts.
  final bool voice;
  final String? kind;
  final String? slug;

  static const _scheme = 'notelore-widget';

  /// The link the widget sends for [note].
  static String link(NoteInfo note) => '$_scheme://note/${note.kind}/${note.slug}';

  /// What [link] asks for, or null when it is not one of the widget's links.
  static QuickOpen? parse(String? link) {
    final uri = Uri.tryParse(link ?? '');
    if (uri == null || uri.scheme != _scheme) return null;
    return switch ((uri.host, uri.pathSegments)) {
      ('write', []) => write,
      ('talk', []) => talk,
      ('note', [final kind, final slug])
          when kinds.containsKey(kind) && RegExp(r'^[a-z0-9-]+$').hasMatch(slug) =>
        QuickOpen.note(kind, slug),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is QuickOpen && other.voice == voice && other.kind == kind && other.slug == slug;

  @override
  int get hashCode => Object.hash(voice, kind, slug);
}

/// What the widget shows, in the app's language: the field's hint, the sync
/// state (empty without Drive) and the two notes changed last, none while the
/// app lock is on: the home screen is not behind it.
Map<String, Object> widgetData(Session session, DateTime today) {
  final s = session.strings;
  final sync = switch (session) {
    Session(driveConnected: false) => '',
    Session(syncing: true) => s.syncingNow,
    Session(syncFailed: true) => s.syncFailed,
    Session(lastSynced: null) => s.syncNever,
    _ => s.syncedShort,
  };
  return {
    'hint': s.quickAdd,
    'talk': s.talk,
    'sync': sync,
    'notes': [
      for (final note in session.lock.enabled ? const <NoteInfo>[] : session.listNotes().take(2))
        {
          'title': note.title,
          'date': switch (note.updated) {
            final updated? => s.shortDate(updated, today),
            null => '',
          },
          'open': QuickOpen.link(note),
        },
    ],
  };
}

/// Hands what [take] returns to the session once it is set up and unlocked,
/// and gives [draw] what the widget shows whenever a turn or a sync ends, or
/// the app lock is turned on or off.
class QuickDelivery {
  QuickDelivery(this.session, this.take, {this.draw}) {
    session.addListener(_changed);
  }

  final Session session;

  /// The link of the last tap on the widget since the last call, or null.
  final Future<String?> Function() take;

  final void Function(Map<String, Object> data)? draw;

  QuickOpen? _waiting;
  var _working = false;
  late var _locking = session.lock.enabled;

  void _changed() {
    _deliver();
    final working = session.busy || session.syncing;
    if ((_working && !working) || _locking != session.lock.enabled) redraw();
    _working = working;
    _locking = session.lock.enabled;
  }

  /// Draws the widget now: at start, and when the app goes to the background.
  void redraw() => draw?.call(widgetData(session, session.clock().toLocal()));

  /// Asks for a tap; call at start and whenever the app comes to the front.
  Future<void> check() async {
    if (QuickOpen.parse(await take()) case final open?) _waiting = open;
    _deliver();
  }

  void _deliver() {
    final open = _waiting;
    if (open == null || !session.ready || session.lock.locked) return;
    _waiting = null;
    session.openQuick(open);
  }

  void dispose() => session.removeListener(_changed);
}
