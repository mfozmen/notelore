import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';

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
          _DriveSection(session),
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

/// Connect, sync now, disconnect; or why there is no sync in this build.
class _DriveSection extends StatelessWidget {
  const _DriveSection(this.session);

  final Session session;

  Future<void> _connect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.connectDrive();
    } on SignInFailed catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!session.driveAvailable) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Google Drive'),
        subtitle: Text('Sync is not set up in this build.'),
      );
    }
    if (!session.driveConnected) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Google Drive'),
        subtitle: Text(session.syncStatus ?? 'Back up and sync your notes across your devices.'),
        trailing: FilledButton(onPressed: () => _connect(context), child: const Text('Connect')),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Google Drive'),
      subtitle: Text(session.syncing ? 'Syncing...' : session.syncStatus ?? 'Connected.'),
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: session.syncing ? null : session.syncNow,
          ),
          IconButton(
            tooltip: 'Disconnect Google Drive',
            icon: const Icon(Icons.link_off),
            onPressed: session.disconnectDrive,
          ),
        ],
      ),
    );
  }
}
