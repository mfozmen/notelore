import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, PointerSignalEvent, kLongPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction, SemanticsRole, SemanticsService;
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';

import 'audio_file.dart';
import 'icons.dart';
import 'model_names.dart';
import 'note_view.dart' show pushNote;
import 'plain_text.dart';
import 'section_label.dart' show Star;
import 'session.dart';
import 'setup.dart' show ProviderWizard;
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart' show FileTooBig, PickedFile;
import 'voice.dart';
import 'web_link.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen(this.session, {this.showNote, super.key});

  final Session session;

  /// Shows the note a receipt opens beside the notes list, on a wide window.
  /// Without it the note opens as a page of its own.
  final ValueChanged<NoteInfo>? showNote;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  /// The line a screen reader hears now, on Android; for one frame only.
  ChatLine? _live;

  /// The note of that [kind] and [slug], where it is now; a note deleted or moved since says so.
  void _openNote(String kind, String slug) {
    final session = widget.session;
    String? read(NoteInfo note) {
      try {
        return session.readNote(note);
      } on FileSystemException {
        return null;
      }
    }

    final note = session.listNotes().where((n) => n.kind == kind && n.slug == slug).firstOrNull;
    final text = note == null ? null : read(note);
    if (note != null && text != null) {
      final show = widget.showNote;
      return show != null ? show(note) : pushNote(context, session, note, text);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(session.strings.noteGone)));
  }

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

  /// A chat shortcut for [key] with Ctrl or Cmd, with and without Shift.
  static List<SingleActivator> _withModifiers(LogicalKeyboardKey key, {bool shift = false}) => [
    SingleActivator(key, control: true, shift: shift),
    SingleActivator(key, meta: true, shift: shift),
  ];

  static final _zoomInKeys = [
    ..._withModifiers(LogicalKeyboardKey.equal),
    ..._withModifiers(LogicalKeyboardKey.equal, shift: true),
    ..._withModifiers(LogicalKeyboardKey.add),
    ..._withModifiers(LogicalKeyboardKey.numpadAdd),
  ];
  static final _zoomOutKeys = [
    ..._withModifiers(LogicalKeyboardKey.minus),
    ..._withModifiers(LogicalKeyboardKey.numpadSubtract),
  ];
  static final _resetKeys = [
    ..._withModifiers(LogicalKeyboardKey.digit0),
    ..._withModifiers(LogicalKeyboardKey.numpad0),
  ];

  /// Ctrl/Cmd and the wheel: one step per notch.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    event.scrollDelta.dy < 0 ? widget.session.zoomChatIn() : widget.session.zoomChatOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    // On a wide window the conversation is a readable column, like a page.
    return CallbackShortcuts(
      bindings: {
        for (final key in _zoomInKeys) key: session.zoomChatIn,
        for (final key in _zoomOutKeys) key: session.zoomChatOut,
        for (final key in _resetKeys) key: session.resetChatText,
      },
      child: Focus(
        canRequestFocus: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.chat),
            child: Column(
              children: [
                Expanded(
                  child: Listener(
                    onPointerSignal: _wheel,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: _ZoomedTextScaler(
                          MediaQuery.textScalerOf(context),
                          session.chatTextScale,
                        ),
                      ),
                      child: session.transcript.isEmpty
                          ? EmptyChat(s, example: session.ready ? _example : null)
                          : _Lines(session, live: _live, open: _openNote),
                    ),
                  ),
                ),
                if (session.modelGone)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Layout.column),
                      child: MaterialBanner(
                        leading: Icon(
                          AppIcons.warning,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        content: Text(s.modelGone(s.providerName(session.spec!), session.model!)),
                        actions: [
                          FilledButton(
                            onPressed: () => _modelMenu.currentState!.showButtonMenu(),
                            child: Text(s.changeModel),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (session.ready)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.preparing && !session.busy)
                        _Thinking(s, fixed: s.devicePreparing),
                      _ModelBar(session, menu: _modelMenu),
                      _Composer(
                        session,
                        voice: _voice,
                        message: _message,
                        send: _send,
                        attach: _attach,
                      ),
                    ],
                  )
                else
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Layout.column),
                      child: _NoModel(session),
                    ),
                  ),
                // Clear of the phone's floating tab bar.
                SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The device's own text scale, multiplied by the chat's own.
