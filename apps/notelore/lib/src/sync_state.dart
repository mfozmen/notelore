import 'dart:async';

import 'package:flutter/material.dart';

import 'icons.dart';
import 'session.dart';
import 'settings.dart';
import 'theme.dart';

/// Where the notes' sync stands (#774): syncing, the last success or a
/// problem, beside the Notes title on a phone and at the rail's foot.
class SyncState extends StatefulWidget {
  const SyncState(this.session, {this.extended = true, super.key});

  final Session session;

  /// With the words; a compact rail shows the mark and a tooltip only.
  final bool extended;

  @override
  State<SyncState> createState() => _SyncStateState();
}

class _SyncStateState extends State<SyncState> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // The relative time moves on while the screen stays open.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    if (!session.driveConnected) return const SizedBox.shrink();
    late final IconData icon;
    late final String text;
    if (session.syncing) {
      icon = AppIcons.sync;
      text = s.syncingNow;
    } else if (session.syncFailed) {
      icon = AppIcons.cloudOff;
      text = s.syncFailed;
    } else if (session.lastSynced case final synced?) {
      icon = AppIcons.cloudDone;
      text = s.syncedAgo(session.clock().toUtc().difference(synced));
    } else {
      icon = AppIcons.cloud;
      text = s.syncNever;
    }
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: muted?.color),
        if (widget.extended) ...[
          const SizedBox(width: Gap.xs),
          Flexible(child: Text(text, style: muted)),
        ],
      ],
    );
    return Tooltip(
      message: text,
      child: InkWell(
        onTap: () => openSettingsSection(context, session, SettingsSection.sync),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs),
          child: Semantics(button: true, label: text, excludeSemantics: true, child: row),
        ),
      ),
    );
  }
}
