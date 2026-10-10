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
  ProviderSpec _spec = providerSpecs.first;
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
      setState(() => _problem = 'Paste the key first.');
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
      setState(() => _problem = '${error.message}\nCheck the connection and try again.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notelore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Choose a model provider', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<ProviderSpec>(
              groupValue: _spec,
              onChanged: (spec) => setState(() {
                _spec = spec!;
                _problem = null;
              }),
              child: Column(
                children: [
                  for (final spec in providerSpecs)
                    RadioListTile<ProviderSpec>(value: spec, title: Text(spec.displayName)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final (index, step) in _spec.keySteps.indexed) Text('${index + 1}. $step'),
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
                decoration: const InputDecoration(
                  labelText: 'API key',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _connect(),
              ),
            ] else
              const Text('Ollama runs on this computer; no key is needed.'),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(problem, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _checking ? null : _connect,
              child: _checking
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator())
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