class _ZoomedTextScaler extends TextScaler {
  const _ZoomedTextScaler(this.inner, this.zoom);

  final TextScaler inner;
  final double zoom;

  @override
  double scale(double fontSize) => inner.scale(fontSize) * zoom;

  @override
  double get textScaleFactor => inner.scale(1) * zoom;
}

/// While Ctrl/Cmd is held the wheel zooms the text, so the list must not also
/// scroll under it.
class _ChatScrollPhysics extends ClampingScrollPhysics {
  const _ChatScrollPhysics({super.parent});

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    final keys = HardwareKeyboard.instance;
    return !keys.isControlPressed && !keys.isMetaPressed && super.shouldAcceptUserOffset(position);
  }

  @override
  _ChatScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChatScrollPhysics(parent: buildParent(ancestor));
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, Gap.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcons.duo(AppIcons.chatEmpty, size: 56, color: colors.primary),
            const SizedBox(height: Gap.m),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                widget.strings.askSomething,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
                      icon: Icon(AppIcons.insert, size: 18, color: colors.primary),
                      label: Text(e),
                      style: OutlinedButton.styleFrom(
                        alignment: AlignmentDirectional.centerStart,
                        backgroundColor: colors.surfaceContainerLow,
                        foregroundColor: colors.onSurface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: colors.outlineVariant),
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
}

/// The conversation, newest at the bottom; while a turn runs, its waiting line.
class _Lines extends StatelessWidget {
  const _Lines(this.session, {required this.open, this.live});

  /// Opens the note a card names.
  final _OpenNote open;

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
      physics: const _ChatScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
      itemCount: lines.length + (session.busy ? 1 : 0),
      itemBuilder: (context, index) => _item(context, index, lines, newest, resendable, s),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    List<ChatLine> lines,
    Set<int> newest,
    int resendable,
    Strings s,
  ) {
    final today = session.clock().toLocal();
    if (session.busy) {
      if (index == 0) {
        return _Thinking(s, fixed: session.preparing ? s.devicePreparing : null);
      }
      return _Bubble(
        lines[index - 1],
        s,
        newest: newest.contains(index - 1),
        open: open,
        today: today,
      );
    }
    return _Bubble(
      lines[index],
      s,
      newest: newest.contains(index),
      open: open,
      today: today,
      // The line a turn just added is read out once; the history stays quiet.
      live: index == 0 && lines[0] == live,
      resend: index == resendable ? session.resend : null,
      retry: session.retryNow,
      answer: index == 0 && session.ready ? (a) => _answer(context, lines.length, a) : null,
      report: index == 0 && lines[0].role == ChatRole.assistant && session.canReport
          ? switch (session.reported) {
              final rel? => () => session.takeBackFeedback(rel),
              null => () => _report(context),
            }
          : null,
      reported: session.reported != null,
    );
  }

  /// Keeps the newest turn for the model's training (#753), with what the user
  /// expected; an Undo takes it back.
  Future<void> _report(BuildContext context) async {
    final s = session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final expected = await showDialog<String>(context: context, builder: (_) => _WrongDialog(s));
    // A model switch while the dialog was open may have dropped the turn.
    if (expected == null || !session.canReport) return;
    final rel = await session.reportWrong(expected);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(s.feedbackSaved),
          action: SnackBarAction(label: s.undo, onPressed: () => session.takeBackFeedback(rel)),
        ),
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

/// Above the message box: the model in use, a menu when there is another to
/// switch to, and the ChatGPT plan notice.
class _ModelBar extends StatelessWidget {
  const _ModelBar(this.session, {required this.menu});

