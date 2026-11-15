import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';
import 'tile.dart';

/// Metro's two buttons, exactly as the system draws them: a saturated fill with
/// a chevron for the primary action, a 1px white outline for everything else.
/// No radius, no shadow, no elevation. Focus takes the live-state colour.
class MetroButton extends StatefulWidget {
  const MetroButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.fill,
    this.chevron = true,
    this.autofocus = false,
    this.expand = false,
    this.dense = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;

  /// Overrides the primary fill — magenta for a download, red for a delete.
  final Color? fill;

  final bool chevron;
  final bool autofocus;
  final bool expand;
  final bool dense;

  /// Marks an outlined button destructive: it takes the red of the ladder
  /// instead of white. Gives severity three legible steps — a white outline
  /// for an ordinary action, a red outline for a destructive one, a red fill
  /// for the one that cannot be undone.
  final bool danger;

  @override
  State<MetroButton> createState() => _MetroButtonState();
}

class _MetroButtonState extends State<MetroButton> {
  bool _focused = false;
  bool _hovered = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final enabled = widget.onPressed != null;
    final fill = widget.fill ?? DZ.cyan;
    final reduced = reducedMotion(context);

    final Color bg;
    final Color fg;
    final Color? border;

    if (widget.primary) {
      bg = enabled ? fill : DZ.grey4;
      fg = enabled ? inkOn(fill) : DZ.grey3;
      border = _focused ? DZ.white : null;
    } else {
      final rest = widget.danger ? DZ.red : DZ.white;
      bg = Colors.transparent;
      fg = !enabled
          ? DZ.grey3
          : _focused
          ? DZ.cyan
          : rest;
      border = !enabled
          ? DZ.grey3
          : _focused
          ? DZ.cyan
          : rest;
    }

    final height = (widget.dense ? 38.0 : DZ.control) * (l.isTV ? 1.25 : 1.0);

    final body = AnimatedContainer(
      duration: reduced ? Duration.zero : DZ.stateChange,
      curve: DZ.ease,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 18),
      decoration: BoxDecoration(
        color: _down && enabled && widget.primary ? _pressed(fill) : bg,
        border: border == null
            ? null
            : Border.all(
                color: border,
                width: _focused && l.isTV ? 3 : DZ.hairline,
              ),
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: widget.expand
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: l.isTV ? 22 : 18, color: fg),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  widget.label.toLowerCase(),
                  style: l
                      .t(widget.dense ? DZ.caption : DZ.body)
                      .copyWith(
                        color: fg,
                        fontVariations: const [FontVariation('wght', 600)],
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (widget.chevron && !_hovered) ...[
            SizedBox(width: widget.expand ? 12 : 10),
            Icon(Icons.chevron_right, size: l.isTV ? 22 : 18, color: fg),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onPressed!();
                }
              : null,
          child: body,
        ),
      ),
    );
  }

  /// Pressed state lightens the fill by the one declared step.
  Color _pressed(Color c) => Color.alphaBlend(DZ.pressWash, c);
}

/// A compact square control: the icon buttons in the nav rail and on the player
/// bar. Always a 1px outline; filled only when it is the active one.
class MetroIconButton extends StatefulWidget {
  const MetroIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 44,
    this.outlined = true,
    this.activeColor = DZ.cyan,
    this.autofocus = false,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final bool outlined;
  final Color activeColor;
  final bool autofocus;

  /// A flat dot in the corner — unread downloads, a new episode.
  final Color? badge;

  @override
  State<MetroIconButton> createState() => _MetroIconButtonState();
}

