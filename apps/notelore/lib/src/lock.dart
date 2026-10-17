/// The app lock (#224): the screen at start while it is on, and the dialogs in
/// Settings that turn it on and off. The PIN or password itself is never kept;
/// the session stores only its salted hash, in the keystore.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// The shortest PIN or password the lock takes.
const minLockLength = 4;

/// Shown instead of everything else until the right PIN or password is given.
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

  /// Ticks while a wait after wrong tries runs, so the countdown moves and the
  /// field opens again when it ends.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _waitIfNeeded();
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

  Future<void> _unlock() async {
    setState(() {
      _checking = true;
      _wrong = false;
    });
    final opened = await widget.session.lock.unlock(_secret.text);
    if (opened || !mounted) return; // the app shows its screens now
    _secret.clear();
    setState(() {
      _checking = false;
      _wrong = true;
    });
    _waitIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final theme = Theme.of(context);
    final wait = widget.session.lock.wait;
    final waiting = wait > Duration.zero;
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
                  Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: Gap.m),
                  Text(
                    s.lockedTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: Gap.l),
                  TextField(
                    key: const Key('unlock'),
                    controller: _secret,
                    obscureText: true,
                    autofocus: true,
                    enabled: !_checking && !waiting,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: s.lockSecret,
                      errorText: waiting
                          ? s.lockWaiting(wait)
                          : _wrong
                          ? s.wrongSecret
                          : null,
                    ),
                  ),
                  const SizedBox(height: Gap.m),
                  FilledButton(
                    onPressed: _checking || waiting ? null : _unlock,
                    child: Text(s.unlock),
                  ),
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
}

/// Asks for a new PIN or password twice, then turns the lock on with it.
Future<void> turnLockOn(BuildContext context, Session session) =>
    showDialog<void>(context: context, builder: (_) => _NewLock(session));

/// Asks for the current PIN or password, then turns the lock off.
Future<void> turnLockOff(BuildContext context, Session session) =>
    showDialog<void>(context: context, builder: (_) => _CurrentLock(session));

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
    await widget.session.lock.set(_first.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    return AlertDialog(
      title: Text(s.appLock),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('lock-new'),
            controller: _first,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: s.lockSecret,
              errorText: _tooShort ? s.lockTooShort : null,
            ),
          ),
          TextField(
            key: const Key('lock-repeat'),
            controller: _repeat,
            obscureText: true,
            decoration: InputDecoration(
              labelText: s.lockRepeat,
              errorText: _mismatch ? s.lockMismatch : null,
            ),
          ),
        ],
      ),
      actions: _actions(context, s, s.turnOn, _ready ? _save : null),
    );
  }
}

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
    return AlertDialog(
      title: Text(s.appLock),
      content: TextField(
        key: const Key('lock-current'),
        controller: _secret,
        obscureText: true,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _check(),
        decoration: InputDecoration(
          labelText: s.lockSecret,
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
