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

import 'mark.dart';
import 'session.dart';
import 'theme.dart';
import 'voice.dart';

/// The platform side: the global shortcut and the window's two shapes.
abstract interface class QuickHost {
  /// The shortcut as the platform writes it: Ctrl+Alt+N, ⌥⌘N.
  String get keys;

  /// Registers the shortcut ([on]) or lets it go; false when another app holds it.
  Future<bool> listen({required bool on});

  /// The window small, floating above other apps, and focused.
  Future<void> compact();

  /// The window back as it was before [compact], minimized again if it was.
  Future<void> restore();

  /// The window as it is, brought to the front.
  Future<void> front();
}

/// What the shortcut does, and the quick window's state.
class QuickWindow {
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
    taken = on && !held;
  }

  void _changed() {
    if (_listening != null && session.quickShortcut != _listening) unawaited(_listen());
    if (session.quickAddOpen && session.lock.locked) unawaited(close());
  }

  /// The shortcut: opens the quick window, or closes it when it is open.
  Future<void> pressed() async {
    if (session.quickAddOpen) return close();
    if (!session.ready || session.lock.locked) return host.front();
    session.showQuickAdd(open: true);
    await host.compact();
  }

  Future<void> close() async {
    session.showQuickAdd(open: false);
    await host.restore();
  }

  /// Sends [text] into the chat's queue and gives the window back at once.
  Future<void> send(String text) async {
    if (text.trim().isEmpty) return;
    await close();
    await session.send(text.trim());
  }

  void dispose() => session.removeListener(_changed);
}

/// The last turn's write receipt, as one line: "Last: Reminder added · Health".
String? lastReceipt(Session session) {
  final s = session.strings;
  final line = session.transcript.lastWhere(
    (line) => line.role == ChatRole.assistant,
    orElse: () => (role: ChatRole.user, text: '', cards: const []),
  );
  final receipt = line.cards.whereType<NoteReceipt>().firstOrNull;
  if (receipt == null) return null;
  return '${s.quickLast}: ${s.noteChange(receipt)} · ${receipt.title}';
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
    _voice
      ..removeListener(_heard)
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
        body: Padding(
          padding: const EdgeInsets.all(Gap.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const NoteloreMark(size: 18),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(s.quickTitle, style: theme.textTheme.titleSmall)),
                  Text(window.host.keys, style: muted),
                ],
              ),
              const SizedBox(height: Gap.s),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(26),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: Gap.m),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Gap.xs),
                      child: IconButton.filled(
                        tooltip: listening ? s.stopTalking : s.talk,
                        isSelected: listening,
                        icon: const Icon(Icons.mic),
                        selectedIcon: const Icon(Icons.arrow_upward),
                        onPressed: _talk,
                      ),
                    ),
                  ],
                ),
              ),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check, size: 16, color: colors.primary),
                      const SizedBox(width: Gap.s),
                      Expanded(child: Text(receipt, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
