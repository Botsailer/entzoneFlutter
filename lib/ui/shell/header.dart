import 'package:material_ui/material_ui.dart';

import '../../core/device.dart';
import '../../core/textures.dart';
import '../../core/tokens.dart';
import '../widgets/controls.dart';

/// The destinations, in the order they appear in the band and the bar.
enum Dest { home, search, library, settings }

extension DestX on Dest {
  String get label => switch (this) {
    Dest.home => 'home',
    Dest.search => 'search',
    Dest.library => 'library',
    Dest.settings => 'you',
  };

  IconData get icon => switch (this) {
    Dest.home => Icons.home_outlined,
    Dest.search => Icons.search,
    Dest.library => Icons.bookmark_border,
    Dest.settings => Icons.person_outline,
  };
}

/// Which catalog the shell is showing. The structural counterpart of the
/// reference prototype's two-source switch, mapped onto something this product
/// actually has: the live catalog, and what is already on this device.
enum Source { catalog, device }

/// The header band.
///
/// Structure is a brand commitment, carried over from the reference prototype:
/// brand mark and name, a segmented source switch, text navigation with an
/// active mark, and a compact inline search field — all in one fixed band.
/// The treatment is this app's own: flat fields, 1px outlines, lowercase type.
///
/// Shown on desktop and TV. A phone gets the compact variant and puts
/// navigation in a bottom bar where a thumb can reach it.
class HeaderBand extends StatelessWidget {
  const HeaderBand({
    super.key,
    required this.dest,
    required this.onDest,
    required this.source,
    required this.onSource,
    required this.searchController,
    required this.onSearch,
    this.downloadCount = 0,
  });

  final Dest dest;
  final ValueChanged<Dest> onDest;
  final Source source;
  final ValueChanged<Source> onSource;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final int downloadCount;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final tight = l.size.width < 1080;

