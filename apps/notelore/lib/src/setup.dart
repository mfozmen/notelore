import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
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
      setState(() => _problem = '$error'); // the ChatGPT sign-in: refused, offline
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Grouped by how they are paid for; a group with nothing to offer is left out.
                      for (final group in ProviderGroup.values)
                        if (widget.session.providers.where((s) => s.group == group).toList()
                            case final specs when specs.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.m, Gap.xs, Gap.xs),
                            child: Text(
                              s.groupHeading(group),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.s),
                            child: Text(
                              s.groupExplanation(group),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Card(
                            child: Column(
                              children: [
                                for (final spec in specs)
                                  RadioListTile<ProviderSpec>(
                                    value: spec,
                                    title: Text(s.providerName(spec)),
                                  ),
                              ],
                            ),
                          ),
                        ],
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
    } on Exception catch (error) {
      final why = error is SignInFailed ? error.message : '$error';
      if (mounted) setState(() => _problem = widget.session.strings.googleRequired(why));
    } finally {
      if (mounted) setState(() => _signingIn = false);
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
              shrinkWrap: true,
              padding: const EdgeInsets.all(Gap.l),
              children: [
                Icon(Icons.cloud_outlined, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: Gap.m),
                Text(s.googleExplained, textAlign: TextAlign.center),
                const SizedBox(height: Gap.l),
                Center(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.login),
                    onPressed: _signingIn ? null : _signIn,
                    label: Text(s.signInWithGoogle),
                  ),
                ),
                if (_problem case final problem?) ...[
                  const SizedBox(height: Gap.m),
                  Text(
                    problem,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
