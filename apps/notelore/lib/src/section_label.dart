import 'dart:math';

import 'package:flutter/material.dart';

import 'strings.dart';
import 'theme.dart';

/// The width a label leaves beside it: star 9, gaps 6 and 12, and 37 for the rest.
const double _beside = 64;

/// A section's heading: a star and its name in mono capitals, then a hairline
/// fading to the right. Screen readers hear the name as written.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    required this.strings,
    this.late = false,
    this.padding = const EdgeInsets.fromLTRB(0, Gap.m, 0, Gap.s),
    this.trailing,
    super.key,
  });

  /// Shown at the end in place of the hairline.
  final Widget? trailing;

  final String text;
  final Strings strings;

  /// Over things already late: in the error colour.
  final bool late;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.extension<NoteloreTokens>()!.label.copyWith(
      color: late ? colors.error : colors.primary,
    );
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Star(style.color!),
              const SizedBox(width: 6),
              // As wide as its words, wrapping before the line runs out (large text).
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: max(0, box.maxWidth - _beside)),
                child: Text(strings.caps(text), semanticsLabel: text, style: style),
              ),
              const SizedBox(width: 12),
              Expanded(
                child:
                    trailing ??
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.outlineVariant,
                            colors.outlineVariant.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small mono section label in the accent, after the look's star.
class Label extends StatelessWidget {
  const Label(this.text, {this.size, super.key});

  final String text;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).extension<NoteloreTokens>()!.label.copyWith(fontSize: size);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Gap.s,
      children: [
        Star(style.color!),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

/// The look's four-pointed star, drawn: no bundled font has the glyph.
class Star extends StatelessWidget {
  const Star(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(9), painter: _StarPainter(color));
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h / 2);
    final path = Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(c.dx, c.dy, w, h / 2)
      ..quadraticBezierTo(c.dx, c.dy, w / 2, h)
      ..quadraticBezierTo(c.dx, c.dy, 0, h / 2)
      ..quadraticBezierTo(c.dx, c.dy, w / 2, 0);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}
