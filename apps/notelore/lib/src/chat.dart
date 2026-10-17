import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart' show PickedFile;
import 'voice.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {super.key});

  final Session session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final TextEditingController _message = TextEditingController(text: widget.session.draft)
    ..addListener(() => widget.session.draft = _message.text);
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

  /// Text (and PDF text) adding up to more than this is refused rather than
  /// sent: it would fill the model's context. shortcut: text, PDF text and
  /// images; audio is #285.
  static const maxAttachment = 200000;

  /// Images adding up to more than this are refused: the providers' own limit
  /// for one (5 MB), over every image of a message.
  static const maxImage = 5 * 1024 * 1024;

  /// Sends the files picked, with what is typed as their explanation: text
  /// files and PDFs' text in the message, images beside it. A file that is none
  /// of these, a PDF with no text in it (scanned, or damaged), too much, or an
  /// image the model cannot take now, is refused and nothing is sent.
  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await widget.session.exchange.pick(any: true);
    if (picked.isEmpty) return; // called off
    final (:files, :images, :names, :refused) = await _read(picked);
    if (refused != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(refused)));
      return;
    }
    final typed = _message.text.trim();
    _message.clear();
    await widget.session.send(withAttachments(typed, files, images: names), images: images);
  }

  /// [picked] as text attachments and images (with their names), or why they
  /// cannot go: the first file refused, else images the model cannot take now.
  Future<({List<Attachment> files, List<Block> images, List<String> names, String? refused})> _read(
    List<PickedFile> picked,
  ) async {
    final session = widget.session;
    final s = session.strings;
    final files = <Attachment>[];
    final images = <Block>[];
    final names = <String>[];
    var sent = 0; // characters, over every text file of the message
    var pictured = 0; // bytes, over every image of it
    for (final file in picked) {
      // An image first: a GIF begins as plain ASCII.
      final type = imageType(file.bytes);
      final pdf = type == null && _isPdf(file.bytes);
      String? text;
      if (type == null) text = pdf ? await _pdfText(file.bytes) : _text(file.bytes);
      final refused = switch ((type, text)) {
        (null, null) when pdf => s.noPdfText(file.name),
        (null, null) => s.notText(file.name),
        (_?, _) when pictured + file.bytes.length > maxImage => s.tooLarge(file.name),
        (_, final text?) when sent + text.length > maxAttachment => s.tooLarge(file.name),
        _ => null,
      };
      if (refused != null) return (files: files, images: images, names: names, refused: refused);
      if (type != null) {
        images.add(imageBlock(type, file.bytes));
        pictured += file.bytes.length;
        names.add(file.name);
      } else {
        files.add((name: file.name, text: text!));
        sent += text.length;
      }
    }
    final refused = images.isEmpty ? null : _imagesRefused();
    return (files: files, images: images, names: names, refused: refused);
  }

  /// Why images cannot go now, or null: the model cannot look at them, or
  /// something else is on its way (an image joins no running turn and never
  /// waits offline, #278).
  String? _imagesRefused() {
    final session = widget.session;
    final s = session.strings;
    if (!session.acceptsImages) return s.noImages(s.providerName(session.spec!));
    final waiting = session.busy || session.transcript.any((l) => l.role == ChatRole.pending);
    return waiting ? s.imagesNotNow : null;
  }

  static bool _isPdf(List<int> bytes) =>
      bytes.length >= 5 && ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-';

  /// A PDF's text, or null when it has none: scanned, or damaged.
  Future<String?> _pdfText(List<int> bytes) async {
    try {
      final text = await widget.session.readPdf(Uint8List.fromList(bytes));
      return text.trim().isEmpty ? null : text;
    } on Object {
      return null;
    }
  }

  /// [bytes] as text, or null for a file that is not (not UTF-8, or binary).
  static String? _text(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.contains('\u0000') ? null : text;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    // On a wide window the conversation is a readable column, like a page.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.chat),
        child: Column(
          children: [
            Expanded(child: session.transcript.isEmpty ? _Empty(s.askSomething) : _Lines(session)),
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
            _ModelBar(session, menu: _modelMenu),
            _Composer(session, voice: _voice, message: _message, send: _send, attach: _attach),
          ],
        ),
      ),
    );
  }
}

/// No conversation yet: what to do.
class _Empty extends StatelessWidget {
  const _Empty(this.prompt);

