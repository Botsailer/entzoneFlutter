import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';

/// The signature move.
///
/// Metro's panorama is one wide surface sliding behind a fixed viewport, with
/// the *next* section's word always clipped into view at the right edge so the
/// surface promises more than it shows. In this app that mechanism carries the
/// control the user named as the one that must be easiest: **seasons are
/// panorama panes.** Moving from season 1 to season 2 is one flick, one D-pad
/// right, or one arrow key — never a dropdown, never a second screen.
///
/// The same control runs the home screen's categories, so the gesture a user
/// learns on the home screen is the gesture that switches seasons.
class Pivot extends StatefulWidget {
  const Pivot({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    required this.builder,
    this.style,
    this.padding = EdgeInsets.zero,
    this.headerGap = 14,
    this.keepAlive = true,
    this.trailing,
  });

  /// One lowercase word per pane.
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Builds the pane body for an index.
  final Widget Function(BuildContext context, int index) builder;

  final TextStyle? style;
  final EdgeInsets padding;
  final double headerGap;
  final bool keepAlive;

  /// Sits at the end of the header row — a count, a filter control.
  final Widget? trailing;

  @override
  State<Pivot> createState() => _PivotState();
}

class _PivotState extends State<Pivot> {
  late final PageController _pages = PageController(initialPage: widget.index);
  final _headerScroll = ScrollController();
  final _labelKeys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(Pivot old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      if (_pages.hasClients && _pages.page?.round() != widget.index) {
        final reduced = reducedMotion(context);
        if (reduced) {
          _pages.jumpToPage(widget.index);
        } else {
          _pages.animateToPage(
            widget.index,
            duration: DZ.paneSlide,
            curve: DZ.ease,
          );
        }
      }
      _revealLabel(widget.index);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  /// Keep the active word on screen, and keep the *next* one clipped into view
  /// rather than scrolled fully in — that peek is the whole point.
  void _revealLabel(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _labelKeys[i];
      final ctx = key?.currentContext;
      if (ctx == null || !_headerScroll.hasClients) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final headerBox = context.findRenderObject() as RenderBox?;
      if (headerBox == null) return;
      final dx = box.localToGlobal(Offset.zero, ancestor: headerBox).dx;
      final target = (_headerScroll.offset + dx - widget.padding.left).clamp(
        0.0,
        _headerScroll.position.maxScrollExtent,
      );
      if ((target - _headerScroll.offset).abs() < 2) return;
      if (reducedMotion(context)) {
        _headerScroll.jumpTo(target);
      } else {
        _headerScroll.animateTo(target, duration: DZ.paneSlide, curve: DZ.ease);
      }
    });
  }

  void _step(int delta) {
    final next = widget.index + delta;
    if (next < 0 || next >= widget.labels.length) return;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final style = widget.style ?? l.t(DZ.title);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.bracketRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
            _step(1),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── the header: lowercase words, the active one white ──
          SizedBox(
            height: (style.fontSize ?? 34) * 1.3,
            child: ListView.builder(
              controller: _headerScroll,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              // Never clip the trailing word — the peek is load-bearing.
              clipBehavior: Clip.none,
              itemCount:
                  widget.labels.length + (widget.trailing != null ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= widget.labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 18, top: 8),
                    child: widget.trailing,
                  );
                }
                final on = i == widget.index;
                final key = _labelKeys.putIfAbsent(i, GlobalKey.new);
                return Padding(
                  key: key,
                  padding: EdgeInsets.only(
                    right: i == widget.labels.length - 1 ? 0 : 22,
                  ),
                  child: _PivotLabel(
                    label: widget.labels[i],
                    on: on,
                    style: style,
                    onTap: () => widget.onChanged(i),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: widget.headerGap),

          // ── the panes ──
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.labels.length,
              onPageChanged: widget.onChanged,
              physics: const ClampingScrollPhysics(),
              allowImplicitScrolling: widget.keepAlive,
              itemBuilder: widget.builder,
            ),
          ),
        ],
      ),
    );
  }
}

class _PivotLabel extends StatefulWidget {
  const _PivotLabel({
    required this.label,
    required this.on,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool on;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  State<_PivotLabel> createState() => _PivotLabelState();
}

class _PivotLabelState extends State<_PivotLabel> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final reduced = reducedMotion(context);
    // Metro marks the active pivot by weight and value, not by an underline or
    // a pill. The focused one takes the live-state colour.
    final color = _focused
        ? DZ.cyan
        : widget.on
        ? DZ.white
        : DZ.grey2;

    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          selected: widget.on,
          button: true,
          label: widget.label,
          child: AnimatedDefaultTextStyle(
            duration: reduced ? Duration.zero : DZ.stateChange,
            curve: DZ.ease,
            style: widget.style.copyWith(
              color: color,
              fontVariations: [FontVariation('wght', widget.on ? 300 : 250)],
            ),
            child: Text(widget.label.toLowerCase(), maxLines: 1),
          ),
        ),
      ),
    );
  }
}

/// A screen's own word, set at poster scale and deliberately allowed to run off
/// the right edge. The crop is the point: it says the surface is wider than the
/// window, which is the promise the panorama keeps.
class GiantWord extends StatelessWidget {
  const GiantWord(
    this.word, {
    super.key,
    this.color = DZ.white,
    this.scale = 1.0,
    this.allowCrop = true,
  });

  final String word;
  final Color color;
  final double scale;

  /// Off on a narrow pane where the word would lose its first syllable.
  final bool allowCrop;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    // The ramp's poster step, pulled down on a phone where 96px would eat the
    // viewport, and pushed up on a TV where it is read from across a room.
    final base = switch (l.hands) {
      Hands.remote => 104.0,
      Hands.pointer => l.size.width >= 1200 ? 96.0 : 72.0,
      Hands.touch => l.size.width >= 600 ? 76.0 : 58.0,
    };
    final style = DZ.poster.copyWith(
      fontSize: base * scale,
      color: color,
      letterSpacing: -(base * scale) * 0.035,
    );

    final text = Text(
      word.toLowerCase(),
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: allowCrop ? TextOverflow.clip : TextOverflow.ellipsis,
    );

    if (!allowCrop) return text;

    // OverflowBox lets the word exceed the viewport without the layout
    // reporting an overflow — the crop is intentional, not a bug.
    return ClipRect(
      child: SizedBox(
        height: base * scale * 1.04,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: text,
        ),
      ),
    );
  }
}