class _MetroIconButtonState extends State<MetroIconButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduced = reducedMotion(context);
    final on = widget.active;

    final bg = on ? widget.activeColor : Colors.transparent;
    final fg = !enabled
        ? DZ.grey3
        : on
        ? inkOn(widget.activeColor)
        : _focused || _hovered
        ? DZ.cyan
        : DZ.white;
    final border = !enabled
        ? DZ.grey3
        : _focused
        ? DZ.cyan
        : on
        ? widget.activeColor
        : DZ.white;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: on,
        label: widget.tooltip,
        child: FocusableActionDetector(
          enabled: enabled,
          autofocus: widget.autofocus,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed!();
                  }
                : null,
            child: AnimatedContainer(
              duration: reduced ? Duration.zero : DZ.stateChange,
              curve: DZ.ease,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: bg,
                border: widget.outlined
                    ? Border.all(
                        color: border,
                        width: _focused ? 2 : DZ.hairline,
                      )
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(widget.icon, size: widget.size * 0.45, color: fg),
                  if (widget.badge != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 7,
                        height: 7,
                        color: widget.badge,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A search field in the world's own vocabulary: a 1px outline that takes the
/// live-state colour on focus, lowercase placeholder, no fill, no radius.
class MetroField extends StatefulWidget {
  const MetroField({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.leading = Icons.search,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final IconData? leading;
  final VoidCallback? onClear;

  @override
  State<MetroField> createState() => _MetroFieldState();
}

class _MetroFieldState extends State<MetroField> {
  late final FocusNode _node = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_sync);
  }

  void _sync() {
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_sync);
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final has = widget.controller.text.isNotEmpty;
    return Container(
      height: DZ.control * (l.isTV ? 1.2 : 1.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: _focused ? DZ.cyan : DZ.white,
          width: _focused && l.isTV ? 3 : DZ.hairline,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            Icon(
              widget.leading,
              size: 18,
              color: _focused ? DZ.cyan : DZ.grey1,
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              autofocus: widget.autofocus,
              style: l.t(DZ.body),
              cursorColor: DZ.cyan,
              cursorWidth: 2,
              cursorRadius: Radius.zero,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onSubmitted,
              onChanged: (v) {
                setState(() {});
                widget.onChanged?.call(v);
              },
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hint.toLowerCase(),
                hintStyle: l.t(DZ.body).copyWith(color: DZ.grey2),
              ),
            ),
          ),
          if (has)
            MetroIconButton(
              icon: Icons.close,
              tooltip: 'clear',
              size: 28,
              outlined: false,
              onPressed: () {
                widget.controller.clear();
                widget.onChanged?.call('');
                widget.onClear?.call();
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

/// A lowercase section heading with a hairline rule running to the edge, as
/// the hero draws "recently played". More space above it than below.
class SectionHead extends StatelessWidget {
  const SectionHead({
    super.key,
    required this.label,
    this.trailing,
    this.onTap,
    this.color = DZ.cyan,
    this.topGap = DZ.sectionTop,
  });

  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toLowerCase(),
          style: l.t(DZ.subtitle).copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 14),
        const Expanded(child: Divider(height: 1, color: DZ.grey4)),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
        if (onTap != null) ...[
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, size: 22, color: color),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: topGap, bottom: DZ.sectionBottom),
      child: onTap == null
          ? head
          : Semantics(
              button: true,
              label: 'see all $label',
              child: InkWell(onTap: onTap, child: head),
            ),
    );
  }
}

/// Every non-content state the app can be in, in one shape: a lowercase line,
/// an optional explanation, and an optional action. No illustration, no icon
/// circle — this world says it in type.
class StateBlock extends StatelessWidget {
  const StateBlock({
    super.key,
    required this.headline,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.tone = DZ.grey1,
    this.compact = false,
  });

  final String headline;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 24 : 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            headline.toLowerCase(),
            style: l.t(compact ? DZ.subtitle : DZ.title).copyWith(color: tone),
          ),
          if (detail != null) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              // Body measure stays readable instead of running the full width
              // of a 4K TV.
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                detail!,
                style: l.t(DZ.body).copyWith(color: DZ.grey1),
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            MetroButton(
              label: actionLabel!,
              onPressed: onAction,
              primary: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// A whole area waiting. Metro's travelling squares, left-aligned with the
/// grid rather than centred in a void.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 46),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!.toLowerCase(), style: DZ.caption),
          const SizedBox(height: 14),
        ],
        const MetroLoading(),
      ],
    ),
  );
}

/// The toggle, drawn in this world's own vocabulary.
///
/// Material's Switch is a pill with a circular thumb — the only rounded thing
/// in an app whose system states there is no corner radius anywhere. This is
/// the Metro toggle instead: a 1px outlined rectangle that fills with the
/// live-state colour when it is on, and a square thumb that slides between
/// the two ends. Off is an outline on black; on is a saturated fill. There is
/// no third surface, which is the rule.
class MetroSwitch extends StatefulWidget {
  const MetroSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<MetroSwitch> createState() => _MetroSwitchState();
}

class _MetroSwitchState extends State<MetroSwitch> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final enabled = widget.onChanged != null;
    final on = widget.value;
    final reduced = reducedMotion(context);

    final scale = l.isTV ? 1.3 : 1.0;
    final trackW = 46.0 * scale;
    final trackH = 20.0 * scale;
    final thumb = 12.0 * scale;
    const inset = 3.0;

    final Color track = !enabled
        ? DZ.grey4
        : on
        ? DZ.cyan
        : Colors.transparent;
    final Color edge = !enabled
        ? DZ.grey3
        : _focused
        ? DZ.white
        : on
        ? DZ.cyan
        : DZ.grey1;
    // On the cyan fill the thumb must be the ink that reads on it; on black it
    // is the ink of the ground.
    final Color pip = !enabled
        ? DZ.grey3
        : on
        ? inkOn(DZ.cyan)
        : DZ.white;

    return Semantics(
      toggled: on,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onChanged?.call(!on);
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onChanged!(!on);
                }
              : null,
          // The drawn control is 20px tall; the target around it clears the
          // 48dp touch floor.
          child: SizedBox(
            height: DZ.control,
            width: trackW,
            child: Center(
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : DZ.stateChange,
                curve: DZ.ease,
                width: trackW,
                height: trackH,
                decoration: BoxDecoration(
                  color: track,
                  border: Border.all(
                    color: edge,
                    width: _focused ? 2 : DZ.hairline,
                  ),
                ),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: reduced ? Duration.zero : DZ.stateChange,
                      curve: DZ.ease,
                      alignment: on
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: inset),
                        child: SizedBox(
                          width: thumb,
                          height: thumb,
                          child: ColoredBox(color: pip),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
