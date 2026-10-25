import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kLongPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsService;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'audio_file.dart';
import 'plain_text.dart';
import 'session.dart';
import 'setup.dart' show ProviderWizard;
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart' show FileTooBig, PickedFile;
import 'voice.dart';
import 'web_link.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {super.key});

  final Session session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  /// The line a screen reader hears now, on Android; for one frame only.
  ChatLine? _live;

  /// A line a turn just added, once (#502). Android's TalkBack reads it as a
  /// live region (an announcement would cut its speech short); elsewhere it is
  /// announced, the whole answer as words and the answers it offers, since a
  /// live region says nothing on the desktops and only part of it on iOS.
  void _announce() {
    final session = widget.session;
    final line = session.fresh;
    if (line == null || session.busy) return;
    session.fresh = null;
    if (defaultTargetPlatform == TargetPlatform.android) {
      setState(() => _live = line);
      WidgetsBinding.instance.addPostFrameCallback((_) => _live = null);
      return;
    }
    final (:text, :answers, files: _, images: _) = _shown(line);
    final message = [
      plainText(text),
      if (answers.isNotEmpty) session.strings.suggestedAnswers(answers.join(', ')),
    ].join(' ');
    unawaited(
      SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context)),
    );
  }

  late final TextEditingController _message = TextEditingController(text: widget.session.draft)
    ..addListener(() => widget.session.draft = _message.text);
  final _modelMenu = GlobalKey<PopupMenuButtonState<String>>();

  /// Push to talk, beside the message box.
  late final _voice = VoiceMode(widget.session, voice: widget.session.voice);

  @override
  void initState() {
    super.initState();
    widget.session
      ..addListener(_syncDraft)
      ..addListener(_announce);
  }

  void _syncDraft() {
    final text = widget.session.draft;
    if (_message.text == text) return;
    _message.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    widget.session
      ..removeListener(_syncDraft)
      ..removeListener(_announce);
    _voice
      ..end()
      ..dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text;
    _message.clear();
    _keyboardAway(context);
    await widget.session.send(text);
  }

  /// Text (and PDF text) adding up to more than this is refused rather than
  /// sent: it would fill the model's context.
  static const maxAttachment = 200000;

  /// Images adding up to more than this are refused: the providers' own limit
  /// for one (5 MB), over every image of a message.
  static const maxImage = 5 * 1024 * 1024;

  /// Sends the files picked, with what is typed as their explanation: text
  /// files and PDFs' text in the message, images beside it. A file that is none
  /// of these, a PDF with no text in it (scanned, or damaged), too much, or an
  /// image the model cannot take now, is refused and nothing is sent.
  /// The largest file that is read at all; what is kept of it is smaller still.
  static const _maxFileBytes = 20 * 1024 * 1024;

  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    final List<PickedFile> picked;
    try {
      picked = _distinct(await widget.session.exchange.pick(any: true, maxBytes: _maxFileBytes));
    } on FileTooBig catch (big) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.session.strings.fileTooBig(big.name))));
      return;
    }
    // Called off; or the app locked meanwhile and this screen is gone (#387).
    if (picked.isEmpty || !mounted) return;
    final (:files, :images, :names, :refused) = await _read(picked);
    if (refused != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(refused)));
      return;
    }
    if (!mounted) return; // listening to audio takes a while: the screen may be gone (#387)
    // A recording's, a PDF's or an image's original is kept beside the notes, for the note to link (#279, #534).
    final originals = <String, String>{};
    final imageOriginals = <String, String>{};
    for (final file in picked) {
      final image = imageType(file.bytes) != null;
      if (!image && !isAudio(file.bytes) && !_isPdf(file.bytes)) continue;
      final path = widget.session.keepOriginal(file.name, file.bytes);
      if (path == null) continue;
      originals[file.name] = path;
      if (image) imageOriginals[file.name] = path;
    }
    final typed = _message.text.trim();
    _message.clear();
    _keyboardAway(context);
    final sent = await widget.session.send(
      withAttachments(typed, files, images: names, originals: originals),
      images: images,
    );
    if (sent) return;
    for (final path in imageOriginals.values) {
      widget.session.discardOriginal(path);
    }
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
      final (:text, :type, :refused) = await _content(file);
      final over =
          refused ??
          switch ((type, text)) {
            (_?, _) when pictured + file.bytes.length > maxImage => s.tooLarge(file.name),
            (_, final text?) when sent + text.length > maxAttachment => s.tooLarge(file.name),
            _ => null,
          };
      if (over != null) return (files: files, images: images, names: names, refused: over);
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

  /// [files] with names made distinct ("report (2).pdf"): two of one name, from
  /// two folders, each keep their own marker and their own original.
  static List<PickedFile> _distinct(List<PickedFile> files) {
    final taken = <String>{};
    return [for (final file in files) (name: _free(file.name, taken), bytes: file.bytes)];
  }

  static String _free(String name, Set<String> taken) {
    final dot = name.lastIndexOf('.');
    final (stem, extension) = dot > 0 ? (name.substring(0, dot), name.substring(dot)) : (name, '');
    var free = name;
    for (var n = 2; !taken.add(free); n++) {
      free = '$stem ($n)$extension';
    }
    return free;
  }

  static bool _isPdf(List<int> bytes) =>
      bytes.length >= 5 && ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-';

  /// What [file] holds for the model: its words (audio heard on the device,
  /// a PDF's or a text file's text) or an image's type; or why it cannot go.
  Future<({String? text, String? type, String? refused})> _content(PickedFile file) async {
    final s = widget.session.strings;
    // Audio first: heard on the device, it goes as its words (#285).
    if (isAudio(file.bytes)) {
      final (:text, :refused) = await _audioText(file);
      return (text: text, type: null, refused: refused);
    }
    // An image next: a GIF begins as plain ASCII.
    if (imageType(file.bytes) case final type?) return (text: null, type: type, refused: null);
    if (_isPdf(file.bytes)) {
      final text = await _pdfText(file.bytes);
      return (text: text, type: null, refused: text == null ? s.noPdfText(file.name) : null);
    }
    final text = _text(file.bytes);
    return (text: text, type: null, refused: text == null ? s.notText(file.name) : null);
  }

  /// An audio file's words, heard on the device, or why it cannot go: no
  /// Whisper yet, a format this device cannot open, or no words in it.
  Future<({String? text, String? refused})> _audioText(PickedFile file) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.transcribing(file.name))));
    try {
      final text = await widget.session.audioText(file.bytes);
      return text == null
          ? (text: null, refused: s.audioNoWords(file.name))
          : (text: text, refused: null);
    } on AudioUnavailable {
      return (text: null, refused: s.audioNeedsWhisper(file.name));
    } on AudioUnreadable {
      return (text: null, refused: s.audioFormat(file.name));
    } finally {
      messenger.hideCurrentSnackBar();
    }
  }

  /// A PDF's text, or null when it has none: scanned, damaged, or still not
  /// read after 30 seconds (a hostile or huge one, #389).
  Future<String?> _pdfText(List<int> bytes) async {
    try {
      final text = await widget.session
          .readPdf(Uint8List.fromList(bytes))
          .timeout(const Duration(seconds: 30));
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

  /// An example from the empty chat: in the box, ready to edit or send.
  void _example(String text) => _message.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

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
            Expanded(
              child: session.transcript.isEmpty
                  ? EmptyChat(s, example: session.ready ? _example : null)
                  : _Lines(session, live: _live),
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
            if (session.ready) ...[
              if (session.preparing && !session.busy)
                _Thinking(s, fixed: s.devicePreparing),
              _ModelBar(session, menu: _modelMenu),
              _Composer(session, voice: _voice, message: _message, send: _send, attach: _attach),
            ] else
              _NoModel(session),
          ],
        ),
      ),
    );
  }
}

