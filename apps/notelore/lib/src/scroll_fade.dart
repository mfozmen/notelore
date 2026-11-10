import 'dart:math';

import 'package:flutter/material.dart';

import 'soft.dart';

/// Fades a scrolling list out where it runs on under a pinned header or bar,
/// instead of a hard cut. It fades to transparent, not to a colour, so the
/// page's backdrop (its glow, a card's fill) shows through unchanged.
class ScrollFade extends StatefulWidget {
  const ScrollFade({required this.child, super.key});

  /// The scrolling list itself, so its own scrolling is the one followed.
  final Widget child;

  /// The alpha mask over a list [height] tall: clear at each faded edge.
  static LinearGradient mask({required bool above, required bool below, required double height}) {
    final fade = min(SoftNavBar.fade / height, 0.5);
    const shown = Colors.white;
    const gone = Color(0x00FFFFFF);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [above ? gone : shown, shown, shown, below ? gone : shown],
      stops: [0, fade, 1 - fade, 1],
    );
  }

  @override
  State<ScrollFade> createState() => ScrollFadeState();
}

class ScrollFadeState extends State<ScrollFade> {
  /// Some of the list is scrolled away above.
  bool get above => _above;
  var _above = false;

  /// More of the list is below.
  bool get below => _below;
  var _below = false;

  bool _scrolled(Notification event) {
    // The list's own scrolling only, not a field's or a row's inside it.
    final metrics = switch (event) {
      ScrollNotification(depth: 0, :final metrics) ||
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics == null) return false;
    final above = metrics.extentBefore > 0;
    final below = metrics.extentAfter > 0;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
    return false;
  }

  /// The list's position, shared with the desk scrollbar drawn above the mask.
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    // The behaviour's own scrollbar (none on a phone), moved above the mask so
    // its ends are not faded with the list.
    return behavior.buildScrollbar(
      context,
      NotificationListener<Notification>(
        onNotification: _scrolled,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) =>
              ScrollFade.mask(above: _above, below: _below, height: rect.height).createShader(rect),
          child: ScrollConfiguration(
            behavior: behavior.copyWith(scrollbars: false),
            // On every platform, so the list takes the controller the scrollbar follows.
            child: PrimaryScrollController(
              controller: _controller,
              automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
              child: widget.child,
            ),
          ),
        ),
      ),
      ScrollableDetails.vertical(controller: _controller),
    );
  }
}