  final Session session;
  final GlobalKey<PopupMenuButtonState<String>> menu;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final plan = session.spec?.access == ProviderAccess.signIn;
    final model = session.model;
    final choices = {...session.models, ?model};
    final switchable = choices.length > 1;
    if (model == null && !plan) return const SizedBox.shrink();
    // On a ChatGPT plan the pill says so, as OpenAI's guidelines ask, with no
    // button by the composer (#507, #513). Its usage link is in Settings (#558).
    final name = model == null ? null : readableModel(model);
    final label = [?name, if (plan) s.usingChatGptPlan].join(' · ');
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontSize: 12, color: colors.onSurface);
    // A bordered pill on the card colour; the arrow only when there is a choice.
    final pill = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, Gap.xs, Gap.s, Gap.xs),
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(AppIcons.sparkle, size: 16, color: colors.primary),
          // The model first: a narrow pill cuts the plan's words, not its name.
          // Nothing to switch to: it wraps, so the plan notice is never cut.
          Flexible(
            child: Text(
              label,
              maxLines: switchable ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (switchable) Icon(AppIcons.expand, size: 16, color: colors.onSurfaceVariant),
        ],
      ),
    );
    // At the composer's start, so it reads as a setting, not as a line of the chat.
    return Container(
      alignment: AlignmentDirectional.centerStart,
      padding: EdgeInsets.fromLTRB(Gap.m, switchable ? 0 : Gap.s, Gap.m, 0),
      // The models the connected provider listed; switching keeps the conversation.
      child: switchable
          ? PopupMenuButton<String>(
              key: menu,
              tooltip: s.changeTheModel,
              enabled: !session.busy,
              initialValue: session.model,
              onSelected: session.setModel,
              itemBuilder: (_) => [
                for (final m in choices) PopupMenuItem(value: m, child: Text(readableModel(m))),
              ],
              // A full-height target around the slim pill.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(widthFactor: 1, child: pill),
              ),
            )
          : MediaQuery.withClampedTextScaling(maxScaleFactor: 1.5, child: pill),
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

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_quick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _quick()); // asked before the chat opened
  }

  @override
  void dispose() {
    widget.session.removeListener(_quick);
    _focus.dispose();
    super.dispose();
  }

  /// The home-screen widget's field or mic (#799): typing, or talking until a tap sends.
  void _quick() {
    final open = widget.session.quickOpen;
    if (!mounted || open == null || open.kind != null) return;
    widget.session.quickOpen = null;
    if (!open.voice) return _focus.requestFocus();
    if (_voice.state != VoiceState.listening) _toggleTalk();
  }

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
            focus: _focus,
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
    required this.focus,
    required this.send,
    required this.attach,
    required this.recording,
    required this.talk,
  });

  final Session session;
  final VoiceMode voice;
  final TextEditingController message;
  final FocusNode focus;
  final Future<void> Function() send;
  final Future<void> Function() attach;
  final Widget recording;
  final Widget talk;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    // One rounded field on the card colour holds the box and its buttons; its
    // edge takes the accent while anything in it has the focus.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(
        builder: (context) => Container(
          key: const Key('composer'),
          margin: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
          padding: const EdgeInsets.all(Gap.xs),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Focus.of(context).hasFocus
                ? Border.all(color: colors.primary, width: 2)
                : Border.all(color: colors.outlineVariant),
          ),
          child: _row(s, colors),
        ),
      ),
    );
  }

  Widget _row(Strings s, ColorScheme colors) => ValueListenableBuilder(
    valueListenable: message,
    // Apart, and level with the box's last line as it grows.
    builder: (context, typed, _) {
      final listening = voice.state == VoiceState.listening;
      return Row(
        spacing: Gap.xs,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: s.attachFile,
            icon: Icon(AppIcons.attach, color: colors.onSurfaceVariant),
            onPressed: attach,
          ),
          Expanded(
            // While recording, the recording takes the field's place, and
            // the field's text stays in its controller.
            child: voice.state == VoiceState.listening
                ? recording
                : _MessageField(message, focus: focus, voice: voice, hint: s.message, send: send),
          ),
          if (voice.state == VoiceState.speaking)
            IconButton(
              tooltip: s.stopReading,
              icon: const Icon(AppIcons.volumeOff),
              onPressed: voice.end,
            ),
          // While a turn runs, Stop is the thing to do: filled in the talk
          // button's place, or tonal beside the primary when there is one
          // (Send with text typed, or a hold still going on).
          // Keyed, so it never takes over another button's state (ink, hover).
          if (session.busy)
            (typed.text.trim().isEmpty && !listening ? IconButton.filled : IconButton.filledTonal)(
              key: const Key('stop'),
              tooltip: s.stop,
              icon: const Icon(AppIcons.stop),
              onPressed: session.stop,
            ),
          if (typed.text.trim().isNotEmpty)
            Orb(
              IconButton(
                key: const Key('send'),
                tooltip: s.send,
                icon: const Icon(AppIcons.send, color: Colors.white),
                onPressed: send,
              ),
            )
          // A hold that a turn interrupts keeps its button, so the let-go still sends.
          else if (!session.busy || listening)
            talk,
        ],
      );
    },
  );
}

