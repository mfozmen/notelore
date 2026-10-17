import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// First run (and after logging out): pick a provider, paste its key, connect.
class SetupScreen extends StatefulWidget {
  const SetupScreen(this.session, {super.key});

  final Session session;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late ProviderSpec _spec = widget.session.providers.first;
  final _key = TextEditingController();
  String? _problem;
  var _checking = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  /// The providers that take a key or run on this computer.
  List<Widget> get _advanced => [
    _ProviderGroup(widget.session, ProviderGroup.apiKey),
    _ProviderGroup(widget.session, ProviderGroup.local),
  ];

  Future<void> _connect() async {
    if (_spec.requiresApiKey && _key.text.trim().isEmpty) {
      setState(() => _problem = widget.session.strings.pasteKeyFirst);
      return;
    }
    setState(() {
      _checking = true;
      _problem = null;
    });
    try {
      await widget.session.connect(_spec, _key.text);
    } on KeyValidationError catch (error) {
      setState(() => _problem = error.message);
    } on TransientValidationError catch (error) {
      setState(() => _problem = '${error.message}\n${widget.session.strings.checkConnection}');
    } on Exception catch (error) {
      debugPrint('sign-in failed: $error'); // the detail, for the log only
      setState(() => _problem = widget.session.strings.signInProblem(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session.strings;
    return Scaffold(
      appBar: AppBar(title: const Text('Notelore')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.l),
              children: [
                Text(s.chooseProvider, style: theme.textTheme.titleLarge),
                const SizedBox(height: Gap.s),
                RadioGroup<ProviderSpec>(
                  groupValue: _spec,
                  onChanged: (spec) => setState(() {
                    _spec = spec!;
                    _problem = null;
                  }),
                  // Grouped by how they are paid for. The plan, one tap, leads;
                  // keys and local models wait under Advanced (#206). Without a
                  // plan to offer there is nothing to be advanced from: all show.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProviderGroup(widget.session, ProviderGroup.plan),
                      if (widget.session.providers.any((p) => p.group == ProviderGroup.plan))
                        ExpansionTile(
                          title: Text(s.advanced),
                          subtitle: Text(
                            s.advancedExplained(localModels: widget.session.localModels),
                          ),
                          tilePadding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                          childrenPadding: EdgeInsets.zero,
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: _advanced,
                        )
                      else
                        ..._advanced,
                    ],
                  ),
                ),
                const SizedBox(height: Gap.m),
                Text(s.cost(_spec), style: theme.textTheme.bodySmall),
                const SizedBox(height: Gap.s),
                for (final (index, step) in s.keySteps(_spec).indexed) Text('${index + 1}. $step'),
                if (_spec.keyUrl case final url?) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                      child: Text(url),
                    ),
                  ),
                ],
                if (_spec.requiresApiKey) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('api-key'),
                    controller: _key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: s.apiKey,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),
                ] else if (_spec.name == 'ollama')
                  Text(s.ollamaNoKey),
                if (_problem case final problem?) ...[
                  const SizedBox(height: 12),
                  Text(problem, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: Gap.m),
                FilledButton(
                  onPressed: _checking ? null : _connect,
                  child: _checking
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
                      // OpenAI's wording for its sign-in button.
                      : Text(_spec.name == 'chatgpt' ? s.continueWithChatGpt : s.connect),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One way of paying, with its providers to pick from (inside the screen's
/// RadioGroup); nothing when this device offers none of them.
class _ProviderGroup extends StatelessWidget {
  const _ProviderGroup(this.session, this.group);

  final Session session;
  final ProviderGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session.strings;
    final specs = session.providers.where((p) => p.group == group).toList();
    if (specs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.m, Gap.xs, Gap.xs),
          child: Text(
            s.groupHeading(group),
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.s),
          child: Text(s.groupExplanation(group), style: theme.textTheme.bodySmall),
        ),
        Card(
          child: Column(
            children: [
              for (final spec in specs)
                RadioListTile<ProviderSpec>(value: spec, title: Text(s.providerName(spec))),
            ],
          ),
        ),
      ],
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
        if (_problem case final problem?) _SignInProblem(problem),
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
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.edit_note, size: 40, color: colors.onPrimaryContainer),
        ),
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

/// Why signing in did not work, said kindly, and read out when it appears.
class _SignInProblem extends StatelessWidget {
  const _SignInProblem(this.problem);

  final String problem;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('google-problem'),
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
                child: Text(problem, style: TextStyle(color: colors.onErrorContainer)),
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
