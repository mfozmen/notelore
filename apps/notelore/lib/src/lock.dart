/// The app lock (#224, #295): the screen at start while it is on, and the
/// dialogs in Settings that turn it on and off. It opens with the device's own
/// lock, or with a Notelore pattern or PIN (an older lock's password still
/// works). A pattern or PIN is never kept, only its salted hash, in the keystore.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lock_state.dart';
import 'mark.dart';
import 'pattern_pad.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// The shortest PIN the lock takes.
const minLockLength = 4;

/// Shown instead of everything else until the lock opens.
class LockScreen extends StatefulWidget {
  const LockScreen(this.session, {super.key});

  final Session session;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _secret = TextEditingController();
  var _checking = false;
  var _wrong = false;

  /// A pattern drawn through too few dots: said, nothing tried.
  var _tooShort = false;

  /// The device's prompt did not open it; [_deviceGone] when the device has
  /// no lock of its own any more, so no prompt ever could.
  var _deviceFailed = false;
  var _deviceGone = false;

  /// Ticks while a wait after wrong tries runs, so the countdown moves and the
  /// lock takes tries again when it ends.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _waitIfNeeded();
    // The device's own prompt comes up by itself; the button brings it back.
    if (widget.session.lock.kind == LockKind.device) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlockWithDevice());
    }
  }

  void _waitIfNeeded() {
    if (widget.session.lock.wait == Duration.zero) return;
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
      if (widget.session.lock.wait > Duration.zero) return;
      _tick?.cancel();
      _tick = null;
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _unlockWith(String secret) async {
    setState(() {
      _checking = true;
      _wrong = false;
      _tooShort = false;
    });
    final opened = await widget.session.lock.unlock(secret);
    if (opened || !mounted) return; // the app shows its screens now
    _secret.clear();
    setState(() {
      _checking = false;
      _wrong = true;
    });
    _waitIfNeeded();
  }

  Future<void> _unlockWithDevice() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    final lock = widget.session.lock;
    try {
      if (await lock.unlockWithDevice(widget.session.strings.unlockReason)) return;
      final gone = !await lock.deviceAvailable();
      if (!mounted) return;
      setState(() {
        _deviceFailed = true;
        _deviceGone = gone;
      });
    } finally {
      if (mounted) setState(() => _checking = false); // never a button stuck off
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final theme = Theme.of(context);
    final wait = widget.session.lock.wait;
    final waiting = wait > Duration.zero;
    final problem = waiting ? s.lockWaiting(wait) : (_wrong ? s.wrongSecret : null);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: NoteloreMark(size: 56)),
                  const SizedBox(height: Gap.m),
                  Text(
                    s.lockedTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: Gap.l),
                  ..._opener(s, waiting, problem),
                  const SizedBox(height: Gap.l),
                  Text(s.lockedHint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What opens this lock: the device's prompt, the pattern pad, or a field.
  List<Widget> _opener(Strings s, bool waiting, String? problem) {
    final kind = widget.session.lock.kind;
    if (kind == LockKind.device) {
      return [
        FilledButton.icon(
          key: const Key('unlock-device'),
          icon: const Icon(Icons.fingerprint),
          onPressed: _checking ? null : _unlockWithDevice,
          label: Text(s.unlock),
        ),
        if (_deviceGone)
          _Problem(s.deviceLockGone)
        else if (_deviceFailed)
          _Problem(s.deviceNotUnlocked),
      ];
    }
    if (kind == LockKind.pattern) {
      // One line above the pad: what to do, or why it did not open. The wait's
      // countdown changes every second, so it is not read out each time.
      final String status;
      if (problem != null) {
        status = problem;
      } else if (_tooShort) {
        status = s.drawPattern;
      } else {
        status = s.drawYourPattern;
      }
      return [
        _Problem(status, error: problem != null || _tooShort, live: !waiting, below: false),
        const SizedBox(height: Gap.s),
        Center(
          child: PatternPad(
            strings: s,
            enabled: !_checking && !waiting,
            onDone: _unlockWith,
            onTooShort: () => setState(() {
              _tooShort = true;
              _wrong = false;
            }),
          ),
        ),
      ];
    }
    final pin = kind == LockKind.pin;
    return [
      TextField(
        key: const Key('unlock'),
        controller: _secret,
        obscureText: true,
        autofocus: true,
        enabled: !_checking && !waiting,
        keyboardType: pin ? TextInputType.number : TextInputType.visiblePassword,
        inputFormatters: [if (pin) FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _unlockWith(_secret.text),
        decoration: InputDecoration(labelText: pin ? s.lockPin : s.lockSecret, errorText: problem),
      ),
      const SizedBox(height: Gap.m),
      FilledButton(
        onPressed: _checking || waiting ? null : () => _unlockWith(_secret.text),
        child: Text(s.unlock),
      ),
    ];
  }
}

/// A line about the lock: why it did not open ([error]), or what to do. Read
/// out when it appears, unless it changes every second ([live] false).
class _Problem extends StatelessWidget {
  const _Problem(this.text, {this.error = true, this.live = true, this.below = true});

  final String text;
  final bool error;
  final bool live;

  /// Under what it is about (a button, a pad), with a gap above.
  final bool below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: below ? Gap.s : 0),
      child: Semantics(
        liveRegion: live,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: error ? colors.error : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Lets the person choose what locks Notelore, then sets it up.
Future<void> turnLockOn(BuildContext context, Session session) async {
  final kind = await showDialog<LockKind>(context: context, builder: (_) => _ChooseLock(session));
  if (kind == null || !context.mounted) return;
  switch (kind) {
    case LockKind.device:
      await session.lock.useDevice(session.strings.lockOnReason);
    case LockKind.pattern:
      await showDialog<void>(context: context, builder: (_) => _NewPattern(session));
    default:
      await showDialog<void>(context: context, builder: (_) => _NewLock(session));
  }
}

/// Asks for what opens the lock now, then turns it off.
Future<void> turnLockOff(BuildContext context, Session session) async {
  switch (session.lock.kind) {
    case LockKind.device:
      await session.lock.removeWithDevice(session.strings.lockOffReason);
    case LockKind.pattern:
      await showDialog<void>(context: context, builder: (_) => _CurrentPattern(session));
    default:
      await showDialog<void>(context: context, builder: (_) => _CurrentLock(session));
  }
}

/// The device's lock (recommended, when the device has one), a pattern or a PIN.
class _ChooseLock extends StatelessWidget {
  const _ChooseLock(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return AlertDialog(
      title: Text(s.lockChoose),
      scrollable: true,
      contentPadding: const EdgeInsets.symmetric(vertical: Gap.m),
      content: FutureBuilder<bool>(
        future: session.lock.deviceAvailable(),
        builder: (context, available) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DeviceChoice(s, available: available.data),
            ListTile(
              key: const Key('lock-pattern'),
              leading: const Icon(Icons.pattern),
              title: Text(s.lockWithPattern),
              onTap: () => Navigator.pop(context, LockKind.pattern),
            ),
            ListTile(
              key: const Key('lock-pin'),
              leading: const Icon(Icons.pin_outlined),
              title: Text(s.lockWithPin),
              onTap: () => Navigator.pop(context, LockKind.pin),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel))],
    );
  }
}

/// The device's own lock: recommended where there is one, and why not where
/// there is none ([available] is null while the device is still being asked).
class _DeviceChoice extends StatelessWidget {
  const _DeviceChoice(this.s, {required this.available});

  final Strings s;
  final bool? available;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final none = available == false;
    return ListTile(
      key: const Key('lock-device'),
      enabled: available ?? false,
      leading: const Icon(Icons.fingerprint),
      title: Wrap(
        spacing: Gap.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(s.lockWithDevice),
          if (available == true)
            Text(
              s.recommended,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
      // Why it cannot be chosen is the point of the line: never greyed out.
      subtitle: Text(
        none ? s.lockNoDevice : s.lockWithDeviceExplained,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      onTap: () => Navigator.pop(context, LockKind.device),
    );
  }
}

/// A new pattern, drawn twice.
class _NewPattern extends StatefulWidget {
  const _NewPattern(this.session);

  final Session session;

  @override
  State<_NewPattern> createState() => _NewPatternState();
}

class _NewPatternState extends State<_NewPattern> {
  String? _first;
  var _mismatch = false;

  Future<void> _drawn(String pattern) async {
    final first = _first;
    if (first == null) return setState(() => _first = pattern);
    if (first != pattern) {
      return setState(() {
        _first = null;
        _mismatch = true;
      });
    }
    await widget.session.lock.set(pattern, kind: LockKind.pattern);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final String step;
    if (_first != null) {
      step = s.drawPatternAgain;
    } else if (_mismatch) {
      step = s.patternMismatch;
    } else {
      step = s.drawPattern;
    }
    return AlertDialog(
      title: Text(s.lockWithPattern),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(liveRegion: true, child: Text(step, textAlign: TextAlign.center)),
          const SizedBox(height: Gap.m),
          PatternPad(strings: s, onDone: _drawn),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel))],
    );
  }
}

/// The current pattern, to turn the lock off.
class _CurrentPattern extends StatefulWidget {
  const _CurrentPattern(this.session);

  final Session session;

  @override
  State<_CurrentPattern> createState() => _CurrentPatternState();
}

class _CurrentPatternState extends State<_CurrentPattern> {
  var _wrong = false;

  Future<void> _drawn(String pattern) async {
    final removed = await widget.session.lock.remove(pattern);
    if (!mounted) return;
    if (removed) return Navigator.pop(context);
    setState(() => _wrong = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final wait = widget.session.lock.wait;
    final waiting = wait > Duration.zero;
    return AlertDialog(
      title: Text(s.appLock),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PatternPad(strings: s, enabled: !waiting, onDone: _drawn),
          if (waiting)
            _Problem(s.lockWaiting(wait), live: false)
          else if (_wrong)
            _Problem(s.wrongSecret),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel))],
    );
  }
}

