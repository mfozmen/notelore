import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'mark.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'whisper_model.dart' show DownloadProblem;

/// First run (and after logging out): pick a provider, paste its key, connect.
/// Connecting a model, one step at a time (#357): Choose, Connect, Done. The
/// first run shows it in the app's place; [open] shows it over the app, to
/// connect another model, and [closable] lets it be called off.
class ProviderWizard extends StatefulWidget {
  const ProviderWizard(this.session, {this.closable = false, super.key});

  final Session session;
  final bool closable;

  /// Over the app; true once a model was connected, false when called off.
  static Future<bool> open(BuildContext context, Session session) =>
      Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => ProviderWizard(session, closable: true)))
          .then((connected) => connected ?? false);

  @override
  State<ProviderWizard> createState() => _ProviderWizardState();
}

enum _Step { choose, connect, done }

/// How far below the window's top the desktop card sits, the same on every step.
const _cardTop = 96.0;

class _ProviderWizardState extends State<ProviderWizard> with WidgetsBindingObserver {
  late ProviderSpec _spec = widget.session.spec ?? widget.session.providers.first;
  var _step = _Step.choose;

  /// The phone's list goes on under the pinned action.
  var _moreBelow = false;

  /// Some of the list has scrolled up under the header (#472).
  var _scrolledUnder = false;

  bool _scrolled(Notification event) {
    // The list's own scrolling only, not a field's or a selectable text's inside it.
    final metrics = switch (event) {
      ScrollNotification(depth: 0, :final metrics) ||
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics == null) return false;
    final more = metrics.extentAfter > 0;
    final under = metrics.extentBefore > 0;
    if (more != _moreBelow || under != _scrolledUnder) {
      setState(() {
        _moreBelow = more;
        _scrolledUnder = under;
      });
    }
    return false;
  }

  /// The test turn's answer on Done (#361); null while it is on its way.
  String? _tried;

  /// Which test turn is the current one: an earlier one answering late is dropped (#376).
  var _tries = 0;

  /// How long the test turn may take before Done gives up on it (#376).
  static const _tryLimit = Duration(seconds: 20);

  /// The options already connected on this device, marked on their cards.
  var _connected = const <String>{};
  final _key = TextEditingController();
  final _keyFocus = FocusNode();

  /// Connect was pressed with no key: said on the field.
  var _keyMissing = false;

  /// The provider refused the key: said on the field it is about.
  String? _keyRefused;
  String? _problem;
  var _checking = false;

  /// The ChatGPT account signed in but has no plan to share (#321).
  var _noPlan = false;

  /// Sent to a key page: on return, the key may be on the clipboard.
  var _awaitingKey = false;

  /// The key in the box came from the clipboard; said under it.
  var _pasted = false;

