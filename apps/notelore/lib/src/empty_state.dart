import 'package:flutter/material.dart';

import 'icons.dart';
import 'theme.dart';

/// One look for an empty screen (#721): a primary icon, a line of body text,
/// an optional hint, and its actions in a wrap.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.hint,
    this.actions = const [],
    super.key,
  });

  final Duotone icon;
  final String title;
  final String? hint;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(Gap.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcons.duo(icon, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: Gap.m),
          // A title can quote a long pasted search.
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge,
          ),
          if (hint case final hint?) ...[
            const SizedBox(height: Gap.s),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: Gap.m),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Gap.s,
              runSpacing: Gap.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