/// No conversation yet: what to do, and three random examples that put
/// themselves in the box to edit or send ([example]; none without a model).
class EmptyChat extends StatefulWidget {
  const EmptyChat(this.strings, {this.example, this.starters, super.key});

  final Strings strings;
  final ValueChanged<String>? example;

  /// Pins the three shown; null picks a random three from [Strings.examples].
  final List<String>? starters;

  @override
  State<EmptyChat> createState() => _EmptyChatState();
}

class _EmptyChatState extends State<EmptyChat> {
  late List<String> _shown;

  void _pick() => _shown = widget.starters ?? pickExamples(widget.strings.examples, Random());

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void didUpdateWidget(covariant EmptyChat old) {
    super.didUpdateWidget(old);
    if (old.strings.languageCode != widget.strings.languageCode ||
        old.starters != widget.starters) {
      _pick();
    }
  }

  // Low on the screen, near the thumb and the message box.
  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, 0.6),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: Gap.m),
          Text(
            widget.strings.askSomething,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (widget.example case final example?) ...[
            const SizedBox(height: Gap.l),
            // Full-width rows that wrap, so a long example never gets cut.
            for (final e in _shown)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.s),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => example(e),
                    icon: const Icon(Icons.north_west, size: 18),
                    label: Text(e),
                    style: OutlinedButton.styleFrom(
                      alignment: AlignmentDirectional.centerStart,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.m,
                        vertical: Gap.m - Gap.xs,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

/// The conversation, newest at the bottom; while a turn runs, its waiting line.
class _Lines extends StatelessWidget {
  const _Lines(this.session, {this.live});

  /// The newest line, when a screen reader is to hear it now.
  final ChatLine? live;

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final lines = session.transcript.reversed.toList();
    // One tap sends the last message again; not while a turn runs.
    // After a failure, the way out is the error's own Try again (#306).
    final resendable = switch (lines.firstOrNull?.role) {
      _ when session.busy || !session.ready => -1,
      ChatRole.error => 0,
      _ => lines.indexWhere((l) => l.role == ChatRole.user),
    };
    // Copy and resend show under the newest message and answer; older ones on a tap.
    final newest = {
      lines.indexWhere((l) => l.role == ChatRole.assistant),
      lines.indexWhere((l) => l.role == ChatRole.user),
    };
    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
      itemCount: lines.length + (session.busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (session.busy) {
          if (index == 0) {
            return _Thinking(s, fixed: session.preparing ? s.devicePreparing : null);
          }
          return _Bubble(lines[index - 1], s, newest: newest.contains(index - 1));
        }
        return _Bubble(
          lines[index],
          s,
          newest: newest.contains(index),
          // The line a turn just added is read out once; the history stays quiet.
          live: index == 0 && lines[0] == live,
          resend: index == resendable ? session.resend : null,
          retry: session.retryNow,
          answer: index == 0 && session.ready ? (a) => _answer(context, lines.length, a) : null,
        );
      },
    );
  }

  /// Only the newest question, and only once: a later tap finds the
  /// conversation moved on (longer than [shown], taken at build), even before
  /// the screen redraws.
  void _answer(BuildContext context, int shown, String answer) {
    if (session.transcript.length != shown) return;
    _keyboardAway(context);
    unawaited(session.send(answer));
  }
}