/// The glowing accent circle behind Talk and Send: lit from the top left,
/// darker at its rim, with a soft glow of the accent under it.
class Orb extends StatelessWidget {
  const Orb(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final light = theme.brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.95,
          stops: const [0, .55, 1],
          colors: light
              ? [
                  const Color(0xFFFED7AA),
                  theme.extension<NoteloreTokens>()!.bright,
                  const Color(0xFF7C2D12),
                ]
              : [const Color(0xFFFFF1E6), accent, Color.lerp(accent, Colors.black, .55)!],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .45),
            offset: const Offset(0, 6),
            blurRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The message box. Open while the model works: what is written meanwhile
/// joins its turn.
class _MessageField extends StatelessWidget {
  const _MessageField(
    this.controller, {
    required this.focus,
    required this.voice,
    required this.hint,
    required this.send,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoiceMode voice;
  final String hint;
  final Future<void> Function() send;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('message'),
    controller: controller,
    focusNode: focus,
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
    // The field around it draws the edge.
    decoration: InputDecoration(
      hintText: hint,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 14),
    ),
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
        child: Orb(
          IconButton(
            tooltip: label,
            icon: Icon(
              stop ? AppIcons.send : (listening ? AppIcons.micOn : AppIcons.mic),
              color: Colors.white,
            ),
            onPressed: () {},
          ),
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
          Icon(AppIcons.micOn, color: colors.onPrimaryContainer),
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
              icon: Icon(AppIcons.close, color: colors.onPrimaryContainer),
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
        Icon(AppIcons.volumeOn, size: 18, color: Theme.of(context).colorScheme.primary),
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
              dimension: 18,
              // Less motion asked for: a still mark instead of a spinner.
              child: MediaQuery.disableAnimationsOf(context)
                  ? Icon(AppIcons.moreHoriz, size: 18, color: muted)
                  : CircularProgressIndicator(strokeWidth: 2, color: muted),
            ),
            Flexible(
              child: Text(
                _waiting,
                style: theme.textTheme.bodyMedium?.copyWith(
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
          // Only a shown line keeps the row: older ones add it when asked, so
          // their default gap stays a Gap.
          if (widget.shown || _open) widget.actions,
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
    required this.open,
    required this.today,
    this.newest = false,
    this.live = false,
    this.resend,
    this.answer,
    this.retry,
    this.report,
    this.reported = false,
  });

  /// Opens the note one of the answer's cards names.
  final _OpenNote open;

  /// For the year a card's date leaves out.
  final DateTime today;

  /// For the newest answer: tell that it was wrong (#753), or take that back.
  final VoidCallback? report;
  final bool reported;

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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mine = line.role == ChatRole.user || line.role == ChatRole.pending;
    // An answer sits on the page itself; the person's words on their own tint.
    final (background, foreground, edge) = switch (line.role) {
      ChatRole.user => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        theme.extension<NoteloreTokens>()!.mineBorder,
      ),
      // Not sent yet: the user's, in a quieter tone.
      ChatRole.pending => (colors.surfaceContainerLow, colors.onSurface, colors.outlineVariant),
      ChatRole.assistant || ChatRole.error => (null, colors.onSurface, null),
    };
    final (:text, :answers, :files, :images) = _shown(line);
    // The theme tint disappears on the tinted bubbles; they get their own tone.
    final Color? selection = switch (line.role) {
      ChatRole.user || ChatRole.pending => _contrastingSelection(background!, foreground),
      ChatRole.assistant || ChatRole.error => null,
    };
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
          selectionColor: selection,
        ),
        mine,
        background,
        edge,
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
              Icon(AppIcons.schedule, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: Gap.xs),
              Text(strings.waitingToSend, style: TextStyle(color: colors.onSurfaceVariant)),
              if (retry case final retry?)
                TextButton(onPressed: retry, child: Text(strings.tryNow)),
            ],
          ),
        ],
      );
    }
    // An answer as plain words (#335); the user's message as typed.
    void copy() => _copy(context, line.role == ChatRole.assistant ? plainText(text) : text);
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: strings.copy): copy},
      child: _Reveal(
        // Answers are what one copies; one's own older lines keep quiet.
        shown: newest || resend != null || line.role == ChatRole.assistant,
        end: mine,
        content: [bubble, ..._under(answers, colors)],
        // Close under its words (full-size targets, pulled up into the
        // bubble's own bottom room), the icons level with the words' edge.
        actions: Transform.translate(
          offset: Offset(mine ? Gap.s : -Gap.s - Gap.xs, mine ? -Gap.s - Gap.xs : -Gap.m - Gap.xs),
          child: _actions(copy, colors.primary, colors.onSurfaceVariant.withValues(alpha: .8)),
        ),
      ),
    );
  }

  /// Under the words: the answer's cards, then the [answers] it suggests.
  List<Widget> _under(List<String> answers, ColorScheme colors) => [
    for (final card in line.cards)
      switch (card) {
        NoteReceipt() => _Receipt(card, strings, open: () => open(card.kind!, card.slug)),
        DecisionSource() => _Source(
          card,
          strings,
          today: today,
          open: () => open(card.kind, card.slug),
        ),
      },
    if (answer case final answer? when answers.isNotEmpty)
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.xs,
        children: [
          for (final a in answers)
            OutlinedButton(
              onPressed: () => answer(a),
              style: OutlinedButton.styleFrom(backgroundColor: colors.surfaceContainerLow),
              child: Text(a),
            ),
        ],
      ),
  ];

  /// Copy, and for the newest lines Resend and This was wrong (filled once reported).
  Widget _actions(VoidCallback copy, Color reportedColor, Color muted) {
    Widget button(String tooltip, IconData icon, VoidCallback onPressed, [Color? color]) =>
        IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 17, color: color ?? muted),
          onPressed: onPressed,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(strings.copy, AppIcons.copy, copy),
        if (resend case final resend?) button(strings.resend, AppIcons.replay, resend),
        if (report case final report?)
          reported
              ? button(strings.wrongAnswerTakeBack, AppIcons.thumbDownOn, report, reportedColor)
              : button(strings.wrongAnswer, AppIcons.thumbDown, report),
      ],
    );
  }

  /// A selection tone on [surface] that stands off it and keeps [text] readable:
  /// the opposite side of the wheel, darker under light text and lighter under
  /// dark text.
  static Color _contrastingSelection(Color surface, Color text) {
    final hsl = HSLColor.fromColor(surface);
    final light = text.computeLuminance() > 0.5;
    return hsl
        .withHue((hsl.hue + 150) % 360)
        .withSaturation(0.75)
        .withLightness(light ? 0.32 : 0.72)
        .toColor();
  }

  /// The person's message: rounded, its corner on their side smaller.
  static const _mineRadius = BorderRadius.only(
    topLeft: Radius.circular(20),
    topRight: Radius.circular(20),
    bottomLeft: Radius.circular(20),
    bottomRight: Radius.circular(6),
  );

  Widget _bubble(Widget content, bool mine, Color? background, Color? edge) {
    return LayoutBuilder(
      builder: (context, size) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Gap.xs),
          // An answer's first paragraph brings its own small step at the top (#335).
          padding: mine
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.fromLTRB(0, Gap.s, 0, Gap.m - Gap.xs),
          // A gutter on the other side on a phone; a readable line on wide windows.
          constraints: BoxConstraints(maxWidth: Layout.bubbleFor(context, size.maxWidth)),
          decoration: mine
              ? BoxDecoration(
                  color: background,
                  border: Border.all(color: edge!),
                  borderRadius: _mineRadius,
                )
              : null,
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
                  Icon(AppIcons.error, size: 20, color: colors.error),
                  Flexible(
                    child: Text(
                      message,
                      textAlign: TextAlign.start,
                      style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
              if (retry case final retry?)
                TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(AppIcons.refresh, size: 18),
                  label: Text(strings.tryAgain),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _OpenNote = void Function(String kind, String slug);

/// A current decision the answer looked up (#792), as the index holds it: the
/// note view's decision card with its note and an Open below.
class _Source extends StatelessWidget {
  const _Source(this.source, this.strings, {required this.today, required this.open});

  final DecisionSource source;
  final Strings strings;
  final DateTime today;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = theme.extension<NoteloreTokens>()!.label;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13.5,
      color: colors.onSurfaceVariant,
    );
    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Padding(
        padding: const EdgeInsets.only(left: Gap.m, right: Gap.xs, top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: Gap.m - Gap.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.caps(source.topic),
                      semanticsLabel: source.topic,
                      style: label,
                    ),
                  ),
                  Text(
                    strings.shortDate(source.date, today),
                    style: label.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              source.value,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 20, height: 1.25),
            ),
            if (source.reason case final reason?) ...[
              const SizedBox(height: Gap.xs),
              Text(reason, style: muted),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.decisionSource(source.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
                TextButton(
                  onPressed: open,
                  child: Text(
                    '${strings.openNoteLink} →',
                    semanticsLabel: '${strings.openNoteLink} ${source.title}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.column),
        child: card,
      ),
    );
  }
}

/// What the turn did to one note (#791): a mono pill with the note and the
/// change, then Open; an archived note has no Open.
class _Receipt extends StatelessWidget {
  const _Receipt(this.receipt, this.strings, {required this.open});

  final NoteReceipt receipt;
  final Strings strings;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = theme.extension<NoteloreTokens>()!.label;
    final change = strings.noteChange(receipt);
    final edge = BorderSide(color: colors.outlineVariant);
    const side = Gap.s + Gap.xs;
    return Stack(
      children: [
        // Ink, not a box: the Open's ripple shows on it. Thinner than the
        // 48 dp row, which is all Open's target.
        Positioned.fill(
          top: Gap.s - 2,
          bottom: Gap.s - 2,
          child: Ink(
            decoration: ShapeDecoration(
              color: colors.surfaceContainerLow,
              shape: StadiumBorder(side: edge),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: side),
            Star(label.color!),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${strings.caps(receipt.title)} · ${strings.caps(change)}',
                semanticsLabel: '${receipt.title}, $change',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label,
              ),
            ),
            if (receipt.kind == null)
              const SizedBox(width: side, height: 48)
            else ...[
              const SizedBox(width: side),
              Container(width: 1, height: 16, color: colors.outlineVariant),
              Semantics(
                container: true,
                button: true,
                label: '${strings.openNote} ${receipt.title}',
                onTap: open,
                excludeSemantics: true,
                child: InkWell(
                  onTap: open,
                  customBorder: const StadiumBorder(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: side),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          strings.openNote,
                          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
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
    this.selectionColor,
  });

  final String text;
  final List<String> files;
  final List<String> images;
  final Color color;
  final Strings strings;
  final Color? selectionColor;

  /// An answer is Markdown (#305): shown formatted. The user's words are shown as typed.
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, height: 1.4);
    // The same selection the answers use (#695): a drag, a double-click and
    // Cmd+C work on macOS, where a bare SelectableText lost the drag.
    final words = markdown
        ? _markdown(context, text, style)
        : SelectionArea(
            child: Text(text, style: style, selectionColor: selectionColor),
          );
    if (files.isEmpty && images.isEmpty) return words;
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Gap.xs,
      children: [
        if (text.isNotEmpty) words,
        for (final name in files) _AttachmentLine(name, AppIcons.note, s.attachedFile(name), style),
        for (final name in images)
          _AttachmentLine(name, AppIcons.image, s.attachedImage(name), style),
      ],
    );
  }
}

/// [text] formatted, every part in the bubble's own colour [style] so it reads
/// on the bubble in both themes; links open in the browser.
/// One selection runs across the whole answer (#335).
Widget _markdown(BuildContext context, String text, TextStyle style) {
  final theme = Theme.of(context);
  final body = theme.textTheme.bodyMedium!
      .merge(style)
      .copyWith(fontSize: AnswerStyle.size, height: AnswerStyle.lineHeight);
  final color = style.color!;
  final number = theme.extension<NoteloreTokens>()!.label.copyWith(
    fontSize: 11.5,
    letterSpacing: .9,
    height: AnswerStyle.lineHeight,
  );
  final tint = color.withValues(alpha: AnswerStyle.tint);
  final code = body.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
  );
  TextStyle heading(TextStyle? size) =>
      size!.copyWith(color: color, fontWeight: AnswerStyle.headingWeight);
  return SelectionArea(
    child: _AnswerMarkdown(
      data: text,
      onTapLink: (_, href, _) => openWebLink(href),
      // A top-level item is numbered on its card; a nested one keeps its bullet.
      bulletBuilder: (b) => switch ((b.nestLevel, b.style)) {
        (0, _) => Text('${b.index + 1}'.padLeft(2, '0'), style: number),
        (_, BulletStyle.unorderedList) => Text('•', textAlign: TextAlign.center, style: body),
        _ => Text('${b.index + 1}.', textAlign: TextAlign.right, style: body),
      },
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
        // Grows with the text size, so a number never breaks in two.
        listIndent: MediaQuery.textScalerOf(context).scale(24),
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

/// An answer's Markdown with each top-level list on a soft card, and the
/// closing line after a list a little quieter.
class _AnswerMarkdown extends MarkdownBody {
  const _AnswerMarkdown({
    required super.data,
    super.onTapLink,
    super.bulletBuilder,
    super.syntaxHighlighter,
    super.imageBuilder,
    super.styleSheet,
  });

  // The builder hands over a list as a Column of item Rows with spacers
  // between; no other block starts with a Row.
  static bool _isList(Widget block) => block is Column && block.children.firstOrNull is Row;

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    // Blocks and their spacers alternate, so the block before is two back.
    final blocks = children!;
    return super.build(context, [
      for (final (i, block) in blocks.indexed)
        if (_isList(block))
          _ListCard((block as Column).children.whereType<Row>().toList())
        else if (i == blocks.length - 1 && i >= 2 && _isList(blocks[i - 2]))
          Opacity(opacity: AnswerStyle.closing, child: block)
        else
          block,
    ]);
  }
}

/// A list's [items] on a soft card, a hairline between them; a screen reader
/// hears a list, item by item.
class _ListCard extends StatelessWidget {
  const _ListCard(this.items);

  final List<Widget> items;

  @override
  Widget build(BuildContext context) => Container(
    // As wide as the answer, also for a list of short items.
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: Gap.xs),
    child: Semantics(
      role: SemanticsRole.list,
      container: true,
      child: Card(
        // Its own node would sit between the list and its items.
        semanticContainer: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Semantics(
                  role: SemanticsRole.listItem,
                  container: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: item,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
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
    // Its own node: a selection area above it must not merge the label away.
    container: true,
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

/// Asks what the answer should have been; null when cancelled, else the words
/// (maybe none).
class _WrongDialog extends StatefulWidget {
  const _WrongDialog(this.s);

  final Strings s;

  @override
  State<_WrongDialog> createState() => _WrongDialogState();
}

class _WrongDialogState extends State<_WrongDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    void send() => Navigator.of(context).pop(_text.text);
    return AlertDialog(
      title: Text(s.wrongAnswer),
      content: SizedBox(
        width: Layout.bubble(MediaQuery.sizeOf(context).width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.wrongAnswerWhy),
            const SizedBox(height: Gap.m),
            TextField(
              key: const Key('expected-field'),
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => send(),
              decoration: InputDecoration(labelText: s.wrongAnswerExpected, helperText: s.optional),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        FilledButton(onPressed: send, child: Text(s.wrongAnswerKeep)),
      ],
    );
  }
}