  final String prompt;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: Gap.m),
          Text(prompt, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

/// The conversation, newest at the bottom; while a turn runs, its waiting line.
class _Lines extends StatelessWidget {
  const _Lines(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final lines = session.transcript.reversed.toList();
    // One tap sends the last message again; not while a turn runs.
    // After a failure, the way out is the error's own Try again (#306).
    final resendable = switch (lines.firstOrNull?.role) {
      _ when session.busy => -1,
      ChatRole.error => 0,
      _ => lines.indexWhere((l) => l.role == ChatRole.user),
    };
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
      itemCount: lines.length + (session.busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (session.busy) return index == 0 ? _Thinking(s) : _Bubble(lines[index - 1], s);
        return _Bubble(
          lines[index],
          s,
          resend: index == resendable ? session.resend : null,
          retry: session.retryNow,
          answer: index == 0 ? (a) => _answer(lines.length, a) : null,
        );
      },
    );
  }

  /// Only the newest question, and only once: a later tap finds the
  /// conversation moved on (longer than [shown], taken at build), even before
  /// the screen redraws.
  void _answer(int shown, String answer) {
    if (session.transcript.length == shown) unawaited(session.send(answer));
  }
}

/// Above the message box: the model, switchable at any time but not while it
/// works, and the ChatGPT plan notice.
class _ModelBar extends StatelessWidget {
  const _ModelBar(this.session, {required this.menu});

  final Session session;
  final GlobalKey<PopupMenuButtonState<String>> menu;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Gap.s,
        children: [
          // The models the connected provider listed; switching keeps the conversation.
          PopupMenuButton<String>(
            key: menu,
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
    );
  }
}

/// The message box and its one button, like a messenger's: Send with text,
/// push to talk without; above them, what voice is doing or how to use it.
class _Composer extends StatefulWidget {
  const _Composer(
    this.session, {
    required this.voice,
    required this.message,
    required this.send,
    required this.attach,
  });

  final Session session;
  final VoiceMode voice;
  final TextEditingController message;
  final Future<void> Function() send;
  final Future<void> Function() attach;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  VoiceMode get _voice => widget.voice;

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

  void _pressed(PointerDownEvent down) {
    _down = down.timeStamp;
    setState(() => _holdHint = false);
    _hold();
  }

  void _released(PointerUpEvent up) {
    _voice.release();
    // A plain click records nothing: say how it works.
    if (up.timeStamp - _down < const Duration(milliseconds: 300)) {
      setState(() => _holdHint = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    return ListenableBuilder(
      listenable: _voice,
      builder: (context, _) => Column(
        children: [
          if (_voice.state == VoiceState.speaking || _holdHint)
            _VoiceStatus(s, speaking: _voice.state == VoiceState.speaking),
          _ComposerRow(
            session,
            voice: _voice,
            message: widget.message,
            send: widget.send,
            attach: widget.attach,
            talk: _TalkButton(
              label: s.talk,
              listening: _voice.state == VoiceState.listening,
              busy: session.busy,
              pressed: _pressed,
              released: _released,
              cancelled: _voice.release,
              toggle: _toggleTalk,
              onKey: (event) => _talkKey(event, busy: session.busy),
            ),
          ),
        ],
      ),
    );
  }
}

/// The message box (or the recording in its place) and its buttons: stop the
/// reading, stop the turn, and one button that sends with text and is [talk]
/// without.
class _ComposerRow extends StatelessWidget {
  const _ComposerRow(
    this.session, {
    required this.voice,
    required this.message,
    required this.send,
    required this.attach,
    required this.talk,
  });

  final Session session;
  final VoiceMode voice;
  final TextEditingController message;
  final Future<void> Function() send;
  final Future<void> Function() attach;
  final Widget talk;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.s, Gap.s, Gap.m, Gap.m),
      child: ValueListenableBuilder(
        valueListenable: message,
        // Apart, and level with the box's last line as it grows.
        builder: (context, typed, _) => Row(
          spacing: Gap.s,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: s.attachFile,
              icon: const Icon(Icons.attach_file),
              onPressed: attach,
            ),
            Expanded(
              // While recording, the recording takes the field's place;
              // the field's text stays in its controller.
              child: voice.state == VoiceState.listening
                  ? _Recording(s.listening)
                  : _MessageField(message, voice: voice, hint: s.message, send: send),
            ),
            if (voice.state == VoiceState.speaking)
              IconButton(
                tooltip: s.stopReading,
                icon: const Icon(Icons.volume_off_outlined),
                onPressed: voice.end,
              ),
            if (session.busy)
              IconButton(tooltip: s.stop, icon: const Icon(Icons.stop), onPressed: session.stop),
            if (typed.text.trim().isNotEmpty)
              IconButton.filled(
                tooltip: s.send,
                icon: const Icon(Icons.arrow_upward),
                onPressed: send,
              )
            else
              talk,
          ],
        ),
      ),
    );
  }
}