/// Sending puts an on-screen keyboard away, or it would cover half the answer.
/// A hardware keyboard (a desktop, a tablet with one) leaves no inset and
/// keeps the focus, so the next message needs no tap.
void _keyboardAway(BuildContext context) {
  if (View.of(context).viewInsets.bottom > 0) FocusManager.instance.primaryFocus?.unfocus();
}

/// In the composer's place when no model is connected (#363): what is missing
/// and one button to the wizard; the conversation and the notes stay.
class _NoModel extends StatelessWidget {
  const _NoModel(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Gap.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.s,
            children: [
              Text(s.noModel, style: theme.textTheme.titleMedium),
              Text(
                s.noModelWhy,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Gap.xs),
              FilledButton(
                onPressed: () => ProviderWizard.open(context, session),
                child: Text(s.connectModel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Above the message box: the model, switchable at any time but not while it
/// works, and the ChatGPT plan notice.
class _ModelBar extends StatelessWidget {
  const _ModelBar(this.session, {required this.menu});

  final Session session;
  final GlobalKey<PopupMenuButtonState<String>> menu;

  /// The model menu's item that opens the plan's usage page.
  static const _manageUsage = '#manage-usage';

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final plan = session.spec?.name == 'chatgpt';
    // At the composer's start, so it reads as a setting, not as a line of the chat.
    return Container(
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, 0),
      // The models the connected provider listed; switching keeps the conversation.
      // On a ChatGPT plan the chip says so and its menu links the plan's usage,
      // as OpenAI's guidelines ask, with no button by the composer (#507).
      child: PopupMenuButton<String>(
        key: menu,
        tooltip: s.changeTheModel,
        enabled: !session.busy,
        initialValue: session.model,
        onSelected: (choice) => choice == _manageUsage
            ? launchUrl(Uri.parse(chatGptUsageUrl), mode: LaunchMode.externalApplication)
            : session.setModel(choice),
        itemBuilder: (_) => [
          for (final m in {...session.models, ?session.model})
            PopupMenuItem(value: m, child: Text(m)),
          if (plan) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _manageUsage,
              // As tall as a model's row, its label on the same edge.
              child: Row(
                children: [
                  Expanded(child: Text(s.manageUsage)),
                  const Icon(Icons.open_in_new, size: 18),
                ],
              ),
            ),
          ],
        ],
        child: Chip(
          avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
          // The model first: a narrow chip cuts the plan's words, not its name.
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  plan ? '${session.model ?? ''} · ${s.usingChatGptPlan}' : session.model ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          visualDensity: VisualDensity.compact,
        ),
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

  /// A tap (no hold) began listening that goes on until the next tap (#452).
  var _latched = false;

  /// The press that ends a tap-started recording: its let-go does nothing more.
  var _stopping = false;

  /// Shorter than this, a press is a tap.
  static const _tap = Duration(milliseconds: 300);

  bool get _stopShown => _latched && _voice.state == VoiceState.listening;

  /// A screen reader's tap: starts listening, or sends what was said.
  void _toggleTalk() {
    if (_voice.state == VoiceState.listening) {
      _latched = false;
      _voice.release();
    } else {
      setState(() => _latched = true);
      unawaited(_hold());
    }
  }

  /// Drops a tap-started recording without sending it.
  void _discard() {
    setState(() => _latched = false);
    _voice.end();
  }

  /// Space or Enter held on the focused talk button: push to talk by keyboard.
  KeyEventResult _talkKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space &&
        event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      setState(() => _latched = false); // a key is held: never a tap's Stop
      unawaited(_hold());
    }
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

  /// The system took the press away (a call, say): it ends like a let-go.
  void _cancelled() {
    _stopping = false;
    _voice.release();
  }

  void _pressed(PointerDownEvent down) {
    _down = down.timeStamp;
    _stopping = false;
    if (_stopShown) {
      _stopping = true;
      _latched = false;
      _voice.release();
      return;
    }
    _latched = false;
    _hold();
  }

  void _released(PointerUpEvent up) {
    if (_stopping) {
      _stopping = false;
      return;
    }
    // A tap keeps listening, and the button turns to Stop; a hold sends on let-go.
    if (up.timeStamp - _down < _tap) {
      setState(() => _latched = true);
      return;
    }
    _voice.release();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    return ListenableBuilder(
      listenable: _voice,
      builder: (context, _) => Column(
        children: [
          if (_voice.state == VoiceState.speaking) _VoiceStatus(s),
          _ComposerRow(
            session,
            voice: _voice,
            message: widget.message,
            send: widget.send,
            attach: widget.attach,
            recording: _Recording(
              _stopShown ? s.listeningTapToSend : s.listening,
              discard: _stopShown ? (s.cancel, _discard) : null,
            ),
            talk: _TalkButton(
              label: _stopShown ? s.stopTalking : s.talk,
              listening: _voice.state == VoiceState.listening,
              stop: _stopShown,
              pressed: _pressed,
              released: _released,
              cancelled: _cancelled,
              toggle: _toggleTalk,
              onKey: _talkKey,
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
    required this.recording,
    required this.talk,
  });

  final Session session;
  final VoiceMode voice;
  final TextEditingController message;
  final Future<void> Function() send;
  final Future<void> Function() attach;
  final Widget recording;
  final Widget talk;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.s, Gap.s, Gap.m, Gap.m),
      child: ValueListenableBuilder(
        valueListenable: message,
        // Apart, and level with the box's last line as it grows.
        builder: (context, typed, _) {
          final listening = voice.state == VoiceState.listening;
          return Row(
            spacing: Gap.s,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: s.attachFile,
                icon: const Icon(Icons.attach_file),
                onPressed: attach,
              ),
              Expanded(
                // While recording, the recording takes the field's place, and
                // the field's text stays in its controller.
                child: voice.state == VoiceState.listening
                    ? recording
                    : _MessageField(message, voice: voice, hint: s.message, send: send),
              ),
              if (voice.state == VoiceState.speaking)
                IconButton(
                  tooltip: s.stopReading,
                  icon: const Icon(Icons.volume_off_outlined),
                  onPressed: voice.end,
                ),
              // While a turn runs, Stop is the thing to do: filled in the talk
              // button's place, or tonal beside the primary when there is one
              // (Send with text typed, or a hold still going on).
              // Keyed, so it never takes over another button's state (ink, hover).
              if (session.busy)
                (typed.text.trim().isEmpty && !listening
                    ? IconButton.filled
                    : IconButton.filledTonal)(
                  key: const Key('stop'),
                  tooltip: s.stop,
                  icon: const Icon(Icons.stop),
                  onPressed: session.stop,
                ),
              if (typed.text.trim().isNotEmpty)
                IconButton.filled(
                  key: const Key('send'),
                  tooltip: s.send,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: send,
                )
              // A hold that a turn interrupts keeps its button, so the let-go still sends.
              else if (!session.busy || listening)
                talk,
            ],
          );
        },
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
    // Sending decides about the keyboard; by default "send" would drop the focus everywhere.
    onEditingComplete: () {},
    decoration: InputDecoration(hintText: hint),
  );
}

/// Talk: held, it listens and let go sends; tapped, it keeps listening and
/// turns into Stop and send ([stop]), and a tap on that sends (#452). The press
/// stays with this Listener wherever the finger goes, even when the keyboard
/// closing moves it (#212). A screen reader cannot hold: one tap starts, the
/// next sends ([toggle]); the keyboard holds Space or Enter ([onKey]).
class _TalkButton extends StatelessWidget {
  const _TalkButton({
    required this.label,
    required this.listening,
    required this.stop,
    required this.pressed,
    required this.released,
    required this.cancelled,
    required this.toggle,
    required this.onKey,
  });

  final String label;
  final bool listening;

  /// A tap started it: the button ends it.
  final bool stop;
  final ValueChanged<PointerDownEvent> pressed;
  final ValueChanged<PointerUpEvent> released;
  final VoidCallback cancelled;
  final VoidCallback toggle;
  final KeyEventResult Function(KeyEvent event) onKey;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: pressed,
    onPointerUp: released,
    onPointerCancel: (_) => cancelled(),
    child: Semantics(
      label: label,
      button: true,
      enabled: true,
      focusable: true,
      excludeSemantics: true,
      onTap: toggle,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => onKey(event),
        child: IconButton.filled(
          tooltip: label,
          icon: Icon(stop ? Icons.arrow_upward : (listening ? Icons.mic : Icons.mic_none)),
          onPressed: () {},
        ),
      ),
    ),
  );
}

/// In the message box's place while recording: it listens and counts the seconds.
class _Recording extends StatefulWidget {
  const _Recording(this.label, {this.discard});

  final String label;

  /// A tap-started recording can be dropped: the tooltip and what does it.
  final (String, VoidCallback)? discard;

  @override
  State<_Recording> createState() => _RecordingState();
}

class _RecordingState extends State<_Recording> {
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

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

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
          Expanded(
            child: Text(
              widget.label,
              key: const Key('voice-state'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
          ),
          Text(_clock(_seconds), style: TextStyle(color: colors.onPrimaryContainer)),
          if (widget.discard case (final tooltip, final drop)?)
            IconButton(
              tooltip: tooltip,
              icon: Icon(Icons.close, color: colors.onPrimaryContainer),
              onPressed: drop,
            ),
        ],
      ),
    );
  }
}

