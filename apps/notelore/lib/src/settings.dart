import 'package:flutter/material.dart';

import 'session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.session, {super.key});

  final Session session;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _model = TextEditingController(text: widget.session.model);

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _saveModel() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.session.setModel(_model.text);
    _model.text = widget.session.model!;
    messenger.showSnackBar(const SnackBar(content: Text('Model saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Provider'),
            subtitle: Text(session.spec!.displayName),
          ),
          TextField(
            key: const Key('model'),
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model',
              helperText: 'Empty means ${session.spec!.defaultModel}',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveModel(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _saveModel, child: const Text('Save model')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notes folder'),
            subtitle: SelectableText(session.paths.notes.path),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: session.logout, child: const Text('Log out')),
          ),
          const Text('Logging out forgets the API key on this device. Your notes stay.'),
        ],
      ),
    );
  }
}
