import 'dart:async';

import 'package:flutter/material.dart';
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

  /// Voice mode; the chat always opens in text mode.
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
    if (_voice.on) return _voice.type(text); // sent by the voice loop, answered aloud
    await widget.session.send(text);
  }

  Future<void> _talk() async {
    final messenger = ScaffoldMessenger.of(context);
    await _voice.start();
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
                  itemBuilder: (context, index) => session.busy
                      ? (index == 0
                            ? _Thinking(s.core(session.step ?? 'Thinking'), s)
                            : _Bubble(lines[index - 1]))
                      : _Bubble(lines[index]),
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
              if (_voice.state case VoiceState.listening || VoiceState.speaking)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.s),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _voice.state == VoiceState.listening ? Icons.mic : Icons.volume_up,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: Gap.s),
                      Text(
                        _voice.state == VoiceState.listening ? s.listening : s.speaking,
                        key: const Key('voice-state'),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.s, Gap.s),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('message'),
                        controller: _message,
                        // Open while the model works: what is written meanwhile joins its turn.
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        // Typing in voice mode quiets the voice; the text is still sent.
                        onChanged: (text) {
                          if (_voice.on && text.isNotEmpty) _voice.hush();
                        },
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(hintText: s.message),
                      ),
                    ),
                    if (_voice.on)
                      IconButton.filled(
                        tooltip: s.backToTyping,
                        icon: const Icon(Icons.graphic_eq),
                        onPressed: _voice.end,
                      )
                    else
                      IconButton(
                        tooltip: s.talk,
                        icon: const Icon(Icons.graphic_eq),
                        onPressed: session.busy ? null : _talk,
                      ),
                    if (session.busy)
                      IconButton(
                        tooltip: s.stop,
                        icon: const Icon(Icons.stop),
                        onPressed: session.stop,
                      ),
                    IconButton.filled(
                      tooltip: s.send,
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: _send,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The assistant's turn while it runs: what it is doing and for how long.
class _Thinking extends StatefulWidget {
  const _Thinking(this.step, this.strings);

  /// What it is doing, in the app's language.
  final String step;
  final Strings strings;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  var _seconds = 0;
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
            Text(widget.strings.thinking(widget.step, _seconds)),
          ],
        ),
      ),
    );
  }
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