/// Above the button while the answer is read aloud.
class _VoiceStatus extends StatelessWidget {
  const _VoiceStatus(this.strings);

  final Strings strings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.s),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.volume_up, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: Gap.s),
        // wraps on a narrow phone
        Flexible(child: Text(strings.speaking, key: const Key('voice-state'))),
      ],
    ),
  );
}

/// The assistant's turn while it runs: a playful line that changes every
/// [_rotation] (its steps, a search or a write, pass too fast to read).
class _Thinking extends StatefulWidget {
  const _Thinking(this.strings, {this.fixed});

  /// How long each waiting line stays before the next one.
  static const _rotation = Duration(seconds: 4);

  final Strings strings;

  /// One line to keep, as while the model reads its prompt before a message.
  final String? fixed;

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
    if (widget.fixed case final line?) return line;
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
      label: widget.fixed ?? widget.strings.working,
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

/// [content], with [actions] under it while [shown], or after a tap or while
/// the pointer is over it: quiet older lines, their buttons at hand.
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.shown,
    required this.end,
    required this.content,
    required this.actions,
  });

  final bool shown;

  /// On the right, as the person's own lines are.
  final bool end;
  final List<Widget> content;
  final Widget actions;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  var _open = false;
  PointerDownEvent? _down;

  /// Runs out while a press is held: a long press is text selection's.
  Timer? _press;

  @override
  void dispose() {
    _press?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _open = true),
    onExit: (_) => setState(() => _open = false),
    // A raw pointer, not a tap: selectable text keeps its own taps. Only a
    // quick touch toggles: not a scroll, not a long press (that selects
    // text), not a mouse (its hover shows them).
    child: Listener(
      onPointerDown: (event) {
        _down = event;
        _press?.cancel();
        _press = Timer(kLongPressTimeout, () => _down = null);
      },
      onPointerUp: (event) {
        _press?.cancel();
        if (_down case final down?
            when down.kind != PointerDeviceKind.mouse &&
                (event.position - down.position).distance < kTouchSlop) {
          setState(() => _open = !_open);
        }
      },
      child: Column(
        crossAxisAlignment: widget.end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ...widget.content,
          // Laid out even while hidden, so nothing above moves when it shows.
          Visibility(
            visible: widget.shown || _open,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: widget.actions,
          ),
        ],
      ),
    ),
  );
}

