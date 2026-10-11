import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';

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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.chooseProvider, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
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
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(s.groupHeading(group), style: theme.textTheme.titleSmall),
                      ),
                      Text(s.groupExplanation(group), style: theme.textTheme.bodySmall),
                      for (final spec in specs)
                        RadioListTile<ProviderSpec>(value: spec, title: Text(s.providerName(spec))),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(s.cost(_spec), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final (index, step) in s.keySteps(_spec).indexed) Text('${index + 1}. $step'),
            if (_spec.keyUrl case final url?) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
                decoration: InputDecoration(labelText: s.apiKey, border: OutlineInputBorder()),
                onSubmitted: (_) => _connect(),
              ),
            ] else if (_spec.name == 'ollama')
              Text(s.ollamaNoKey),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(problem, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
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
    );
  }
}
