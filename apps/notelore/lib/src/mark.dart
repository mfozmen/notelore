/// Notelore's mark (#340, #568): a folded ribbon that forms an N, its left end
/// cut like a bookmark, on lagoon teal. One drawing for the app and for every
/// platform's icon (`tool/make_icons_test.dart`), so they never drift apart.
library;

import 'package:flutter/material.dart';

/// The mark's own colours: a brand, the same whatever palette the app wears.
abstract final class MarkColors {
  static const teal = Color(0xFF0D9488); // the lagoon palette's seed
  static const ribbon = Color(0xFFFFFFFF);
  static const fold = Color(0xFF5EC9BC);
  static const foldOnLight = Color(0xFF064E48);
}

/// The mark at [size]: on its rounded teal square, or the ribbon alone
/// ([badge] false) for a place that has its own background.
class NoteloreMark extends StatelessWidget {
  const NoteloreMark({this.size = 72, this.badge = true, super.key});

  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Notelore',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: MarkPainter(
            background: badge ? MarkColors.teal : null,
            ink: badge ? null : (dark ? MarkColors.ribbon : MarkColors.teal),
            fold: badge || dark ? MarkColors.fold : MarkColors.foldOnLight,
          ),
        ),
      ),
    );
  }
}

/// Draws the mark into its canvas: a [background] square (its corners rounded
/// by [radius], a share of the side) when given, and the ribbon within [inset]
/// (a share of the side on every edge). [mono] draws the ribbon's silhouette
/// alone, for Android's themed icons.
class MarkPainter extends CustomPainter {
  const MarkPainter({
    this.background,
    this.radius = 0.22,
    this.inset = 0.13,
    this.mono = false,
    this.ink,
    this.fold,
  });

  final Color? background;
  final double radius;
  final double inset;
  final bool mono;

  /// The ribbon's colour when the painter has no [background] of its own, such
  /// as Android's adaptive foreground over its teal layer.
  final Color? ink;

  /// The turned underside: a shade of [ink] on the badge, darker than the
  /// ribbon when it stands on a light surface.
  final Color? fold;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (background case final color?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * radius)),
        Paint()..color = color,
      );
    }
    // The ribbon in a 100-unit box, placed within the inset.
    final unit = side * (1 - 2 * inset) / 100;
    canvas
      ..save()
      ..translate(side * inset, side * inset)
      ..scale(unit);
    if (mono) {
      canvas.drawPath(_ribbon, Paint()..color = Colors.white);
    } else {
      canvas.drawPath(
        _ribbon,
        Paint()..color = ink ?? (background == null ? MarkColors.teal : MarkColors.ribbon),
      );
      canvas.drawPath(_fold, Paint()..color = fold ?? MarkColors.fold);
    }
    canvas.restore();
  }

  /// A bold N: the two uprights and the diagonal are one ribbon, its top-left
  /// end cut down the middle like a bookmark's notch.
  static final _ribbon = Path.combine(
    PathOperation.difference,
    Path.combine(
      PathOperation.union,
      Path()
        ..addRect(const Rect.fromLTRB(14, 12, 38, 88))
        ..addRect(const Rect.fromLTRB(62, 12, 86, 88)),
      Path()
        ..moveTo(14, 12)
        ..lineTo(38, 12)
        ..lineTo(86, 88)
        ..lineTo(62, 88)
        ..close(),
    ),
    Path()
      ..moveTo(14, 12)
      ..lineTo(29, 34)
      ..lineTo(44, 12)
      ..close(),
  );

  /// The underside of the ribbon where it turns into the right upright.
  static final _fold = Path()
    ..moveTo(62, 88)
    ..lineTo(62, 60)
    ..lineTo(86, 60)
    ..close();

  @override
  bool shouldRepaint(MarkPainter old) =>
      old.background != background ||
      old.inset != inset ||
      old.mono != mono ||
      old.ink != ink ||
      old.fold != fold ||
      old.radius != radius;
}
