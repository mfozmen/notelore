import 'package:flutter/material.dart';

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
                  itemCount: lines.length,
                  itemBuilder: (context, index) => _Bubble(lines[index]),
                ),
        ),
        if (session.busy) const LinearProgressIndicator(),
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
              IconButton(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: session.busy ? null : _send,
              ),
            ],
          ),
        ),
      ],
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
