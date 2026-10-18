/// Notelore's mark (#340): a note you talk to. A white card with a folded
/// corner (the note) and a speech tail (the chat), two lines of writing on it,
/// on lagoon teal. One drawing for the app and for every platform's icon
/// (`tool/make_icons_test.dart`), so they never drift apart.
library;

import 'package:flutter/material.dart';

/// The mark's own colours: a brand, the same whatever palette the app wears.
abstract final class MarkColors {
  static const teal = Color(0xFF0D9488); // the lagoon palette's seed
  static const card = Color(0xFFFFFFFF);
  static const fold = Color(0xFF99E2D8);
}

/// The mark at [size]: on its rounded teal square, or the card alone ([badge]
/// false) for a place that has its own background.
class NoteloreMark extends StatelessWidget {
  const NoteloreMark({this.size = 72, this.badge = true, super.key});

  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Notelore',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: MarkPainter(background: badge ? MarkColors.teal : null)),
    ),
  );
}

/// Draws the mark into its canvas: a [background] square (its corners rounded
/// by [radius], a share of the side) when given, and the card within [inset]
/// (a share of the side on every edge). [mono] draws the card's shape alone,
/// the writing cut out, for Android's themed icons.
class MarkPainter extends CustomPainter {
  const MarkPainter({this.background, this.radius = 0.22, this.inset = 0.16, this.mono = false});

  final Color? background;
  final double radius;
  final double inset;
  final bool mono;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (background case final color?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * radius)),
        Paint()..color = color,
      );
    }
    // The card in a 100-unit box, placed within the inset.
    final unit = side * (1 - 2 * inset) / 100;
    canvas
      ..save()
      ..translate(side * inset, side * inset)
      ..scale(unit);
    if (mono) canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
    final ink = mono ? Colors.white : MarkColors.teal;
    canvas.drawPath(_card, Paint()..color = mono ? Colors.white : MarkColors.card);
    if (!mono) canvas.drawPath(_fold, Paint()..color = MarkColors.fold);
    final line = Paint()
      ..color = ink
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      // The writing is cut out of the themed icon's single colour.
      ..blendMode = mono ? BlendMode.clear : BlendMode.srcOver;
    canvas
      ..drawLine(const Offset(26, 36), const Offset(70, 36), line)
      ..drawLine(const Offset(26, 54), const Offset(54, 54), line);
    if (mono) canvas.restore();
    canvas.restore();
  }

  /// A rounded card with its top-right corner folded away, and a speech tail
  /// at its bottom-left.
  static final _card = Path.combine(
    PathOperation.union,
    Path.combine(
      PathOperation.difference,
      Path()..addRRect(RRect.fromLTRBR(10, 8, 90, 74, const Radius.circular(12))),
      Path()
        ..moveTo(62, 0)
        ..lineTo(100, 0)
        ..lineTo(100, 38)
        ..close(),
    ),
    Path()
      ..moveTo(22, 70)
      ..lineTo(16, 94)
      ..lineTo(42, 70)
      ..close(),
  );

  /// The folded-down corner.
  static final _fold = Path()
    ..moveTo(70, 8)
    ..lineTo(70, 22)
    ..quadraticBezierTo(70, 28, 76, 28)
    ..lineTo(90, 28)
    ..close();

  @override
  bool shouldRepaint(MarkPainter old) =>
      old.background != background ||
      old.inset != inset ||
      old.mono != mono ||
      old.radius != radius;
}
