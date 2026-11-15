import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';

/// The one door in this interface.
///
/// A tile is a flat field — a saturated colour or a piece of artwork — with no
/// border, no radius and no shadow. Everything it needs to say is inside it.
///
/// Three behaviours, all from the world:
///  • **tilt** — pressing tips the tile in 3D toward the press point and
///    releases. This is Metro's one tactile signature and the only "animation"
///    an ordinary control gets.
///  • **focus flood** — a focused tile (D-pad or keyboard) is ringed in the
///    live-state colour and lifts. On a TV this is the entire navigation model,
///    so it is drawn thick enough to read from ten feet.
///  • **press-and-hold** — opens the tile's secondary action where one exists,
///    which is how a remote reaches a context menu with no right-click.
class MetroTile extends StatefulWidget {
  const MetroTile({
    super.key,
    required this.child,
    this.onTap,
    this.onHold,
    this.fill,
    this.semanticLabel,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.tilt = true,
    this.focusColor = DZ.cyan,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onHold;

  /// A flat colour field behind the child. Null means the child paints itself
  /// (artwork tiles do).
  final Color? fill;

  final String? semanticLabel;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool tilt;
  final Color focusColor;

  @override
  State<MetroTile> createState() => _MetroTileState();
}

class _MetroTileState extends State<MetroTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DZ.tiltPress,
    reverseDuration: DZ.tiltRelease,
  );

  /// Where the press landed, in -1..1 tile coordinates. Drives the tilt axis,
  /// so a corner press tips the corner and a centre press sinks the whole tile.
  Offset _point = Offset.zero;
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down(Offset local, Size size) {
    if (!widget.enabled) return;
    _point = Offset(
      ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
      ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
    );
    _c.forward();
  }

  void _up() => _c.reverse();

  void _activate() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = reducedMotion(context);
    final focusWidth = Device.i.isTV ? 4.0 : 2.0;

    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      enabled: widget.enabled,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled:
            widget.enabled && (widget.onTap != null || widget.onHold != null),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        mouseCursor: widget.enabled && widget.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          // A remote has no long-press; the menu key is how it reaches one.
          SingleActivator(LogicalKeyboardKey.contextMenu): _HoldIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonY): _HoldIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          _HoldIntent: CallbackAction<_HoldIntent>(
            onInvoke: (_) {
              widget.onHold?.call();
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _down(d.localPosition, size),
              onTapUp: (_) => _up(),
              onTapCancel: _up,
              onTap: widget.enabled ? _activate : null,
              onLongPress: widget.onHold == null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      widget.onHold!.call();
                    },
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final t = reduced || !widget.tilt
                      ? 0.0
                      : Curves.easeOut.transform(_c.value);
                  final m = Matrix4.identity()
                    ..setEntry(3, 2, 0.0014) // perspective
                    ..rotateX(-_point.dy * DZ.tiltMax * t)
                    ..rotateY(_point.dx * DZ.tiltMax * t)
                    ..scaleByDouble(1 - 0.018 * t, 1 - 0.018 * t, 1, 1);
                  return Transform(
                    alignment: Alignment.center,
                    transform: m,
                    child: child,
                  );
                },
                child: AnimatedContainer(
                  duration: reduced ? Duration.zero : DZ.stateChange,
                  curve: DZ.ease,
                  decoration: BoxDecoration(
                    color: widget.fill,
                    border: _focused
                        ? Border.all(
                            color: widget.focusColor,
                            width: focusWidth,
                          )
                        : _hovered
                        ? Border.all(color: DZ.white, width: DZ.hairline)
                        : null,
                  ),
                  foregroundDecoration: widget.enabled
                      ? null
                      // Disabled is a flat knock-down, not a colour change —
                      // this world has no tinting. One of the two declared
                      // scrim steps, never a value between them.
                      : const BoxDecoration(color: DZ.scrimLight),
                  child: ClipRect(child: widget.child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HoldIntent extends Intent {
  const _HoldIntent();
}

/// A tile that is a flat colour field with a giant numeral and a lowercase
/// label — Metro's own "live tile". The numeral is the magnitude, read as
/// extent before it is read as text.
class CountTile extends StatelessWidget {
  const CountTile({
    super.key,
    required this.label,
    required this.count,
    required this.fill,
    this.onTap,
    this.caption,
    this.autofocus = false,
  });

  final String label;
  final int count;
  final Color fill;
  final VoidCallback? onTap;
  final String? caption;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final ink = inkOn(fill);
    return MetroTile(
      fill: fill,
      onTap: onTap,
      autofocus: autofocus,
      semanticLabel: '$label, $count',
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count > 99 ? '99+' : '$count',
              style: l.t(DZ.numeral).copyWith(color: ink),
              maxLines: 1,
            ),
            const Spacer(),
            Text(
              label,
              style: l.t(DZ.body).copyWith(color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (caption != null)
              Text(
                caption!,
                // Hierarchy comes from the type ramp — caption against body —
                // not from fading the ink, which the ladder has no step for.
                style: l.t(DZ.caption).copyWith(color: ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// A flat progress rule, flush to a tile's bottom edge. Metro draws state as a
/// bar of colour, never as a ring or a percentage label.
class TileProgress extends StatelessWidget {
  const TileProgress({
    super.key,
    required this.ratio,
    this.color = DZ.cyan,
    this.height = 4,
    this.track = true,
  });

  final double ratio;
  final Color color;
  final double height;
  final bool track;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (track) const ColoredBox(color: DZ.grey4),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0.0, 1.0),
          child: ColoredBox(color: color),
        ),
      ],
    ),
  );
}

/// Small flat badge for a tile corner: "cam", "offline", "s2 · e4".
class TileBadge extends StatelessWidget {
  const TileBadge({super.key, required this.text, this.fill = DZ.white});

  final String text;
  final Color fill;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    color: fill,
    child: Text(
      text.toLowerCase(),
      style: DZ.label.copyWith(color: inkOn(fill), letterSpacing: 0.6),
      maxLines: 1,
    ),
  );
}

/// Metro's loading mark: a short run of squares travelling across the field.
/// It replaces the Material spinner everywhere a whole area is waiting.
class MetroLoading extends StatefulWidget {
  const MetroLoading({super.key, this.color = DZ.cyan, this.width = 120});

  final Color color;
  final double width;

  @override
  State<MetroLoading> createState() => _MetroLoadingState();
}

class _MetroLoadingState extends State<MetroLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) {
      return SizedBox(
        width: widget.width,
        height: 5,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: widget.width * 0.4,
            height: 5,
            color: widget.color,
          ),
        ),
      );
    }
    return SizedBox(
      width: widget.width,
      height: 5,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          children: List.generate(5, (i) {
            // Each square runs the width on its own phase, easing at both ends.
            final phase = (_c.value + i * 0.085) % 1.0;
            final eased = phase < 0.5
                ? Curves.easeIn.transform(phase * 2) * 0.5
                : 0.5 + Curves.easeOut.transform((phase - 0.5) * 2) * 0.5;
            return Positioned(
              left: eased * (widget.width - 5),
              child: Container(width: 5, height: 5, color: widget.color),
            );
          }),
        ),
      ),
    );
  }
}

