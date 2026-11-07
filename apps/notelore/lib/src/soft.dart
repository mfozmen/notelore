/// The Soft look's own controls, where a Material widget cannot take its
/// shape: the floating tab bar, the orb switch and radio, and press feedback.
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'theme.dart';

/// A short dip in opacity and size while a finger is down, in place of a ripple.
class Pressed extends StatefulWidget {
  const Pressed({required this.child, super.key});

  final Widget child;

  @override
  State<Pressed> createState() => _PressedState();
}

class _PressedState extends State<Pressed> {
  var _down = false;

  void _set(bool down) => setState(() => _down = down);

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: pressFeedback(pressed: _down, child: widget.child),
  );
}

/// The phone's tab bar: a pill on the card colour floating over the page,
/// the chosen tab an orb with its icon and label, the others icons only.
/// Every tab keeps its label for screen readers and as a tooltip.
class SoftNavBar extends StatelessWidget {
  const SoftNavBar({
    required this.destinations,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The tab's icon, its icon when chosen, and its label.
  final List<(IconData, Duotone, String)> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  /// The bar's own height, without the fade over it and the system's inset.
  static const double height = 64;

  /// The fade over the bar, where the page scrolls out of sight.
  static const double fade = 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: Container(
            height: fade,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.surface.withValues(alpha: 0), colors.surface],
              ),
            ),
          ),
        ),
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m + bottom),
            child: DecoratedBox(
              decoration: softDecoration(colors, radius: height / 2, raised: true),
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.s + 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final (i, (icon, chosen, label)) in destinations.indexed)
                        _Tab(
                          icon: icon,
                          chosen: chosen,
                          label: label,
                          selected: i == selected,
                          onTap: () => onSelected(i),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.chosen,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Duotone chosen;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pill = selected
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: orbFill(colors),
              borderRadius: BorderRadius.circular(23),
              boxShadow: orbGlow(colors),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 18, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Gap.s,
                children: [
                  AppIcons.duo(chosen, size: 22, color: colors.onPrimary),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : SizedBox(width: 52, child: Icon(icon, size: 22, color: colors.onSurfaceVariant));
    final tab = Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        // An InkWell, not a bare gesture, so a keyboard can focus and press it.
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          highlightColor: Colors.transparent,
          child: Pressed(
            child: SizedBox(height: 48, child: Center(widthFactor: 1, child: pill)),
          ),
        ),
      ),
    );
    return selected ? Flexible(child: tab) : tab;
  }
}

/// A card's soft edge: a hairline, a light catching its top, and by day a
/// gentle shadow tinted by the accent; at night a faint glow inside instead.
ShapeDecoration softDecoration(ColorScheme colors, {required double radius, bool raised = false}) {
  final light = colors.brightness == Brightness.light;
  return ShapeDecoration(
    color: colors.surfaceContainerLow,
    shape: softBorder(colors, BorderRadius.circular(radius)),
    shadows: light
        ? [
            BoxShadow(
              color: colors.primary.withValues(alpha: raised ? .3 : .18),
              offset: Offset(0, raised ? 12 : 8),
              blurRadius: raised ? 28 : 20,
              spreadRadius: raised ? -10 : -12,
            ),
          ]
        : [
            if (raised)
              const BoxShadow(
                color: Colors.black,
                offset: Offset(0, 12),
                blurRadius: 28,
                spreadRadius: -12,
              ),
          ],
  );
}

/// The Soft switch's look: a sunken track and an orb for a knob. Its
/// [SoftSwitchTile] row is the target and says the state.
class SoftSwitch extends StatelessWidget {
  const SoftSwitch({required this.value, required this.enabled, super.key});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final track = Container(
      width: 50,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: value
            ? Color.alphaBlend(colors.primary.withValues(alpha: .22), colors.surfaceContainerLow)
            : colors.surface,
        border: value ? null : Border.all(color: colors.outlineVariant),
      ),
      child: AnimatedAlign(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: value ? orbFill(colors) : null,
            color: value ? null : Color.lerp(colors.onSurfaceVariant, colors.surface, .45),
            boxShadow: value
                ? orbGlow(colors, blur: 8, y: 2)
                : const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
        ),
      ),
    );
    return Opacity(opacity: enabled ? 1 : .45, child: track);
  }
}

/// [SwitchListTile]'s row with a [SoftSwitch]: the row toggles it, and a
/// screen reader hears the title, the subtitle and the state as one.
class SoftSwitchTile extends StatelessWidget {
  const SoftSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        child: ListTile(
          leading: secondary,
          title: title,
          subtitle: subtitle,
          enabled: enabled,
          onTap: enabled ? () => onChanged!(!value) : null,
          trailing: SoftSwitch(value: value, enabled: enabled),
        ),
      ),
    );
  }
}

/// A choice's mark: an orb with a white dot when chosen, a sunken ring when not.
class SoftRadio extends StatelessWidget {
  const SoftRadio({required this.selected, this.semanticLabel, super.key});

  final bool selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      checked: selected,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(
                shape: BoxShape.circle,
                gradient: orbFill(colors),
                boxShadow: orbGlow(colors, blur: 8, y: 2),
              )
            : BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerLow,
                border: Border.all(color: colors.outline),
              ),
        child: selected
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colors.onPrimary),
              )
            : null,
      ),
    );
  }
}