/// The message box. Open while the model works: what is written meanwhile
/// joins its turn.
class _MessageField extends StatelessWidget {
  const _MessageField(
    this.controller, {
    required this.voice,
    required this.hint,
    required this.send,
  });

  final TextEditingController controller;
  final VoiceMode voice;
  final String hint;
  final Future<void> Function() send;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('message'),
    controller: controller,
    minLines: 1,
    maxLines: 5,
    textInputAction: TextInputAction.send,
    // Typing quiets an answer read aloud.
    onChanged: (text) {
      if (voice.state == VoiceState.speaking && text.isNotEmpty) voice.hush();
    },
    onSubmitted: (_) => send(),
    decoration: InputDecoration(hintText: hint),
  );
}

/// Push to talk: held, it listens; let go, what was said is sent. The press
/// stays with this Listener wherever the finger goes, even when the keyboard
/// closing moves it (#212). A screen reader cannot hold: one tap starts, the
/// next sends ([toggle]); the keyboard holds Space or Enter ([onKey]).
class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.label,
    required this.listening,
    required this.busy,
    required this.pressed,
    required this.released,
    required this.cancelled,
    required this.toggle,
    required this.onKey,
  });

  final String label;
  final bool listening;
  final bool busy;
  final ValueChanged<PointerDownEvent> pressed;
  final ValueChanged<PointerUpEvent> released;
  final VoidCallback cancelled;
  final VoidCallback toggle;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: busy ? null : pressed,
    onPointerUp: released,
    onPointerCancel: (_) => cancelled(),
    child: Semantics(
      label: label,
      button: true,
      enabled: !busy,
      focusable: true,
      excludeSemantics: true,
      onTap: busy ? null : toggle,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => onKey(event),
        child: IconButton.filled(
          tooltip: label,
          icon: Icon(listening ? Icons.mic : Icons.mic_none),
          onPressed: busy ? null : () {},
        ),
      ),
    ),
  );
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

/// A line above the message box: the answer is read aloud ([speaking]), or else
/// how to talk: above the button, not over it, so a plain click learns to hold.
class _VoiceStatus extends StatelessWidget {
  const _VoiceStatus(this.strings, {required this.speaking});

  final Strings strings;
  final bool speaking;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.s),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          speaking ? Icons.volume_up : Icons.touch_app_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: Gap.s),
        Flexible(
          // wraps on a narrow phone
          child: speaking
              ? Text(strings.speaking, key: const Key('voice-state'))
              : Text(strings.holdHint),
        ),
      ],
    ),
  );
}

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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // A passing status where the answer will appear, not an answer (#290): no
    // bubble, small muted italic words. A screen reader hears one steady line;
    // the playful ones change too often to read out.
    return Semantics(
      key: const Key('working'),
      liveRegion: true,
      label: widget.strings.working,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.s),
        child: Row(
          spacing: Gap.s,
          children: [
            SizedBox.square(
              dimension: 14,
              // Less motion asked for: a still mark instead of a spinner.
              child: MediaQuery.disableAnimationsOf(context)
                  ? Icon(Icons.more_horiz, size: 14, color: muted)
                  : CircularProgressIndicator(strokeWidth: 1.5, color: muted),
            ),
            Flexible(
              child: Text(
                _waiting,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the conversation. Messages and answers have a Copy button under
/// them; the last message also one that sends it again ([resend]). The answers
/// the newest question suggests are buttons that send one of them ([answer]).
class _Bubble extends StatelessWidget {
  const _Bubble(this.line, this.strings, {this.resend, this.answer, this.retry});

  final ChatLine line;
  final Strings strings;
  final VoidCallback? resend;

  /// For a message that waits (offline, or the usage limit): send what waits now.
  final VoidCallback? retry;
  final ValueChanged<String>? answer;

  Future<void> _copy(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.copied), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    // A failed turn is a status, not an answer: no bubble (#306).
    if (line.role == ChatRole.error) return _ErrorRow(line.text, strings, retry: resend);
    final colors = Theme.of(context).colorScheme;
    final mine = line.role == ChatRole.user || line.role == ChatRole.pending;
    final (background, foreground) = switch (line.role) {
      ChatRole.user => (colors.primary, colors.onPrimary),
      // Not sent yet: the user's, in a quieter tone.
      ChatRole.pending => (colors.primaryContainer, colors.onPrimaryContainer),
      ChatRole.assistant || ChatRole.error => (colors.surfaceContainerHigh, colors.onSurface),
    };
    final (:text, :answers, :files, :images) = _shown(line);
    final bubble = _bubble(
      _BubbleText(text, files: files, images: images, color: foreground, strings: strings),
      mine,
      background,
    );
    if (line.role == ChatRole.pending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          bubble,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: Gap.xs),
              Text(strings.waitingToSend, style: TextStyle(color: colors.onSurfaceVariant)),
              if (retry case final retry?)
                TextButton(onPressed: retry, child: Text(strings.tryNow)),
            ],
          ),
        ],
      );
    }
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        bubble,
        if (answer case final answer? when answers.isNotEmpty)
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.xs,
            children: [
              for (final a in answers) OutlinedButton(onPressed: () => answer(a), child: Text(a)),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(strings.copy, Icons.copy, () => _copy(context, text)),
            if (resend case final resend?) button(strings.resend, Icons.replay, resend),
          ],
        ),
      ],
    );
  }

  Widget _bubble(Widget content, bool mine, Color background) {
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
        child: content,
      ),
    );
  }
}