/// A new PIN, typed twice.
class _NewLock extends StatefulWidget {
  const _NewLock(this.session);

  final Session session;

  @override
  State<_NewLock> createState() => _NewLockState();
}

class _NewLockState extends State<_NewLock> {
  late final _first = TextEditingController()..addListener(_changed);
  late final _repeat = TextEditingController()..addListener(_changed);
  var _saving = false;

  void _changed() => setState(() {});

  @override
  void dispose() {
    _first.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _tooShort => _first.text.isNotEmpty && _first.text.length < minLockLength;
  bool get _mismatch => _repeat.text.isNotEmpty && _repeat.text != _first.text;
  bool get _ready => !_saving && _first.text.length >= minLockLength && _repeat.text == _first.text;

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.session.lock.set(_first.text, kind: LockKind.pin);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    return AlertDialog(
      title: Text(s.lockWithPin),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PinField(
            fieldKey: const Key('lock-new'),
            controller: _first,
            label: s.lockPin,
            error: _tooShort ? s.lockTooShort : null,
            autofocus: true,
          ),
          _PinField(
            fieldKey: const Key('lock-repeat'),
            controller: _repeat,
            label: s.lockRepeat,
            error: _mismatch ? s.lockMismatch : null,
          ),
        ],
      ),
      actions: _actions(context, s, s.turnOn, _ready ? _save : null),
    );
  }
}

