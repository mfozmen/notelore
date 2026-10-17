import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'voice.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {super.key});

  final Session session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _message = TextEditingController();
  final _modelMenu = GlobalKey<PopupMenuButtonState<String>>();

  /// Push to talk, beside the message box.
  late final _voice = VoiceMode(widget.session, voice: widget.session.voice);

  @override
  void dispose() {
    _voice
      ..end()
      ..dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text;
    _message.clear();
    await widget.session.send(text);
  }

  /// When the talk button last went down (the pointer's own clock).
  var _down = Duration.zero;

  /// The last press was a plain click: show how talking works.
  var _holdHint = false;

  /// A screen reader's tap: starts listening, or sends what was said.
  void _toggleTalk() =>
      _voice.state == VoiceState.listening ? _voice.release() : unawaited(_hold());

  /// Space or Enter held on the focused talk button: push to talk by keyboard.
  KeyEventResult _talkKey(KeyEvent event, {required bool busy}) {
    if (event.logicalKey != LogicalKeyboardKey.space &&
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && !busy) unawaited(_hold());
    if (event is KeyUpEvent) _voice.release();
    return KeyEventResult.handled; // and its repeats, so the button's own press does not fire
  }

  /// The talk button went down: one push-to-talk turn.
  Future<void> _hold() async {
    final messenger = ScaffoldMessenger.of(context);
    await _voice.press();
    if (_voice.problem case final problem?) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    final lines = session.transcript.reversed.toList(); // newest at the bottom
    // One tap sends the last message again; not while a turn runs.
    final resendable = session.busy ? -1 : lines.indexWhere((l) => l.role == ChatRole.user);
    // On a wide window the conversation is a readable column, like a page.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.chat),
        child: _conversation(context, session, s, lines, resendable),
      ),
    );
  }

  Widget _conversation(
    BuildContext context,
    Session session,
    Strings s,
    List<ChatLine> lines,
    int resendable,
  ) {
    return Column(
      children: [
        Expanded(
          child: lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.l),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 56,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: Gap.m),
                        Text(
                          s.askSomething,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
                  itemCount: lines.length + (session.busy ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (!session.busy) {
                      final bubble = _Bubble(lines[index]);
                      return index == resendable ? _Resendable(bubble, s, session.resend) : bubble;
                    }
                    return index == 0 ? _Thinking(s) : _Bubble(lines[index - 1]);
                  },
                ),
        ),
        if (session.modelGone)
          MaterialBanner(
            leading: const Icon(Icons.warning_amber),
            content: Text(s.modelGone(s.providerName(session.spec!), session.model!)),
            actions: [
              TextButton(
                onPressed: () => _modelMenu.currentState!.showButtonMenu(),
                child: Text(s.changeModel),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, 0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Gap.s,
            children: [
              // The models the connected provider listed; switching keeps the conversation.
              PopupMenuButton<String>(
                key: _modelMenu,
                tooltip: s.changeTheModel,
                enabled: !session.busy,
                initialValue: session.model,
                onSelected: session.setModel,
                itemBuilder: (_) => [
                  for (final m in {...session.models, ?session.model})
                    PopupMenuItem(value: m, child: Text(m)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                  label: Text(session.model ?? ''),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (session.spec?.name == 'chatgpt') ...[
                // OpenAI asks plan-usage apps to show this near the composer.
                Text(s.usingChatGptPlan),
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse(chatGptUsageUrl), mode: LaunchMode.externalApplication),
                  child: Text(s.manageUsage),
                ),
              ],
            ],
          ),
        ),
        ListenableBuilder(
          listenable: _voice,
          builder: (context, _) => Column(
            children: [
              if (_voice.state == VoiceState.speaking)
                _status(context, Icons.volume_up, Text(s.speaking, key: const Key('voice-state')))
              // Above the button, not over it: a plain click learns to hold.
              else if (_holdHint)
                _status(context, Icons.touch_app_outlined, Text(s.holdHint)),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.s, Gap.s),
                // One button, like a messenger's: Send with text, the microphone without.
                child: ValueListenableBuilder(
                  valueListenable: _message,
                  builder: (context, typed, _) => Row(
                    children: [
                      Expanded(
                        // While recording, the recording takes the field's place;
                        // the field's text stays in its controller.
                        child: _voice.state == VoiceState.listening
                            ? _Recording(s.listening)
                            : TextField(
                                key: const Key('message'),
                                controller: _message,
                                // Open while the model works: what is written meanwhile joins its turn.
                                minLines: 1,
                                maxLines: 5,
                                textInputAction: TextInputAction.send,
                                // Typing quiets an answer read aloud.
                                onChanged: (text) {
                                  if (_voice.state == VoiceState.speaking && text.isNotEmpty) {
                                    _voice.hush();
                                  }
                                },
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(hintText: s.message),
                              ),
                      ),
                      if (_voice.state == VoiceState.speaking)
                        IconButton(
                          tooltip: s.stopReading,
                          icon: const Icon(Icons.volume_off_outlined),
                          onPressed: _voice.end,
                        ),
                      if (session.busy)
                        IconButton(
                          tooltip: s.stop,
                          icon: const Icon(Icons.stop),
                          onPressed: session.stop,
                        ),
                      if (typed.text.trim().isNotEmpty)
                        IconButton.filled(
                          tooltip: s.send,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _send,
                        )
                      else
                        // Push to talk: held, it listens; let go, what was said is
                        // sent. The press stays with this Listener wherever the
                        // finger goes, even when the keyboard closing moves it (#212).
                        Listener(
                          onPointerDown: session.busy
                              ? null
                              : (down) {
                                  _down = down.timeStamp;
                                  setState(() => _holdHint = false);
                                  _hold();
                                },
                          onPointerUp: (up) {
                            _voice.release();
                            // A plain click records nothing: say how it works.
                            if (up.timeStamp - _down < const Duration(milliseconds: 300)) {
                              setState(() => _holdHint = true);
                            }
                          },
                          onPointerCancel: (_) => _voice.release(),
                          // A screen reader cannot hold: one tap starts, the next sends.
                          child: Semantics(
                            label: s.talk,
                            button: true,
                            excludeSemantics: true,
                            onTap: session.busy ? null : _toggleTalk,
                            // The keyboard holds Space or Enter instead.
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: (_, event) => _talkKey(event, busy: session.busy),
                              child: IconButton.filled(
                                tooltip: s.talk,
                                icon: Icon(
                                  _voice.state == VoiceState.listening ? Icons.mic : Icons.mic_none,
                                ),
                                onPressed: session.busy ? null : () {},
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// In the message box's place while recording: it listens.
class _Recording extends StatelessWidget {
  const _Recording(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: Gap.m),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: colors.onPrimaryContainer),
          const SizedBox(width: Gap.s),
          Flexible(
            child: Text(
              label,
              key: const Key('voice-state'),
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line above the message box: what voice is doing, or how to use it.
Widget _status(BuildContext context, IconData icon, Widget text) => Padding(
  padding: const EdgeInsets.only(top: Gap.s),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: Gap.s),
      Flexible(child: text), // wraps on a narrow phone
    ],
  ),
);

/// The assistant's turn while it runs: a playful line that changes every
/// [_rotation] (its steps, a search or a write, pass too fast to read).
class _Thinking extends StatefulWidget {
  const _Thinking(this.strings);

  /// How long each waiting line stays before the next one.
  static const _rotation = Duration(seconds: 4);

  final Strings strings;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  var _seconds = 0;

  /// Where in the waiting lines this turn starts: a different one each time.
  final _first = Random().nextInt(1 << 16);
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  String get _waiting {
    final lines = widget.strings.waitingLines;
    return lines[(_first + _seconds ~/ _Thinking._rotation.inSeconds) % lines.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Gap.xs),
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: _bubbleRadius(mine: false),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Flexible(child: Text(_waiting)),
          ],
        ),
      ),
    );
  }
}

/// The last message, with a button under it that sends it again.
class _Resendable extends StatelessWidget {
  const _Resendable(this.bubble, this.strings, this.resend);

  final Widget bubble;
  final Strings strings;
  final VoidCallback resend;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      bubble,
      IconButton(
        tooltip: strings.resend,
        icon: const Icon(Icons.replay, size: 18),
        visualDensity: VisualDensity.compact,
        onPressed: resend,
      ),
    ],
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.line);

  final ChatLine line;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mine = line.role == ChatRole.user;
    final (background, foreground) = switch (line.role) {
      ChatRole.user => (colors.primary, colors.onPrimary),
      ChatRole.assistant => (colors.surfaceContainerHigh, colors.onSurface),
      ChatRole.error => (colors.errorContainer, colors.onErrorContainer),
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Gap.xs),
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: 10),
        // Readable line length on wide windows.
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: background,
          borderRadius: _bubbleRadius(mine: mine),
        ),
        child: SelectableText(line.text, style: TextStyle(color: foreground, height: 1.4)),
      ),
    );
  }
}

/// Rounded, with a smaller corner on the speaker's side, like a speech bubble.
BorderRadius _bubbleRadius({required bool mine}) => BorderRadius.only(
  topLeft: const Radius.circular(18),
  topRight: const Radius.circular(18),
  bottomLeft: Radius.circular(mine ? 18 : 4),
  bottomRight: Radius.circular(mine ? 4 : 18),
);