/// The shimmer stand-in for a tile that has not loaded. A flat grey field that
/// pulses between two ladder steps — no gradient sweep, which this world bans.
class TileSkeleton extends StatefulWidget {
  const TileSkeleton({super.key, this.delayIndex = 0});
  final int delayIndex;

  @override
  State<TileSkeleton> createState() => _TileSkeletonState();
}

class _TileSkeletonState extends State<TileSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _c.value = (widget.delayIndex * 0.17) % 1.0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return const ColoredBox(color: DZ.grey4);
    return AnimatedBuilder(
      animation: _c,
      // A quantised two-step flip, not a lerp through greys the ladder does
      // not contain: the skeleton dwells on one declared grey, then the other.
      builder: (context, _) =>
          ColoredBox(color: _c.value < 0.5 ? DZ.grey4 : DZ.grey3),
    );
  }
}

/// Lays out a Metro field: a fixed column count, square cells, and children
/// that declare how many columns and rows they span. This is the grid the whole
/// app is built on — it is what makes one grammar work from 390px to a 4K TV.
class TileField extends StatelessWidget {
  const TileField({
    super.key,
    required this.children,
    this.columns,
    this.gap = DZ.gap,
  });

  final List<TileSpan> children;
  final int? columns;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final cols = columns ?? l.columns;
    return LayoutBuilder(
      builder: (context, c) {
        final cell = (c.maxWidth - gap * (cols - 1)) / cols;
        final placed = _pack(children, cols);
        final rows = placed.isEmpty
            ? 0
            : placed
                  .map((p) => p.row + p.span.rows)
                  .reduce((a, b) => a > b ? a : b);
        double extent(int n) => cell * n + gap * (n - 1);
        return SizedBox(
          height: rows == 0 ? 0 : extent(rows),
          child: Stack(
            children: [
              for (final p in placed)
                Positioned(
                  left: p.col * (cell + gap),
                  top: p.row * (cell + gap),
                  width: extent(math.min(p.span.cols, cols)),
                  height: extent(p.span.rows),
                  child: p.span.child,
                ),
            ],
          ),
        );
      },
    );
  }

  /// First-fit packing on a cell grid, the way the tile field is drawn on a
  /// Windows Phone start screen.
  ///
  /// A `Wrap` cannot do this: it lays a run out side by side and makes the run
  /// as tall as its tallest child, so every 1×1 tile standing beside the 2×2
  /// lead left the cell underneath it empty — an L-shaped void that grew with
  /// the window. Here a tile takes the first free block that holds it, so the
  /// small tiles fill in under their neighbours and the field has no holes.
  static List<_Placed> _pack(List<TileSpan> spans, int cols) {
    final grid = <List<bool>>[];
    final out = <_Placed>[];

    bool free(int row, int col, int w, int h) {
      for (var r = row; r < row + h; r++) {
        if (r >= grid.length) continue; // rows below the end are empty
        for (var c = col; c < col + w; c++) {
          if (grid[r][c]) return false;
        }
      }
      return true;
    }

    void occupy(int row, int col, int w, int h) {
      while (grid.length < row + h) {
        grid.add(List<bool>.filled(cols, false));
      }
      for (var r = row; r < row + h; r++) {
        for (var c = col; c < col + w; c++) {
          grid[r][c] = true;
        }
      }
    }

    for (final span in spans) {
      final w = math.min(span.cols, cols);
      final h = span.rows;
      var row = 0;
      var col = 0;
      var found = false;
      while (!found) {
        for (col = 0; col <= cols - w; col++) {
          if (free(row, col, w, h)) {
            found = true;
            break;
          }
        }
        if (!found) row++;
      }
      occupy(row, col, w, h);
      out.add(_Placed(span, row, col));
    }
    return out;
  }
}

class _Placed {
  const _Placed(this.span, this.row, this.col);
  final TileSpan span;
  final int row;
  final int col;
}

/// A child of a [TileField] and its span in grid cells.
class TileSpan {
  const TileSpan({required this.child, this.cols = 1, this.rows = 1});
  final Widget child;
  final int cols;
  final int rows;
}