/// A PIN: digits only, the number pad, hidden.
class _PinField extends StatelessWidget {
  const _PinField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.error,
    this.autofocus = false,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? error;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    obscureText: true,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, errorText: error),
  );
}

/// The current PIN (or an older lock's password), to turn the lock off.
class _CurrentLock extends StatefulWidget {
  const _CurrentLock(this.session);

  final Session session;

  @override
  State<_CurrentLock> createState() => _CurrentLockState();
}

class _CurrentLockState extends State<_CurrentLock> {
  final _secret = TextEditingController();
  var _wrong = false;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final removed = await widget.session.lock.remove(_secret.text);
    if (!mounted) return;
    if (removed) {
      Navigator.pop(context);
    } else {
      _secret.clear();
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final pin = widget.session.lock.kind == LockKind.pin;
    return AlertDialog(
      title: Text(s.appLock),
      content: TextField(
        key: const Key('lock-current'),
        controller: _secret,
        obscureText: true,
        autofocus: true,
        keyboardType: pin ? TextInputType.number : TextInputType.visiblePassword,
        inputFormatters: [if (pin) FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _check(),
        decoration: InputDecoration(
          labelText: pin ? s.lockPin : s.lockSecret,
          errorText: _wrong ? s.wrongSecret : null,
        ),
      ),
      actions: _actions(context, s, s.turnOff, _check),
    );
  }
}

List<Widget> _actions(BuildContext context, Strings s, String confirm, VoidCallback? onConfirm) => [
  TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
  FilledButton(onPressed: onConfirm, child: Text(confirm)),
];