/// A failed turn, as a status between the lines (#306): an icon and what went
/// wrong, centred, and its way out right there ([retry], for the newest one).
/// The message keeps the normal text colour, so it reads as a notice, not an
/// alarm; only the icon carries the error colour.
class _ErrorRow extends StatelessWidget {
  const _ErrorRow(this.message, this.strings, {this.retry});

  final String message;
  final Strings strings;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('chat-error'),
      padding: const EdgeInsets.symmetric(vertical: Gap.s),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.s,
                children: [
                  Icon(Icons.error_outline, size: 20, color: colors.error),
                  Flexible(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
              if (retry case final retry?)
                TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(strings.tryAgain),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What [line] shows: an answer without its suggested answers' line, a
/// message without the text of the files attached to it, only their names.
({String text, List<String> answers, List<String> files, List<String> images}) _shown(
  ChatLine line,
) {
  if (line.role == ChatRole.assistant) {
    final (:text, :answers) = suggestedAnswers(line.text);
    return (text: text, answers: answers, files: const [], images: const []);
  }
  final (:text, :files, :images) = attachedFiles(line.text);
  return (text: text, answers: const [], files: files, images: images);
}

/// A bubble's words, and under them a line for each file and image sent with
/// them, a little apart: related, but not part of the words.
class _BubbleText extends StatelessWidget {
  const _BubbleText(
    this.text, {
    required this.files,
    required this.images,
    required this.color,
    required this.strings,
  });

  final String text;
  final List<String> files;
  final List<String> images;
  final Color color;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, height: 1.4);
    if (files.isEmpty && images.isEmpty) return SelectableText(text, style: style);
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Gap.xs,
      children: [
        if (text.isNotEmpty) SelectableText(text, style: style),
        for (final name in files)
          _AttachmentLine(name, Icons.description_outlined, s.attachedFile(name), style),
        for (final name in images)
          _AttachmentLine(name, Icons.image_outlined, s.attachedImage(name), style),
      ],
    );
  }
}

/// One file sent with a message: a kind's icon and its name on one line; the
/// whole name in the tooltip (a long press) and for screen readers ([label]).
class _AttachmentLine extends StatelessWidget {
  const _AttachmentLine(this.name, this.icon, this.label, this.style);

  final String name;
  final IconData icon;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Tooltip(
      message: name,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Gap.xs,
        children: [
          Icon(icon, size: 18, color: style.color),
          Flexible(
            child: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

/// Rounded, with a smaller corner on the speaker's side, like a speech bubble.
BorderRadius _bubbleRadius({required bool mine}) => BorderRadius.only(
  topLeft: const Radius.circular(18),
  topRight: const Radius.circular(18),
  bottomLeft: Radius.circular(mine ? 18 : 4),
  bottomRight: Radius.circular(mine ? 4 : 18),
);
