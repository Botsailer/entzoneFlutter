import 'package:material_ui/material_ui.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/tile.dart';
import 'player_screen.dart' show PlayerSheet;

/// The gesture layer over the picture.
///
/// Tap toggles the chrome. On desktop, a double click toggles fullscreen. On
/// touch devices, a double tap on the left or right third skips by the user's
/// own interval. Holding runs at the user's chosen speed and releases.
/// A vertical drag on the right half moves the volume.
class PlayerGestures extends StatefulWidget {
  const PlayerGestures({
    super.key,
    required this.locked,
    required this.skipSeconds,
    required this.onTap,
    required this.onDoubleTapLeft,
    required this.onDoubleTapRight,
    this.onDoubleTapFullscreen,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onVolumeDelta,
  });

  final bool locked;
  final int skipSeconds;
  final VoidCallback onTap;
  final VoidCallback onDoubleTapLeft;
  final VoidCallback onDoubleTapRight;
  final VoidCallback? onDoubleTapFullscreen;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final ValueChanged<double> onVolumeDelta;

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures> {
  Offset _last = Offset.zero;

  @override
  Widget build(BuildContext context) {
    if (widget.locked) {
      // Locked: the picture takes a tap to reveal the unlock control, nothing else.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (d) => _last = d.localPosition,
          onDoubleTapDown: (d) => _last = d.localPosition,
          onDoubleTap: () {
            if (widget.onDoubleTapFullscreen != null) {
              widget.onDoubleTapFullscreen!();
            } else if (_last.dx < w * 0.38) {
              widget.onDoubleTapLeft();
            } else if (_last.dx > w * 0.62) {
              widget.onDoubleTapRight();
            } else {
              widget.onTap();
            }
          },
          onLongPressStart: (_) => widget.onHoldStart(),
          onLongPressEnd: (_) => widget.onHoldEnd(),
          onLongPressCancel: widget.onHoldEnd,
          onVerticalDragUpdate: (d) {
            if (d.localPosition.dx < w * 0.5) return; // left half is reserved
            widget.onVolumeDelta(d.primaryDelta! / c.maxHeight);
          },
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// All the chrome: the top band, the centre transport, and the bottom bar with
/// the seek rule and every control the player offers.
class PlayerChrome extends StatelessWidget {
  const PlayerChrome({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.offline,
    required this.trailer,
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.speed,
    required this.qualityLabel,
    required this.fitLabel,
    required this.captionsOn,
    required this.hasNext,
    required this.autoNext,
    required this.skipSeconds,
    required this.volume,
    required this.onVolume,
    required this.onToggleMute,
    required this.canPip,
    this.onMinimize,
    this.onToggleMaximize,
    this.onToggleFullscreen,
    this.isMaximized = false,
    this.isFullscreen = false,
    required this.onClose,
    required this.onPlayPause,
    required this.onSkip,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onNext,
    required this.onToggleAutoNext,
    required this.onLock,
    required this.onFit,
    required this.onPip,
    required this.onSheet,
  });

  /// 0–100, as libmpv reports it.
  final double volume;
  final ValueChanged<double> onVolume;
  final VoidCallback onToggleMute;

  final bool visible;
  final String title;
  final String? subtitle;
  final bool offline;
  final bool trailer;
  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double speed;
  final String qualityLabel;
  final String fitLabel;
  final bool captionsOn;
  final bool hasNext;
  final bool autoNext;
  final int skipSeconds;
  final bool canPip;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onToggleFullscreen;
  final bool isMaximized;
  final bool isFullscreen;

  final VoidCallback onClose;
  final VoidCallback onPlayPause;
  final ValueChanged<int> onSkip;
  final VoidCallback onSeekStart;
  final ValueChanged<Duration> onSeekUpdate;
  final ValueChanged<Duration> onSeekEnd;
  final VoidCallback? onNext;
  final VoidCallback onToggleAutoNext;
  final VoidCallback onLock;
  final VoidCallback onFit;
  final VoidCallback onPip;
  final ValueChanged<PlayerSheet> onSheet;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final reduced = reducedMotion(context);
    final pad = 22.0 + (l.isTV ? 0 : 0);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
        curve: DZ.ease,
        child: Stack(
          children: [
            // ── top band ──
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                color: DZ.scrimLight,
                padding: EdgeInsets.only(
                  left: pad + l.overscan.left,
                  right: pad + l.overscan.right,
                  top: 14 + l.overscan.top,
                  bottom: 14,
                ),
                child: Row(
                  children: [
                    MetroIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'back',
                      outlined: false,
                      size: l.isTV ? 52 : 42,
                      onPressed: onClose,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title.toLowerCase(),
                            style: l.t(DZ.subtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: l.t(DZ.caption),
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                    if (offline)
                      const TileBadge(text: 'offline', fill: DZ.magenta),
                    if (trailer) ...[
                      const SizedBox(width: 8),
                      const TileBadge(text: 'trailer', fill: DZ.amber),
                    ],
                    if (canPip) ...[
                      const SizedBox(width: 10),
                      MetroIconButton(
                        icon: Icons.picture_in_picture_alt_outlined,
                        tooltip: 'picture in picture',
                        outlined: false,
                        size: l.isTV ? 52 : 42,
                        onPressed: onPip,
                      ),
                    ],
                    if (onMinimize != null) ...[
                      const SizedBox(width: 8),
                      MetroIconButton(
                        icon: Icons.minimize,
                        tooltip: 'minimize window',
                        outlined: false,
                        size: 42,
                        onPressed: onMinimize,
                      ),
                      MetroIconButton(
                        icon: isMaximized
                            ? Icons.filter_none
                            : Icons.crop_square,
                        tooltip: isMaximized
                            ? 'restore window'
                            : 'maximize window',
                        outlined: false,
                        size: 42,
                        onPressed: onToggleMaximize,
                      ),
                      MetroIconButton(
                        icon: isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        tooltip: isFullscreen
                            ? 'exit fullscreen'
                            : 'fullscreen',
                        outlined: false,
                        size: 42,
                        onPressed: onToggleFullscreen,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── centre transport ──
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkipButton(
                    seconds: skipSeconds,
                    forward: false,
                    onPressed: () => onSkip(-skipSeconds),
                  ),
                  SizedBox(width: l.isTV ? 72 : 44),
                  _PlayButton(playing: playing, onPressed: onPlayPause),
                  SizedBox(width: l.isTV ? 72 : 44),
                  _SkipButton(
                    seconds: skipSeconds,
                    forward: true,
                    onPressed: () => onSkip(skipSeconds),
                  ),
                ],
              ),
            ),

            // ── bottom bar ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: DZ.scrimLight,
                padding: EdgeInsets.only(
                  left: pad + l.overscan.left,
                  right: pad + l.overscan.right,
                  top: 10,
                  bottom: 12 + l.overscan.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(
                            formatTime(position.inSeconds),
                            style: l.t(DZ.caption).copyWith(color: DZ.white),
                          ),
                        ),
                        Expanded(
                          child: SeekRule(
                            position: position,
                            duration: duration,
                            buffered: buffered,
                            onStart: onSeekStart,
                            onUpdate: onSeekUpdate,
                            onEnd: onSeekEnd,
                          ),
                        ),
                        SizedBox(
                          width: 66,
                          child: Text(
                            formatTime(duration.inSeconds),
                            style: l.t(DZ.caption).copyWith(color: DZ.white),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Wraps rather than scrolls. A horizontal scroll view
                    // advertises nothing on a pointer, and the control it
                    // pushed out of reach first was quality — the one the bar
                    // exists for. A second line of chips costs 44px and keeps
                    // every action on screen.
                    Wrap(
                      runSpacing: DZ.gap,
                      children: [
                        if (!l.isTV)
                          _BarAction(
                            icon: Icons.lock_outline,
                            label: 'lock',
                            onPressed: onLock,
                          ),
                        if (onNext != null)
                          _BarAction(
                            icon: Icons.skip_next,
                            label: 'next',
                            onPressed: onNext,
                          ),
                        _BarAction(
                          icon: autoNext
                              ? Icons.repeat_on_outlined
                              : Icons.repeat,
                          label: 'auto-next ${autoNext ? 'on' : 'off'}',
                          active: autoNext,
                          onPressed: onToggleAutoNext,
                        ),
                        _BarAction(
                          icon: Icons.closed_caption_outlined,
                          label: 'subtitles',
                          active: captionsOn,
                          onPressed: () => onSheet(PlayerSheet.captions),
                        ),
                        VolumeControl(
                          volume: volume,
                          onChanged: onVolume,
                          onToggleMute: onToggleMute,
                        ),
                        _BarAction(
                          icon: Icons.graphic_eq,
                          label: 'audio track',
                          onPressed: () => onSheet(PlayerSheet.audio),
                        ),
                        _BarAction(
                          icon: Icons.speed,
                          label: speed == 1 ? 'speed' : '${speed}x',
                          active: speed != 1,
                          onPressed: () => onSheet(PlayerSheet.speed),
                        ),
                        _BarAction(
                          icon: Icons.aspect_ratio,
                          label: fitLabel,
                          onPressed: onFit,
                        ),
                        _BarAction(
                          icon: Icons.forward_10,
                          label: 'skip ${skipSeconds}s',
                          onPressed: () => onSheet(PlayerSheet.settings),
                        ),
                        _BarAction(
                          icon: Icons.high_quality_outlined,
                          label: qualityLabel,
                          strong: true,
                          onPressed: () => onSheet(PlayerSheet.quality),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The seek rule. A flat track, a flat buffered run, a flat played run, and a
/// square handle — no rounded caps, no glow, no tooltip bubble.
class SeekRule extends StatefulWidget {
  const SeekRule({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final VoidCallback onStart;
  final ValueChanged<Duration> onUpdate;
  final ValueChanged<Duration> onEnd;

  @override
  State<SeekRule> createState() => _SeekRuleState();
}

class _SeekRuleState extends State<SeekRule> {
  double? _dragRatio;
  bool _hovered = false;

  double get _ratio {
    if (_dragRatio != null) return _dragRatio!;
    final d = widget.duration.inMilliseconds;
    if (d <= 0) return 0;
    return (widget.position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  Duration _at(double ratio) => Duration(
    milliseconds: (widget.duration.inMilliseconds * ratio.clamp(0.0, 1.0))
        .round(),
  );

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final d = widget.duration.inMilliseconds;
    final buffered = d <= 0
        ? 0.0
        : (widget.buffered.inMilliseconds / d).clamp(0.0, 1.0);
    final thick = (_hovered || _dragRatio != null) ? 6.0 : (l.isTV ? 5.0 : 3.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          void report(double dx, void Function(Duration) f) =>
              f(_at((dx / w).clamp(0.0, 1.0)));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (e) {
              widget.onStart();
              setState(
                () => _dragRatio = (e.localPosition.dx / w).clamp(0.0, 1.0),
              );
              report(e.localPosition.dx, widget.onUpdate);
            },
            onHorizontalDragUpdate: (e) {
              setState(
                () => _dragRatio = (e.localPosition.dx / w).clamp(0.0, 1.0),
              );
              report(e.localPosition.dx, widget.onUpdate);
            },
            onHorizontalDragEnd: (_) {
              final r = _dragRatio;
              setState(() => _dragRatio = null);
              if (r != null) widget.onEnd(_at(r));
            },
            onTapDown: (e) {
              widget.onStart();
              report(e.localPosition.dx, widget.onEnd);
            },
            child: SizedBox(
              height: 30,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // track
                  Align(
                    alignment: Alignment.center,
                    child: Container(height: thick, color: DZ.grey4),
                  ),
                  // buffered
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: thick,
                      width: w * buffered,
                      color: DZ.grey3,
                    ),
                  ),
                  // played
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: thick,
                      width: w * _ratio,
                      color: DZ.cyan,
                    ),
                  ),
                  // handle — a square, because this world has no circles
                  Positioned(
                    left: (w * _ratio - 6).clamp(0.0, w - 12),
                    child: AnimatedContainer(
                      duration: reducedMotion(context)
                          ? Duration.zero
                          : DZ.stateChange,
                      width: (_hovered || _dragRatio != null) ? 12 : 10,
                      height: (_hovered || _dragRatio != null) ? 20 : 14,
                      color: DZ.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final side = l.isTV ? 96.0 : 72.0;
    return MetroTile(
      fill: DZ.cyan,
      onTap: onPressed,
      autofocus: true,
      semanticLabel: playing ? 'pause' : 'play',
      child: SizedBox(
        width: side,
        height: side,
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          size: side * 0.5,
          color: inkOn(DZ.cyan),
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.seconds,
    required this.forward,
    required this.onPressed,
  });

  final int seconds;
  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final side = l.isTV ? 76.0 : 58.0;
    return MetroTile(
      onTap: onPressed,
      semanticLabel: '${forward ? 'forward' : 'back'} $seconds seconds',
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              forward ? Icons.refresh : Icons.refresh,
              size: side * 0.78,
              color: DZ.white,
            ),
            // The interval is the label: it changes with the setting, so the
            // control never lies about what it will do.
            Text(
              '$seconds',
              style: l
                  .t(DZ.caption)
                  .copyWith(
                    color: DZ.white,
                    fontVariations: const [FontVariation('wght', 700)],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: DZ.gap),
    child: MetroButton(
      label: label,
      icon: icon,
      chevron: false,
      dense: true,
      primary: active || strong,
      fill: active ? DZ.cyan : DZ.grey4,
      onPressed: onPressed,
    ),
  );
}

/// Mute plus a level, sized and bordered to sit in the chip row as one more
/// chip. The level is the seek rule's language at a smaller scale: a flat
/// track, a flat fill, a square handle.
///
/// The app had volume on the arrow keys and on a vertical drag over the right
/// half of the picture, and nothing a pointer or a thumb could find. Those two
/// still work; this is the one you can see.
class VolumeControl extends StatefulWidget {
  const VolumeControl({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onToggleMute,
  });

  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  bool _hovered = false;
  bool _dragging = false;

  IconData get _icon {
    if (widget.volume == 0) return Icons.volume_off_outlined;
    if (widget.volume < 34) return Icons.volume_mute_outlined;
    if (widget.volume < 67) return Icons.volume_down_outlined;
    return Icons.volume_up_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final muted = widget.volume == 0;
    final height = 38.0 * (l.isTV ? 1.25 : 1.0);
    final trackWidth = l.isTV ? 120.0 : 84.0;
    final ratio = (widget.volume / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(right: DZ.gap),
      child: Container(
        height: height,
        // Transparent over a white hairline, exactly as the outlined chips
        // beside it are drawn, so the row reads as one run of controls.
        decoration: BoxDecoration(
          border: Border.all(color: DZ.white, width: DZ.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: muted ? 'unmute' : 'mute',
              child: Tooltip(
                message: muted ? 'unmute' : 'mute',
                child: InkWell(
                  onTap: widget.onToggleMute,
                  child: SizedBox(
                    width: height,
                    height: height,
                    child: Icon(
                      _icon,
                      size: 18,
                      color: muted ? DZ.grey2 : DZ.white,
                    ),
                  ),
                ),
              ),
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Semantics(
                slider: true,
                label: 'volume',
                value: '${widget.volume.round()}%',
                onIncrease: () => widget.onChanged(widget.volume + 5),
                onDecrease: () => widget.onChanged(widget.volume - 5),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) =>
                      setState(() => _dragging = true),
                  onHorizontalDragUpdate: (e) =>
                      widget.onChanged((e.localPosition.dx / trackWidth) * 100),
                  onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                  onTapDown: (e) =>
                      widget.onChanged((e.localPosition.dx / trackWidth) * 100),
                  child: SizedBox(
                    width: trackWidth,
                    height: height,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(height: 3, color: DZ.grey3),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 3,
                            width: trackWidth * ratio,
                            color: muted ? DZ.grey2 : DZ.cyan,
                          ),
                        ),
                        Positioned(
                          left: (trackWidth * ratio - 5).clamp(
                            0.0,
                            trackWidth - 10,
                          ),
                          child: AnimatedContainer(
                            duration: reducedMotion(context)
                                ? Duration.zero
                                : DZ.stateChange,
                            width: 10,
                            height: (_hovered || _dragging) ? 18 : 14,
                            color: muted ? DZ.grey2 : DZ.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Locked: only the way out.
class LockedChrome extends StatelessWidget {
  const LockedChrome({
    super.key,
    required this.visible,
    required this.onUnlock,
  });

  final bool visible;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reducedMotion(context) ? Duration.zero : DZ.stateChange,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 30 + l.overscan.left),
            child: MetroButton(
              label: 'unlock',
              icon: Icons.lock_open,
              chevron: false,
              onPressed: onUnlock,
            ),
          ),
        ),
      ),
    );
  }
}

/// Buffering. Metro's travelling squares, centred on the picture.
class MetroBuffering extends StatelessWidget {
  const MetroBuffering({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 140, child: MetroLoading(width: 140));
}

class PlayerToast extends StatelessWidget {
  const PlayerToast({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: 104 + l.overscan.top),
        child: Container(
          color: DZ.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            message.toLowerCase(),
            style: l
                .t(DZ.caption)
                .copyWith(
                  color: DZ.black,
                  fontVariations: const [FontVariation('wght', 600)],
                ),
          ),
        ),
      ),
    );
  }
}

/// A stream that will not play. Names the problem and offers the two things
/// that can actually be done about it.
class PlayerError extends StatelessWidget {
  const PlayerError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return ColoredBox(
      color: DZ.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('this video stopped', style: l.t(DZ.title)),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: l.t(DZ.body).copyWith(color: DZ.grey1),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  'try again requests a fresh link. if the video host still '
                  'rejects it, try another title or come back later.',
                  style: l.t(DZ.caption),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    MetroButton(
                      label: 'try again',
                      primary: true,
                      chevron: false,
                      autofocus: true,
                      onPressed: onRetry,
                    ),
                    const SizedBox(width: DZ.gap),
                    MetroButton(
                      label: 'close',
                      chevron: false,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when an episode ends and auto-play is off — so the next one is still
/// one press away without turning the setting on.
class UpNextCard extends StatelessWidget {
  const UpNextCard({super.key, required this.onPlay, required this.onClose});

  final VoidCallback onPlay;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return ColoredBox(
      color: DZ.scrim,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('finished', style: l.t(DZ.title)),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MetroButton(
                  label: 'play next episode',
                  icon: Icons.skip_next,
                  primary: true,
                  chevron: false,
                  autofocus: true,
                  onPressed: onPlay,
                ),
                const SizedBox(width: DZ.gap),
                MetroButton(label: 'done', chevron: false, onPressed: onClose),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
