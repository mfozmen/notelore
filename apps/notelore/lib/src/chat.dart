import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {super.key});

  final Session session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _message = TextEditingController();

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
    final lines = session.transcript.reversed.toList(); // newest at the bottom
    return Column(
      children: [
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Ask or tell me something.'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: lines.length + (session.busy ? 1 : 0),
                  itemBuilder: (context, index) => session.busy
                      ? (index == 0 ? _Thinking(session.step) : _Bubble(lines[index - 1]))
                      : _Bubble(lines[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              // The models the connected provider listed; switching keeps the conversation.
              PopupMenuButton<String>(
                tooltip: 'Change the model',
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
                const Text('Using ChatGPT plan'),
                TextButton(
                  onPressed: () =>
                      launchUrl(Uri.parse(chatGptUsageUrl), mode: LaunchMode.externalApplication),
                  child: const Text('Manage usage'),
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
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (session.busy)
                IconButton(tooltip: 'Stop', icon: const Icon(Icons.stop), onPressed: session.stop)
              else
                IconButton(tooltip: 'Send', icon: const Icon(Icons.send), onPressed: _send),
            ],
          ),
        ),
      ],
    );
  }
}

/// The assistant's turn while it runs: what it is doing and for how long.
class _Thinking extends StatefulWidget {
  const _Thinking(this.step);

  final String? step;

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
            Text('${widget.step ?? 'Thinking'}… $_seconds s'),
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