    return Container(
      height: l.isTV ? 96 : 76,
      padding: EdgeInsets.only(
        left: l.margin + l.overscan.left,
        right: l.margin + l.overscan.right,
        top: l.overscan.top * 0.4,
      ),
      decoration: const BoxDecoration(
        color: DZ.black,
        border: Border(
          bottom: BorderSide(color: DZ.grey4, width: DZ.hairline),
        ),
      ),
      child: Row(
        children: [
          // The band carries four committed elements, so none of them is
          // dropped when the window narrows — the brand gives up width first
          // and the field second, and nothing overflows the band.
          Flexible(flex: 2, child: _BrandMark(wordmark: l.size.width >= 900)),
          SizedBox(width: tight ? 20 : 38),
          _SourceSwitch(source: source, onChanged: onSource),
          const Spacer(),
          if (!tight) ...[
            for (final d in Dest.values)
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: _NavWord(
                  label: d.label,
                  on: dest == d,
                  badge: d == Dest.library && downloadCount > 0,
                  onTap: () => onDest(d),
                ),
              ),
            const SizedBox(width: 30),
          ] else ...[
            for (final d in Dest.values)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: MetroIconButton(
                  icon: d.icon,
                  tooltip: d.label,
                  active: dest == d,
                  size: 40,
                  badge: d == Dest.library && downloadCount > 0
                      ? DZ.magenta
                      : null,
                  onPressed: () => onDest(d),
                ),
              ),
            const SizedBox(width: 16),
          ],
          Flexible(
            flex: 3,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tight ? 190 : 280,
                minWidth: 104,
              ),
              child: MetroField(
                controller: searchController,
                hint: 'search titles',
                leading: Icons.search,
                onSubmitted: onSearch,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand mark and name. The mark is the dot-matrix patch the world already
/// owns, in the live-state colour — not a logo this app does not have.
class _BrandMark extends StatelessWidget {
  const _BrandMark({this.wordmark = true});

  /// Below a narrow band the mark stands alone. A wordmark clipped to
  /// "depre…" reads as a bug; the dot-matrix patch is the identity either way.
  final bool wordmark;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Semantics(
      header: true,
      label: 'depressedzone',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (wordmark) ...[
            Flexible(
              child: Text(
                'depressedzone',
                style: l
                    .t(DZ.subtitle)
                    .copyWith(
                      fontVariations: const [FontVariation('wght', 300)],
                    ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 11),
          ],
          const CornerDots(
            color: DZ.cyan,
            opacity: 1,
            cols: 3,
            rows: 3,
            cell: 5,
          ),
        ],
      ),
    );
  }
}

/// Two segmented buttons. The selected one takes a flat fill; the other is
/// bare. No radius, no divider, no pill.
class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({required this.source, required this.onChanged});

  final Source source;
  final ValueChanged<Source> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Semantics(
      label: 'catalog source',
      child: Container(
        height: l.isTV ? 44 : 36,
        decoration: const BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: DZ.grey3, width: DZ.hairline),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              label: 'catalog',
              on: source == Source.catalog,
              onTap: () => onChanged(Source.catalog),
            ),
            _Segment(
              label: 'on this device',
              on: source == Source.device,
              onTap: () => onChanged(Source.device),
              fill: DZ.magenta,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.on,
    required this.onTap,
    this.fill = DZ.cyan,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color fill;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final fg = widget.on
        ? inkOn(widget.fill)
        : _focused
        ? DZ.cyan
        : DZ.grey1;
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
          child: AnimatedContainer(
            duration: reducedMotion(context) ? Duration.zero : DZ.stateChange,
            curve: DZ.ease,
            padding: EdgeInsets.symmetric(horizontal: l.isTV ? 18 : 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.on ? widget.fill : Colors.transparent,
              border: _focused ? Border.all(color: DZ.cyan, width: 2) : null,
            ),
            child: Text(
              widget.label,
              style: l
                  .t(DZ.caption)
                  .copyWith(
                    color: fg,
                    fontVariations: const [FontVariation('wght', 600)],
                  ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// A navigation word. Active is white at a heavier weight with a flat cyan
/// rule beneath — the one place this app keeps the reference prototype's
/// underline, because the structure was a brand commitment.
class _NavWord extends StatefulWidget {
  const _NavWord({
    required this.label,
    required this.on,
    required this.onTap,
    this.badge = false,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool badge;

  @override
  State<_NavWord> createState() => _NavWordState();
}

class _NavWordState extends State<_NavWord> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final color = _focused || _hovered
        ? DZ.cyan
        : widget.on
        ? DZ.white
        : DZ.grey2;
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: l
                        .t(DZ.body)
                        .copyWith(
                          color: color,
                          fontVariations: [
                            FontVariation('wght', widget.on ? 600 : 400),
                          ],
                        ),
                  ),
                  if (widget.badge) ...[
                    const SizedBox(width: 6),
                    Container(width: 6, height: 6, color: DZ.magenta),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: reducedMotion(context)
                    ? Duration.zero
                    : DZ.stateChange,
                curve: DZ.ease,
                height: 2,
                width: widget.on ? 22 : 0,
                color: DZ.cyan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The phone's bottom bar: four outlined squares, the active one flooded with
/// the live-state colour. Drawn exactly as the world's component board shows it.
class BottomBar extends StatelessWidget {
  const BottomBar({
    super.key,
    required this.dest,
    required this.onDest,
    this.downloadCount = 0,
  });

  final Dest dest;
  final ValueChanged<Dest> onDest;
  final int downloadCount;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Container(
      color: DZ.black,
      padding: EdgeInsets.only(bottom: l.safe.bottom),
      child: Row(
        children: [
          for (final d in Dest.values)
            Expanded(
              child: _BarCell(
                dest: d,
                on: dest == d,
                badge: d == Dest.library && downloadCount > 0,
                onTap: () => onDest(d),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarCell extends StatefulWidget {
  const _BarCell({
    required this.dest,
    required this.on,
    required this.onTap,
    this.badge = false,
  });

  final Dest dest;
  final bool on;
  final VoidCallback onTap;
  final bool badge;

  @override
  State<_BarCell> createState() => _BarCellState();
}

class _BarCellState extends State<_BarCell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    final fg = on
        ? inkOn(DZ.cyan)
        : _focused
        ? DZ.cyan
        : DZ.white;
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
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
          selected: on,
          button: true,
          label: widget.dest.label,
          child: AnimatedContainer(
            duration: reducedMotion(context) ? Duration.zero : DZ.stateChange,
            curve: DZ.ease,
            height: 62,
            margin: const EdgeInsets.only(right: DZ.hairline),
            decoration: BoxDecoration(
              color: on ? DZ.cyan : Colors.transparent,
              border: Border.all(
                color: _focused ? DZ.cyan : (on ? DZ.cyan : DZ.grey3),
                width: _focused ? 2 : DZ.hairline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(widget.dest.icon, size: 21, color: fg),
                    if (widget.badge)
                      Positioned(
                        right: -4,
                        top: -2,
                        child: Container(
                          width: 7,
                          height: 7,
                          color: DZ.magenta,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  widget.dest.label,
                  style: DZ.caption.copyWith(color: fg),
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
