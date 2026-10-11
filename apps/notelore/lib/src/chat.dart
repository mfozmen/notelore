import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
import 'strings.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {super.key});

  final Session session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _message = TextEditingController();
  final _modelMenu = GlobalKey<PopupMenuButtonState<String>>();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text;
    _message.clear();
    await widget.session.send(text);
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
              ? Center(child: Text(s.askSomething))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
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
                  avatar: const Icon(Icons.tune, size: 16),
                  label: Text(session.model ?? ''),
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
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('message'),
                  controller: _message,
                  enabled: !session.busy,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: s.message, border: OutlineInputBorder()),
                ),
              ),
              if (session.busy)
                IconButton(tooltip: s.stop, icon: const Icon(Icons.stop), onPressed: session.stop)
              else
                IconButton(tooltip: s.send, icon: const Icon(Icons.send), onPressed: _send),
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
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
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
    final (alignment, background, foreground) = switch (line.role) {
      ChatRole.user => (Alignment.centerRight, colors.primaryContainer, colors.onPrimaryContainer),
      ChatRole.assistant => (
        Alignment.centerLeft,
        colors.surfaceContainerHighest,
        colors.onSurface,
      ),
      ChatRole.error => (Alignment.centerLeft, colors.errorContainer, colors.onErrorContainer),
    };
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: SelectableText(line.text, style: TextStyle(color: foreground)),
      ),
    );
  }
}
