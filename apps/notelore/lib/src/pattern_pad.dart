/// A 3×3 pattern of dots for the app lock (#295): drawn by dragging through
/// the dots, or by tapping them in turn and then Done (one pointer is enough,
/// no drag needed; each dot is a labelled button for a screen reader).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'strings.dart';
import 'theme.dart';

/// The fewest dots a pattern joins.
const minPatternDots = 4;

/// [dots] as the lock stores it: their numbers, 0 to 8, joined by dashes.
String patternOf(List<int> dots) => dots.join('-');

class PatternPad extends StatefulWidget {
  const PatternPad({
    required this.strings,
    required this.onDone,
    this.onTooShort,
    this.enabled = true,
    super.key,
  });

  final Strings strings;

  /// A finished pattern of at least [minPatternDots] dots, as [patternOf] writes it.
  final void Function(String pattern) onDone;

  /// A pattern drawn through fewer dots: nothing is tried, but the person hears why.
  final VoidCallback? onTooShort;
  final bool enabled;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final _dots = <int>[];
  final _box = GlobalKey();

  /// The finger, while it draws.
  Offset? _finger;
  var _drawing = false;

  /// The pad's side and each dot's touch target, from the screen's shorter
  /// side (a phone on its side, a split screen): at most 64 dp a dot, never
  /// under 44. Not from the parent's size: a dialog asks for intrinsic sizes.
  var _side = 240.0;
  double get _target => _side / 4;
  double get _gap => _side / 8;

  Offset _center(int dot) => Offset(
    (dot % 3) * (_target + _gap) + _target / 2,
    (dot ~/ 3) * (_target + _gap) + _target / 2,
  );

  int? _dotAt(Offset point) {
    for (var dot = 0; dot < 9; dot++) {
      if ((_center(dot) - point).distance <= _target / 2) return dot;
    }
    return null;
  }

  Offset _local(Offset global) =>
      (_box.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _add(int dot) {
    if (_dots.contains(dot)) return;
    setState(() => _dots.add(dot));
  }

  void _finish() {
    final dots = List.of(_dots);
    setState(() {
      _dots.clear();
      _finger = null;
    });
    if (dots.length >= minPatternDots) {
      widget.onDone(patternOf(dots));
    } else {
      widget.onTooShort?.call();
    }
  }

  void _clear() => setState(() {
    _dots.clear();
    _finger = null;
  });

  /// A finger that starts drawing on the pad. The immediate recognizer claims
  /// the drag at the touch slop, before a scroll around the pad can (#295).
  Drag? _startDrawing(Offset global) {
    if (_drawing) return null; // one finger draws
    _drawing = true;
    _clear();
    // The finger, followed by its moves: the first update brings the whole
    // way since the touch as one move, with the touch's own position.
    var point = _local(global);
    if (_dotAt(point) case final dot?) _add(dot);
    return _Drawing(
      onUpdate: (delta) {
        point += delta;
        setState(() => _finger = point);
        if (_dotAt(point) case final dot?) _add(dot);
      },
      onEnd: () {
        _drawing = false;
        _finish();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final colors = Theme.of(context).colorScheme;
    _side = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(176, 256);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // How many dots are chosen, for a screen reader (each dot says its own).
        Semantics(
          container: true,
          liveRegion: true,
          label: _dots.isEmpty ? null : s.patternDotsChosen(_dots.length),
          child: RawGestureDetector(
            key: const Key('pattern-pad'),
            gestures: {
              ImmediateMultiDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
                    ImmediateMultiDragGestureRecognizer.new,
                    (recognizer) => recognizer.onStart = widget.enabled ? _startDrawing : null,
                  ),
            },
            child: SizedBox.square(
              key: _box,
              dimension: _side,
              child: CustomPaint(
                painter: _Lines([for (final dot in _dots) _center(dot)], _finger, colors.primary),
                child: Stack(
                  children: [
                    for (var dot = 0; dot < 9; dot++)
                      Positioned(
                        left: _center(dot).dx - _target / 2,
                        top: _center(dot).dy - _target / 2,
                        child: _Dot(
                          label: s.patternDot(dot + 1),
                          size: _target,
                          selected: _dots.contains(dot),
                          onTap: widget.enabled ? () => _add(dot) : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.s),
        // Under each other when they do not fit beside (a narrow dialog, large text).
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Gap.s,
          runSpacing: Gap.xs,
          children: [
            // Only once there is something to clear; its room is kept, so nothing moves.
            Visibility(
              key: const Key('pattern-clear'),
              visible: _dots.isNotEmpty,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(
                onPressed: widget.enabled && _dots.isNotEmpty ? _clear : null,
                child: Text(s.clearPattern),
              ),
            ),
            FilledButton.tonal(
              onPressed: widget.enabled && _dots.length >= minPatternDots ? _finish : null,
              child: Text(s.patternDone),
            ),
          ],
        ),
      ],
    );
  }
}

/// A drag that draws: how far the finger moves, and when it lifts.
class _Drawing extends Drag {
  _Drawing({required this.onUpdate, required this.onEnd});

  final void Function(Offset delta) onUpdate;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.delta);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

/// One dot: a button that can be tapped. A chosen dot is larger, filled and
/// ringed, so it differs by more than colour; a disabled pad's dots are faint.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final idle = enabled ? colors.outline : colors.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              width: selected ? 26 : 14,
              height: selected ? 26 : 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colors.primary : idle,
                border: selected ? Border.all(color: colors.primaryContainer, width: 4) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line through the chosen dots, and on to the finger while it draws.
class _Lines extends CustomPainter {
  const _Lines(this.points, this.finger, this.color);

  final List<Offset> points;
  final Offset? finger;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in [...points.skip(1), ?finger]) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Lines old) => true; // a new path every frame it draws
}
