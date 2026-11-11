/// The Soft look's own controls, where a Material widget cannot take its
/// shape: the floating tab bar, the orb switch and radio, and press feedback.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// The bar's widest: the design's 360-point phone less its margins, so on a
  /// wider phone the tabs stay close instead of spreading out.
  static const double width = 328;

  /// The chosen tab's orb: nearly the bar's height.
  static const double orb = 46;

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
            child: Center(
              child: DecoratedBox(
                decoration: _barDecoration(colors),
                child: SizedBox(
                  height: height,
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.s),
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
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: SizedBox(
                height: SoftNavBar.orb,
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

/// The floating bar's soft edge, and its shadow: tinted by the accent by day,
/// a plain dark one at night.
ShapeDecoration _barDecoration(ColorScheme colors) => ShapeDecoration(
  color: colors.surfaceContainerLow,
  shape: softBorder(colors, BorderRadius.circular(SoftNavBar.height / 2)),
  shadows: [
    BoxShadow(
      color: colors.brightness == Brightness.light
          ? colors.primary.withValues(alpha: .3)
          : Colors.black,
      offset: const Offset(0, 12),
      blurRadius: 28,
      spreadRadius: -11,
    ),
  ],
);

/// A [softRound]'s circle, and how far it sits inside its 48-point target.
const softRoundSize = 38.0;
const softRoundInset = (48 - softRoundSize) / 2;

/// A header's icon button in the Soft look: a 38-point circle on the card
/// colour with a soft edge, padded out to a 48-point target.
ButtonStyle softRound(ColorScheme colors) => IconButton.styleFrom(
  fixedSize: const Size.square(softRoundSize),
  iconSize: 20,
  minimumSize: const Size.square(softRoundSize),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.padded,
  backgroundColor: colors.surfaceContainerLow,
  shape: softBorder(colors, BorderRadius.circular(softRoundSize / 2)),
);

/// A page's way back as a [softRound]; without [onPressed] it pops the route.
Widget softBack(BuildContext context, {VoidCallback? onPressed}) =>
    BackButton(style: softRound(Theme.of(context).colorScheme), onPressed: onPressed);

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
        border: value ? null : Border.all(color: colors.outline),
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
            color: value ? null : colors.outline,
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

/// A [ListTile] whose text runs past two lines in one block, as a long subtitle
/// does, gets its leading and trailing at the top beside the title; otherwise
/// they stay centred.
class TallTile extends StatefulWidget {
  const TallTile({required this.child, super.key});

  final Widget child;

  @override
  State<TallTile> createState() => _TallTileState();
}

class _TallTileState extends State<TallTile> {
  var _top = false;

  var _pending = false;

  // ListTile picks its alignment before it knows its height, and sizes can
  // only be read once layout is over: measure after the frame, apply in the next.
  void _laidOut(RenderBox box) {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted) return;
      final top = _longest(box) > 2;
      if (top != _top) setState(() => _top = top);
    });
  }

  static int _longest(RenderObject box) {
    var lines = 0;
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        final painter = TextPainter(
          text: node.text,
          textDirection: node.textDirection,
          textScaler: node.textScaler,
        )..layout(maxWidth: node.size.width);
        lines = max(lines, painter.computeLineMetrics().length);
        painter.dispose();
      }
      node.visitChildren(visit);
    }

    box.visitChildren(visit);
    return lines;
  }

  @override
  Widget build(BuildContext context) => ListTileTheme.merge(
    titleAlignment: _top ? ListTileTitleAlignment.top : null,
    child: _OnLayout(_laidOut, child: widget.child),
  );
}

class _OnLayout extends SingleChildRenderObjectWidget {
  const _OnLayout(this.onLayout, {required super.child});

  final ValueChanged<RenderBox> onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOnLayout(onLayout);

  @override
  void updateRenderObject(BuildContext context, _RenderOnLayout renderObject) =>
      renderObject.onLayout = onLayout;
}

class _RenderOnLayout extends RenderProxyBox {
  _RenderOnLayout(this.onLayout);

  ValueChanged<RenderBox> onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout(this);
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
        child: TallTile(
          child: ListTile(
            leading: secondary,
            title: title,
            subtitle: subtitle,
            enabled: enabled,
            onTap: enabled ? () => onChanged!(!value) : null,
            trailing: SoftSwitch(value: value, enabled: enabled),
          ),
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