  /// What each provider's API key looks like; nothing else is taken from the clipboard.
  static final _keyShapes = {
    'anthropic': RegExp(r'^sk-ant-[0-9A-Za-z_\-]{20,}$'),
    'openai': RegExp(r'^sk-(?!ant-)[0-9A-Za-z_\-]{20,}$'),
    'gemini': RegExp(r'^AIza[0-9A-Za-z_\-]{35}$'),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      widget.session.connections().then((specs) {
        if (mounted) setState(() => _connected = {for (final spec in specs) spec.name});
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _key.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // One look on the first return, key or not: every read shows Android's
    // "pasted from clipboard" notice.
    if (state == AppLifecycleState.resumed && _awaitingKey) {
      _awaitingKey = false;
      unawaited(_pickUpKey());
    }
  }

  /// Back from a key page: a copied key goes into the box (only one shaped like
  /// the chosen provider's, only into an empty box); connecting stays the user's.
  Future<void> _pickUpKey() async {
    final copied = await Clipboard.getData(Clipboard.kTextPlain)
        .then((data) => data?.text?.trim() ?? '', onError: (Object _) => ''); // unreadable: none
    final shape = _keyShapes[_spec.name];
    if (!mounted || shape == null || !shape.hasMatch(copied) || _key.text.isNotEmpty) return;
    setState(() {
      _key.text = copied;
      _pasted = true;
    });
  }

  /// The free way on: Gemini chosen, and its key page opened in the browser.
  void _freeGemini() {
    final gemini = widget.session.providers.firstWhere((p) => p.name == 'gemini');
    setState(() {
      _spec = gemini;
      _noPlan = false;
      _awaitingKey = true;
    });
    unawaited(launchUrl(Uri.parse(gemini.keyUrl!), mode: LaunchMode.externalApplication));
  }

  Future<void> _connect() async {
    if (_spec.requiresApiKey && _key.text.trim().isEmpty) {
      setState(() => _keyMissing = true);
      _keyFocus.requestFocus(); // brings the field into view, keyboard up
      return;
    }
    if (_spec.name == 'device' && !widget.session.deviceModel.ready) {
      final session = widget.session;
      // Back stays open: minutes of downloading must never look like a hang.
      // The download goes on in the session; leaving only skips the connect.
      setState(() => _problem = null);
      await session.downloadDeviceModel();
      if (!mounted || _step != _Step.connect || _spec.name != 'device') return;
      if (!session.deviceModel.ready) {
        final problem = session.deviceProblem ?? DownloadProblem.failed;
        return setState(() => _problem = session.strings.deviceDownloadFailed(problem));
      }
    }
    await _attempt(() => widget.session.connect(_spec, _key.text));
  }

  /// The model on the device is downloading: its button waits, Back does not.
  bool get _downloading => _spec.name == 'device' && widget.session.deviceProgress != null;

  /// A model connected before: used again with its stored key, no key asked.
  Future<void> _useConnected() => _attempt(() => widget.session.switchTo(_spec));

  /// Runs [connect]; on success the wizard says Done, otherwise why not, on Connect.
  Future<void> _attempt(Future<void> Function() connect) async {
    setState(() {
      _checking = true;
      _problem = null;
      _keyRefused = null;
      _noPlan = false;
    });
    var connected = false;
    // The first run's app would switch to the chat on connecting: it waits for Done.
    if (!widget.closable) widget.session.finishingSetup = true;
    try {
      await connect();
      connected = true;
      if (mounted) {
        setState(() {
          _step = _Step.done;
          _tried = null;
        });
        unawaited(_try());
      }
    } on NoChatGptPlan {
      setState(() => _noPlan = true); // no retry helps: another way in does
    } on NoLocalModel {
      setState(() => _problem = widget.session.strings.ollamaNoModel);
    } on KeyValidationError catch (error) {
      setState(() => _keyRefused = error.message);
    } on TransientValidationError catch (error) {
      setState(() => _problem = '${error.message}\n${widget.session.strings.checkConnection}');
    } on Exception catch (error) {
      debugPrint('sign-in failed: $error'); // the detail, for the log only
      setState(() => _problem = widget.session.strings.signInProblem(error));
    } finally {
      if (!connected) widget.session.finishingSetup = false;
      // The plan signs in from Choose; what went wrong is said on Connect.
      if (mounted) {
        setState(() {
          _checking = false;
          if (_step == _Step.choose) _step = _Step.connect;
        });
      }
    }
  }

  // OpenAI's wording for its sign-in button; the model on the device downloads first.
  String _connectLabel(Strings s) => switch (_spec.name) {
    'chatgpt' => s.continueWithChatGpt,
    'device' when !widget.session.deviceModel.ready =>
      _problem == null ? s.downloadAndConnect : s.resumeDownload,
    _ => s.connect,
  };

  /// The one test turn: its answer on Done, or why not, back on Connect.
  Future<void> _try() async {
    final s = widget.session.strings;
    final mine = ++_tries;
    try {
      final answer = await widget.session.tryModel().timeout(_tryLimit);
      if (mounted && mine == _tries) setState(() => _tried = answer);
    } on Object catch (error) {
      // Anything at all, an Error too: Done must never be left spinning.
      if (mounted && mine == _tries) {
        setState(() {
          _problem = switch (error) {
            TimeoutException() => s.tryTimedOut(_tryLimit.inSeconds),
            final Exception error => s.chatError(error),
            _ => s.signInProblem(error),
          };
          _step = _Step.connect;
        });
      }
    }
  }

  /// One step back; the choice made is kept.
  void _back() => setState(() => _step = _Step.values[_step.index - 1]);

  void _finish() =>
      widget.closable ? Navigator.of(context).pop(true) : widget.session.finishSetup();

  /// Where the key goes, or why none is needed.
  List<Widget> _keyEntry(Strings s, ThemeData theme) => [
    if (_spec.requiresApiKey) ...[
      const SizedBox(height: Gap.l),
      TextField(
        key: const Key('api-key'),
        controller: _key,
        focusNode: _keyFocus,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: s.apiKey,
          prefixIcon: const Icon(Icons.key_outlined),
          helperText: _pasted ? s.keyFromClipboard : null,
          errorText: _keyMissing ? s.pasteKeyFirst : _keyRefused,
        ),
        onChanged: (_) {
          if (_keyMissing || _keyRefused != null) {
            setState(() {
              _keyMissing = false;
              _keyRefused = null;
            });
          }
        },
        onSubmitted: (_) => _connect(),
      ),
    ] else if (_spec.name == 'ollama') ...[
      const SizedBox(height: Gap.l),
      Text(s.ollamaNoKey, style: theme.textTheme.bodyMedium),
    ] else if (_spec.name == 'device') ...[
      const SizedBox(height: Gap.l),
      _DeviceDownload(widget.session),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session.strings;
    final muted = theme.colorScheme.onSurfaceVariant;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (_step) {
        _Step.choose => _choose(s, theme, muted),
        _Step.connect => _connectStep(s, theme, muted),
        _Step.done => _done(s, theme, muted),
      },
    );
    final action = _action(s);
    Widget header([double inset = 0]) => _StepHeader(
      inset: inset,
      step: _step.index + 1,
      of: _Step.values.length,
      label: s.stepOf(_step.index + 1, _Step.values.length),
      leading: switch (_step) {
        _Step.connect => BackButton(onPressed: _checking ? null : _back),
        _Step.choose when widget.closable => CloseButton(
          onPressed: () => Navigator.of(context).pop(false),
        ),
        _ => null,
      },
    );
    return PopScope(
      // Back goes a step back; only the first step of an opened wizard leaves,
      // and Done of an opened one finishes: the model is connected by then.
      canPop: _step == _Step.choose && widget.closable,
      onPopInvokedWithResult: (popped, _) {
        if (popped) return;
        if (_step == _Step.connect && !_checking) _back();
        if (_step == _Step.done && widget.closable) _finish();
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, size) => _layout(context, size, header, content, action),
          ),
        ),
      ),
    );
  }

  /// What the step's button does.
  Widget _action(Strings s) => switch (_step) {
    // Connected before: used again at once, with no key asked.
    _Step.choose when _connected.contains(_spec.name) => FilledButton(
      onPressed: _checking ? null : _useConnected,
      child: Text(s.useThisModel),
    ),
    // The plan is one tap, as before: it signs in right here.
    _Step.choose when _spec.name == 'chatgpt' => _connectAction(s),
    _Step.choose => FilledButton(
      onPressed: () => setState(() => _step = _Step.connect),
      child: Text(s.next),
    ),
    _Step.connect => _connectAction(s),
    _Step.done => FilledButton(onPressed: _tried == null ? null : _finish, child: Text(s.start)),
  };

  /// The peak of the wizard: what is connected, and that it can change later.
  List<Widget> _done(Strings s, ThemeData theme, Color muted) => [
    const SizedBox(height: Gap.l),
    Icon(Icons.check_circle_rounded, size: 64, color: theme.colorScheme.primary),
    const SizedBox(height: Gap.l),
    Text(
      s.connectedTo(s.providerName(_spec)),
      style: theme.textTheme.headlineSmall,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: Gap.s),
    Text(
      s.connectedExplained,
      style: theme.textTheme.bodyLarge?.copyWith(color: muted),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: Gap.l),
    // The model's own hello, the proof it works: shaped like an answer in the
    // chat, with the chat's gutter; until it comes, a status line, never a bubble.
    Semantics(
      liveRegion: true,
      child: switch (_tried) {
        null => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Gap.s,
          children: [
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            Flexible(
              child: Text(s.trying, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ),
          ],
        ),
        final answer => LayoutBuilder(
          builder: (context, size) => Center(
            child: Container(
              key: const Key('hello-bubble'),
              constraints: BoxConstraints(maxWidth: Layout.bubble(size.maxWidth)),
              padding: const EdgeInsets.all(Gap.m),
              // The chat's answer bubble: the same shape the model speaks in there.
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: bubbleRadius(mine: false),
              ),
              child: Text(answer, style: theme.textTheme.bodyLarge),
            ),
          ),
        ),
      },
    ),
  ];

  /// Which provider: the plan first, keys and local models under Advanced.
  List<Widget> _choose(Strings s, ThemeData theme, Color muted) => [
    Text(s.chooseProvider, style: theme.textTheme.headlineSmall),
    const SizedBox(height: Gap.s),
    Text(s.chooseProviderWhy, style: theme.textTheme.bodyLarge?.copyWith(color: muted)),
    const SizedBox(height: Gap.m),
    // Every option side by side, each told the same way (#358): nothing hidden.
    for (final spec in widget.session.providers) ...[
      _OptionCard(
        spec: spec,
        strings: s,
        chosen: spec == _spec,
        connected: _connected.contains(spec.name),
        onTap: () => setState(() {
          _spec = spec;
          _problem = null;
          _keyMissing = false;
          _noPlan = false; // about ChatGPT: gone with another choice
          _keyRefused = null;
        }),
      ),
      const SizedBox(height: Gap.m),
    ],
  ];

  /// The chosen provider: what it costs, how to get its key, the key itself.
  List<Widget> _connectStep(Strings s, ThemeData theme, Color muted) => [
    Text(s.providerName(_spec), style: theme.textTheme.headlineSmall),
    const SizedBox(height: Gap.s),
    Text(s.cost(_spec), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
    if (s.keySteps(_spec) case final steps when steps.isNotEmpty) ...[
      const SizedBox(height: Gap.l),
      _Steps(
        steps,
        link: _spec.keyUrl,
        openLabel: s.openKeyPage,
        opened: () => _awaitingKey = true,
      ),
    ],
    ..._keyEntry(s, theme),
    if (_noPlan) _NoPlan(s),
  ];

  // What went wrong sits on the button, in view on a phone and next to the key
  // it is usually about.
  Widget _connectAction(Strings s) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Gap.m,
    children: [
      if (_problem case final problem?) _SignInProblem(problem, key: const Key('setup-problem')),
      // Without a plan, the free way in is the action; the plan stays, quietly,
      // for after an upgrade (#352).
      if (_noPlan) ...[
        FilledButton.icon(
          onPressed: _freeGemini,
          icon: const Icon(Icons.open_in_new),
          label: Text(s.getFreeGeminiKey),
        ),
        TextButton(onPressed: _checking ? null : _connect, child: Text(_connectLabel(s))),
      ] else
        FilledButton(
          onPressed: _checking || _downloading ? null : _connect,
          child: _checking
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: s.signingIn),
                )
              : Text(_connectLabel(s)),
        ),
    ],
  );

  /// A hairline where the list runs on under the header or the action; the same
  /// box either way, so nothing moves and the list beside it is never rebuilt
  /// (its scroll offset would be lost).
  static Widget _edge(String key, {required bool show}) =>
      SizedBox(height: 1, child: show ? Divider(key: Key(key), height: 1) : null);

  /// A desk: one card of a readable width, like the sign-in's. A phone: the
  /// choices scroll and the action stays where the thumb is, above the keyboard
  /// too, when the window is tall enough; otherwise it all scrolls together.
  /// The window's height decides, not what the keyboard leaves, so the layout
  /// never changes under the field being typed in.
  Widget _layout(
    BuildContext context,
    BoxConstraints size,
    Widget Function([double inset]) header,
    Widget content,
    Widget action,
  ) {
    if (size.maxWidth >= Layout.wide) {
      // Held near the top, so the card does not jump between steps; nearer on
      // a short window, where every line of the list counts (#472).
      final top = size.maxHeight < 640 ? Gap.l : _cardTop;
      return Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Gap.l, top, Gap.l, Gap.l),
          child: ConstrainedBox(
            // Never taller than the window: the list scrolls, the action stays in view.
            constraints: BoxConstraints(
              maxWidth: 480,
              // Never negative, in a window shorter than the card's top.
              maxHeight: max(0, size.maxHeight - top - Gap.l),
            ),
            child: Card(
              key: const Key('setup-card'),
              child: Padding(
                // 32, but 16 at the right: the list's own 16 there is the scrollbar's gutter.
                padding: const EdgeInsets.fromLTRB(
                  Gap.l + Gap.s,
                  Gap.l + Gap.s,
                  Gap.m,
                  Gap.l + Gap.s,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.m),
                      child: header(),
                    ),
                    const SizedBox(height: Gap.l),
                    // As wide as the content: the gutter on the right is the scrollbar's.
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.m),
                      child: _edge('header-edge', show: _scrolledUnder),
                    ),
                    Flexible(
                      child: NotificationListener<Notification>(
                        onNotification: _scrolled,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(right: Gap.m),
                          child: content,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.m),
                      child: _edge('action-edge', show: _moreBelow),
                    ),
                    const SizedBox(height: Gap.l),
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.m),
                      child: action,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (MediaQuery.sizeOf(context).height < 560) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.l,
          children: [header(), content, action],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The back button sits nearer the edge; the bar lines up with the content.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.s, Gap.s, Gap.l, 0),
          child: header(Gap.l - Gap.s),
        ),
        _edge('header-edge', show: _scrolledUnder),
        Expanded(
          child: NotificationListener<Notification>(
            onNotification: _scrolled,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.l, Gap.l, Gap.l, Gap.m),
              child: content,
            ),
          ),
        ),
        // An edge while the list runs on under the action (#352).
        _edge('action-edge', show: _moreBelow),
        Padding(padding: const EdgeInsets.fromLTRB(Gap.l, Gap.s, Gap.l, Gap.m), child: action),
      ],
    );
  }
}