/// One line of the conversation. The [newest] message and answer have a Copy
/// button under them, the last message also one that sends it again
/// ([resend]); an older line shows them on a tap or a hover, and a screen
/// reader can copy any line. The answers the newest question suggests are
/// buttons that send one of them ([answer]).
class _Bubble extends StatelessWidget {
  const _Bubble(
    this.line,
    this.strings, {
    this.newest = false,
    this.live = false,
    this.resend,
    this.answer,
    this.retry,
  });

  final ChatLine line;
  final Strings strings;
  final bool newest;

  /// The newest line: a screen reader announces it when it appears.
  final bool live;
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
    if (line.role == ChatRole.error) {
      return Semantics(
        liveRegion: live,
        child: _ErrorRow(line.text, strings, retry: resend),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final mine = line.role == ChatRole.user || line.role == ChatRole.pending;
    final (background, foreground) = switch (line.role) {
      ChatRole.user => (colors.primary, colors.onPrimary),
      // Not sent yet: the user's, in a quieter tone.
      ChatRole.pending => (colors.primaryContainer, colors.onPrimaryContainer),
      ChatRole.assistant || ChatRole.error => (colors.surfaceContainerHigh, colors.onSurface),
    };
    final (:text, :answers, :files, :images) = _shown(line);
    final bubble = Semantics(
      liveRegion: live && line.role == ChatRole.assistant,
      child: _bubble(
        _BubbleText(
          text,
          files: files,
          images: images,
          color: foreground,
          strings: strings,
          markdown: line.role == ChatRole.assistant,
        ),
        mine,
        background,
      ),
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
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(tooltip: tooltip, icon: Icon(icon, size: 20), onPressed: onPressed);
    // An answer as plain words (#335); the user's message as typed.
    void copy() => _copy(context, line.role == ChatRole.assistant ? plainText(text) : text);
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: strings.copy): copy},
      child: _Reveal(
        // Answers are what one copies; one's own older lines keep quiet.
        shown: newest || resend != null || line.role == ChatRole.assistant,
        end: mine,
        content: [
          bubble,
          if (answer case final answer? when answers.isNotEmpty)
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.xs,
              children: [
                for (final a in answers) OutlinedButton(onPressed: () => answer(a), child: Text(a)),
              ],
            ),
        ],
        // Close under its bubble (full-size targets, pulled up a little).
        actions: Transform.translate(
          offset: const Offset(0, -Gap.s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(strings.copy, Icons.copy, copy),
              if (resend case final resend?) button(strings.resend, Icons.replay, resend),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(Widget content, bool mine, Color background) {
    return LayoutBuilder(
      builder: (context, size) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Gap.xs),
          // An answer's first paragraph brings its own small step at the top (#335).
          padding: EdgeInsets.fromLTRB(Gap.m, mine ? Gap.m - Gap.xs : Gap.s, Gap.m, Gap.m - Gap.xs),
          // A gutter on the other side on a phone; a readable line on wide windows.
          constraints: BoxConstraints(maxWidth: Layout.bubble(size.maxWidth)),
          decoration: BoxDecoration(
            color: background,
            borderRadius: bubbleRadius(mine: mine),
          ),
          child: content,
        ),
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
    required this.markdown,
  });

  final String text;
  final List<String> files;
  final List<String> images;
  final Color color;
  final Strings strings;

  /// An answer is Markdown (#305): shown formatted. The user's words are shown as typed.
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, height: 1.4);
    final words = markdown ? _markdown(context, text, style) : SelectableText(text, style: style);
    if (files.isEmpty && images.isEmpty) return words;
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Gap.xs,
      children: [
        if (text.isNotEmpty) words,
        for (final name in files)
          _AttachmentLine(name, Icons.description_outlined, s.attachedFile(name), style),
        for (final name in images)
          _AttachmentLine(name, Icons.image_outlined, s.attachedImage(name), style),
      ],
    );
  }
}

