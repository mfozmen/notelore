/// The desktop's quick-add window (#800): a global shortcut turns the app's
/// window into a small floating one with a field (Enter sends, Esc closes) and
/// the mic orb. The message joins the chat; its answer is read there later.
///
/// One window, not a second one: the shortcut shrinks the main window and
/// [QuickHost.restore] gives it back as it was, so the chat, the session and the
/// app lock stay the ones the app already has. A locked or unset app comes to
/// the front as itself instead.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notelore_core/notelore_core.dart';

import 'chat.dart' show Orb;
import 'icons.dart';
import 'mark.dart';
import 'session.dart';
import 'strings.dart' show Strings;
import 'theme.dart';
import 'voice.dart';

/// The platform side: the global shortcut and the window's two shapes.
abstract interface class QuickHost {
  /// The shortcut's keys as the platform writes them: Ctrl, Alt, N; ⌥, ⌘, N.
  List<String> get keys;

  /// Registers the shortcut ([on]) or lets it go; false when another app holds it.
  Future<bool> listen({required bool on});

  /// The window small, floating above other apps, and focused.
  Future<void> compact();

  /// The window back as it was before [compact], minimized again if it was.
  Future<void> restore();

  /// The window as it is, brought to the front.
  Future<void> front();
}

/// What the shortcut does, and the quick window's state; it notifies when
/// [taken] changes.
class QuickWindow extends ChangeNotifier {
  QuickWindow(this.session, this.host) {
    session.addListener(_changed);
  }

  final Session session;
  final QuickHost host;

  /// The shortcut is on in Settings but another app holds it.
  var taken = false;
  bool? _listening;

  /// Registers the shortcut as Settings says; again whenever that changes.
  Future<void> start() => _listen();

  Future<void> _listen() async {
    final on = session.quickShortcut;
    _listening = on;
    final held = await host.listen(on: on);
    if (on != _listening) return; // a later toggle's own call decides
    final now = on && !held;
    if (now == taken) return;
    taken = now;
    notifyListeners();
  }

  /// The shortcut in words: Ctrl+Alt+N, ⌥⌘N.
  String get keysLabel => host.keys.join(host.keys.any((key) => key.length > 1) ? '+' : '');

  void _changed() {
    if (_listening != null && session.quickShortcut != _listening) unawaited(_listen());
    if (session.quickAddOpen && session.lock.locked) unawaited(close());
  }

  /// The shortcut: opens the quick window, or closes it when it is open.
  Future<void> pressed() async {
    if (session.quickAddOpen) return close();
    // Away long enough, the app locks now, before anything of it shows.
    session.lock.foregrounded();
    if (!session.ready || session.lock.locked) return host.front();
    session.showQuickAdd(open: true);
    await host.compact();
  }

  Future<void> close() async {
    session.showQuickAdd(open: false);
    await host.restore();
  }

  /// The platform gave the window back itself: a click went to another app.
  void closed() => session.showQuickAdd(open: false);

  /// Sends [text] into the chat's queue and gives the window back at once.
  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    await close();
    await session.send(text.trim());
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }
}

/// The last turn's write receipt, as one line: "Reminder added · Health".
String? lastReceipt(Session session) {
  final s = session.strings;
  final line = session.transcript.lastWhere(
    (line) => line.role == ChatRole.assistant,
    orElse: () => (role: ChatRole.user, text: '', cards: const []),
  );
  final receipt = line.cards.whereType<NoteReceipt>().firstOrNull;
  if (receipt == null) return null;
  return '${s.noteChange(receipt)} · ${receipt.title}';
}

/// The quick window's one screen: its title, the field and orb, the keys, and
/// the last receipt.
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen(this.window, {super.key});

  final QuickWindow window;

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final _text = TextEditingController();

  /// Talking instead of typing; the answer is read later, so nothing is spoken.
  late final _voice = VoiceMode(widget.window.session, voice: const _Silent())..addListener(_heard);

  /// What was said is on its way: the window goes, as after Enter.
  void _heard() {
    setState(() {});
    if (_voice.state == VoiceState.thinking) unawaited(widget.window.close());
  }

  void _talk() =>
      _voice.state == VoiceState.listening ? _voice.release() : unawaited(_voice.press());

  @override
  void dispose() {
    // Closed while listening: the mic stops, and nothing is sent.
    _voice
      ..removeListener(_heard)
      ..end()
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    final s = window.session.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final receipt = lastReceipt(window.session);
    final listening = _voice.state == VoiceState.listening;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): window.close},
      child: Scaffold(
        // Centred in the small window; it scrolls only if a mic error and the
        // receipt both show.
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const NoteloreMark(size: 18),
                    const SizedBox(width: Gap.s),
                    Expanded(child: Text(s.quickTitle, style: theme.textTheme.titleSmall)),
                    for (final key in window.host.keys) ...[
                      const SizedBox(width: Gap.xs),
                      _Key(key, style: muted),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.s),
                _field(s, colors, listening: listening),
                const SizedBox(height: Gap.s),
                Row(
                  children: [
                    Expanded(child: Text(s.quickKeys, style: muted)),
                    Text(s.quickToChat, style: muted),
                  ],
                ),
                if (_voice.problem case final problem?) ...[
                  const SizedBox(height: Gap.s),
                  Text(problem, style: muted?.copyWith(color: colors.error)),
                ],
                if (receipt != null) ...[
                  const SizedBox(height: Gap.s),
                  _receipt(receipt, s, colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The chat composer's field: its edge takes the accent while focused.
  Widget _field(Strings s, ColorScheme colors, {required bool listening}) {
    final window = widget.window;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(Gap.xs),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Focus.of(context).hasFocus
                ? Border.all(color: colors.primary, width: 2)
                : Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('quick-message'),
                  controller: _text,
                  autofocus: true,
                  textInputAction: TextInputAction.send,
                  onSubmitted: window.send,
                  decoration: InputDecoration(
                    hintText: listening ? s.listening : s.quickAdd,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: Gap.s),
                  ),
                ),
              ),
              // Send once something is typed, as in the chat; the mic before.
              ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, typed, _) => Orb(
                  typed.text.trim().isNotEmpty
                      ? IconButton(
                          tooltip: s.send,
                          icon: const Icon(AppIcons.send, color: Colors.white),
                          onPressed: () => window.send(_text.text),
                        )
                      : IconButton(
                          tooltip: listening ? s.stopTalking : s.talk,
                          icon: Icon(listening ? AppIcons.send : AppIcons.mic, color: Colors.white),
                          onPressed: _talk,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The last answer's write receipt, its value weighing more than the label.
  Widget _receipt(String receipt, Strings s, ColorScheme colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
    decoration: BoxDecoration(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(AppIcons.check, size: 16, color: colors.primary),
        const SizedBox(width: Gap.s),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${s.quickLast}: ',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                TextSpan(text: receipt),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// One key of the shortcut, drawn as a key.
class _Key extends StatelessWidget {
  const _Key(this.label, {this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: style),
    );
  }
}

class _Silent implements Voice {
  const _Silent();

  @override
  Future<void> speak(String text, String language) async {}

  @override
  Future<void> stop() async {}
}