/// Where the wizard is: back or close, then three segments, the ones done
/// filled, with the step said for screen readers and in a small label.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.inset,
    required this.step,
    required this.of,
    required this.label,
    required this.leading,
  });

  /// How far the bar starts right of the button's slot, to line up with the content.
  final double inset;
  final int step;
  final int of;
  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Row(
          spacing: Gap.s,
          children: [
            // The same room with or without a button, so nothing below shifts.
            SizedBox.square(dimension: 48, child: leading),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: inset),
          child: ExcludeSemantics(
            child: Row(
              key: const Key('step-bar'),
              spacing: Gap.xs,
              children: [
                for (var i = 1; i <= of; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step ? colors.primary : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// How to get a key, as numbered steps; the key page opens from the first
/// one, where it says to sign in.
class _Steps extends StatelessWidget {
  const _Steps(this.steps, {required this.link, required this.openLabel, required this.opened});

  final List<String> steps;
  final String? link;
  final String Function(String host) openLabel;

  /// The link was opened: the key may come back on the clipboard.
  final VoidCallback opened;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.m,
      children: [
        for (final (index, step) in steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.m,
            children: [
              CircleAvatar(
                radius: MediaQuery.textScalerOf(context).scale(12), // grows with the text
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Text('${index + 1}', style: theme.textTheme.labelMedium),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step, style: theme.textTheme.bodyMedium),
                    if (link case final url? when index == 0) ...[
                      const SizedBox(height: Gap.s),
                      OutlinedButton.icon(
                        onPressed: () {
                          opened();
                          unawaited(
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                          );
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(openLabel(Uri.parse(url).host)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A ChatGPT account without Plus or Pro (#321): what happened, plainly, and
/// the free way on in the same place: a Gemini key from Google AI Studio, with
/// what its free tier means for privacy. Not an alarm: nothing went wrong.
class _NoPlan extends StatelessWidget {
  const _NoPlan(this.strings);

  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const Key('no-chatgpt-plan'),
      margin: const EdgeInsets.only(top: Gap.m),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: Gap.s,
              children: [
                Icon(Icons.info_outline, color: colors.primary),
                Expanded(child: Text(strings.noChatGptPlan, style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: Gap.s),
            Text(strings.noChatGptPlanWhy, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.m),
            Text(strings.freeGemini, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.s,
              children: [
                Icon(Icons.privacy_tip_outlined, size: 16, color: colors.onSurfaceVariant),
                Expanded(
                  child: Text(
                    strings.freeGeminiPrivacy,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The first step of setup (#208): sign in with a Google account, which also
/// connects Drive. Without one (refused, cancelled, no account) there is no
/// way on, and the screen says why.
class GoogleScreen extends StatefulWidget {
  const GoogleScreen(this.session, {super.key});

  final Session session;

  @override
  State<GoogleScreen> createState() => _GoogleScreenState();
}

class _GoogleScreenState extends State<GoogleScreen> {
  String? _problem;
  var _signingIn = false;

  Future<void> _signIn() async {
    setState(() {
      _signingIn = true;
      _problem = null;
    });
    try {
      await widget.session.connectDrive();
    } on PartialGrant {
      if (mounted) setState(() => _problem = widget.session.strings.drivePermissionsAll);
    } on SignInFailed catch (error) {
      // Refused or cancelled: no account to go on with.
      if (mounted) {
        debugPrint('Google sign-in refused: ${error.message}');
        setState(() => _problem = widget.session.strings.googleRequired);
      }
    } on Exception catch (error) {
      debugPrint('Google sign-in failed: $error');
      if (mounted) setState(() => _problem = widget.session.strings.signInProblem(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final theme = Theme.of(context);
    // The way on: why it failed (when it did), what it asks for, Google's button.
    final action = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.m,
      children: [
        if (_problem case final problem?) _SignInProblem(problem, key: const Key('google-problem')),
        Text(
          s.welcomeAccount,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        _GoogleButton(
          s.signInWithGoogle,
          busy: _signingIn,
          busyLabel: s.signingIn,
          onPressed: _signingIn ? null : _signIn,
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, size) => size.maxWidth >= Layout.wide
              // A desk: one card of a readable width, in the middle.
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(Gap.l),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Card(
                        key: const Key('google-card'),
                        child: Padding(
                          padding: const EdgeInsets.all(Gap.l + Gap.s), // 32
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: Gap.l,
                            children: [_Welcome(s), action],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              // A phone: the welcome above, the button where the thumb is. With
              // too little height (on its side, large text) it all scrolls.
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(Gap.l),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: size.maxHeight - 2 * Gap.l),
                    child: IntrinsicHeight(
                      child: Column(
                        spacing: Gap.l,
                        children: [
                          Expanded(child: Center(child: _Welcome(s))),
                          action,
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Who Notelore is and why it asks for Google: the app's mark, a welcome, a
/// promise, and two lines that build trust (where the notes go, what it sees).
class _Welcome extends StatelessWidget {
  const _Welcome(this.strings);

  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NoteloreMark(),
        const SizedBox(height: Gap.l),
        Text(
          strings.welcomeTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: Gap.s),
        Text(
          strings.welcomePromise,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.l),
        _Reason(Icons.cloud_done_outlined, strings.welcomeDrive),
        const SizedBox(height: Gap.m),
        _Reason(Icons.lock_outline, strings.welcomePrivate),
      ],
    );
  }
}

/// One reason to trust it: an icon and a line.
class _Reason extends StatelessWidget {
  const _Reason(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.m,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 24, color: theme.colorScheme.primary)),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// Why signing in or connecting did not work, said kindly, and read out when it appears.
class _SignInProblem extends StatelessWidget {
  const _SignInProblem(this.problem, {super.key});

  final String problem;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: problem,
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.m,
            children: [
              Icon(Icons.error_outline, color: colors.onErrorContainer),
              Expanded(
                // Selectable: a command in it (ollama pull …) can be copied.
                child: SelectableText(problem, style: TextStyle(color: colors.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google's own Sign in with Google button, as its branding guidelines draw it
/// (https://developers.google.com/identity/branding-guidelines): its G, its
/// fills, outline and label colours, whatever the app's palette. While it
/// works, a spinner takes the G's place.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton(
    this.label, {
    required this.busy,
    required this.busyLabel,
    required this.onPressed,
  });

  final String label;
  final bool busy;

  /// What a screen reader hears while it works.
  final String busyLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, outline, text) = dark
        ? (const Color(0xFF131314), const Color(0xFF8E918F), const Color(0xFFE3E3E3))
        : (Colors.white, const Color(0xFF747775), const Color(0xFF1F1F1F));
    return OutlinedButton(
      key: const Key('google-sign-in'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: fill,
        disabledBackgroundColor: fill,
        foregroundColor: text,
        disabledForegroundColor: text,
        side: BorderSide(color: outline),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: const StadiumBorder(),
        // The app's font, at the guidelines' size and weight.
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 20 / 14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 10,
        children: [
          SizedBox.square(
            dimension: 20,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2, color: text, semanticsLabel: busyLabel)
                : Image.asset('assets/google/g_${dark ? 'dark' : 'light'}.png'),
          ),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// The model on the device (#328): what the download costs, and while it runs
/// how far it is, in a bar and in words (screen readers hear the value).
class _DeviceDownload extends StatelessWidget {
  const _DeviceDownload(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final s = session.strings;
      final theme = Theme.of(context);
      final progress = session.deviceProgress;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.s,
        children: [
          Text(
            session.deviceModel.ready ? s.deviceModelHere : s.deviceDownloadNote,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (progress != null) ...[
            LinearProgressIndicator(
              value: progress,
              semanticsLabel: s.downloadingModel,
              semanticsValue: '${(progress * 100).floor()}%',
            ),
            Text(s.downloadedPercent((progress * 100).floor()), style: theme.textTheme.bodyMedium),
          ],
        ],
      );
    },
  );
}

/// One option on the Choose step (#358). Every card says who it suits and a few
/// short tags; the chosen one opens to cost, where the notes go, quality and
/// the effort to set it up, so all options fit one screen and stay comparable.
/// Chosen is told by an icon, the border and a tint, never by colour alone.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.spec,
    required this.strings,
    required this.chosen,
    required this.connected,
    required this.onTap,
  });

  final ProviderSpec spec;
  final Strings strings;
  final bool chosen;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    final local = spec.name == 'ollama' || spec.name == 'device';
    return Semantics(
      key: ValueKey('option-${spec.name}'),
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      child: Card(
        margin: EdgeInsets.zero,
        color: chosen ? colors.secondaryContainer.withValues(alpha: .4) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: chosen ? colors.primary : colors.outlineVariant,
            width: chosen ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s + Gap.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: Gap.s,
                  children: [
                    Expanded(child: Text(s.providerName(spec), style: theme.textTheme.titleMedium)),
                    Icon(
                      chosen ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: chosen ? colors.primary : muted,
                    ),
                  ],
                ),
                // Who it suits: what decides, so it comes first.
                Text(s.optionFit(spec), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                if (connected) ...[
                  const SizedBox(height: Gap.s),
                  _Tag(s.connectedBadge, strong: true),
                ],
                // Opened, the details say what the tags did: they swap in one motion.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: chosen
                      ? Padding(
                          padding: const EdgeInsets.only(top: Gap.m),
                          child: Column(
                            spacing: Gap.xs,
                            children: [
                              _Line(Icons.payments_outlined, s.optionCost(spec)),
                              // Where the notes go: a lock only when they stay here.
                              _Line(
                                local ? Icons.lock_outline : Icons.cloud_upload_outlined,
                                s.optionPrivacy(spec),
                              ),
                              _Line(Icons.auto_awesome_outlined, s.optionQuality(spec)),
                              _Line(
                                spec.name == 'chatgpt' ? Icons.bolt_outlined : Icons.build_outlined,
                                s.optionEffort(spec),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: Gap.s),
                          child: SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: Gap.xs,
                              runSpacing: Gap.xs,
                              children: [for (final text in s.optionTags(spec)) _Tag(text)],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short label on an option card; [strong] for what is already true (Connected).
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? colors.secondaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Gap.s),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: strong ? colors.onSecondaryContainer : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One fact on the chosen option's card, after its icon.
class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.s,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