/// [text] formatted, every part in the bubble's own colour [style] so it reads
/// on the bubble in every palette, light and dark; links open in the browser.
/// One selection runs across the whole answer (#335).
Widget _markdown(BuildContext context, String text, TextStyle style) {
  final theme = Theme.of(context);
  final body = theme.textTheme.bodyMedium!.merge(style);
  final color = style.color!;
  final tint = color.withValues(alpha: AnswerStyle.tint);
  final code = body.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
  );
  TextStyle heading(TextStyle? size) =>
      size!.copyWith(color: color, fontWeight: AnswerStyle.headingWeight);
  return SelectionArea(
    child: MarkdownBody(
      data: text,
      onTapLink: (_, href, _) => openWebLink(href),
      // A code block's box carries the tint; its letters are not tinted again.
      syntaxHighlighter: _PlainCode(code),
      // Never fetched: an image address could carry the notes off to whoever
      // the model was steered by. Its words show instead.
      imageBuilder: (_, _, alt) => Text(alt ?? '', style: body),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        // Every block a small step apart, and a paragraph one more: list items
        // sit close, and a list stays under the line that leads into it.
        blockSpacing: Gap.xs,
        pPadding: const EdgeInsets.only(top: Gap.xs),
        h1Padding: const EdgeInsets.only(top: Gap.xs),
        h2Padding: const EdgeInsets.only(top: Gap.xs),
        h3Padding: const EdgeInsets.only(top: Gap.xs),
        p: body,
        listBullet: body,
        strong: const TextStyle(fontWeight: FontWeight.bold).copyWith(color: color),
        em: const TextStyle(fontStyle: FontStyle.italic).copyWith(color: color),
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
        code: code.copyWith(backgroundColor: tint),
        codeblockDecoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(Gap.s)),
        blockquote: body,
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: color.withValues(alpha: AnswerStyle.quoteBar),
              width: AnswerStyle.quoteBarWidth,
            ),
          ),
        ),
        // At most a title's size: the bubble keeps to a few type sizes.
        h1: heading(theme.textTheme.titleMedium),
        h2: heading(theme.textTheme.titleSmall),
        h3: heading(theme.textTheme.titleSmall),
      ),
    ),
  );
}

/// A code block's letters in [style], with no colouring of their own.
class _PlainCode extends SyntaxHighlighter {
  _PlainCode(this.style);

  final TextStyle style;

  @override
  TextSpan format(String source) => TextSpan(style: style, text: source);
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
