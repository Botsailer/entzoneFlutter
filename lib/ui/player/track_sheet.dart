import 'package:material_ui/material_ui.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';

/// One option in a player sheet.
class TrackOption {
  const TrackOption({
    required this.id,
    required this.label,
    this.detail,
    this.accent = DZ.cyan,
  });

  final String id;
  final String label;
  final String? detail;
  final Color accent;
}

/// The player's settings surface: a panel on the trailing edge listing one
/// group of choices. It slides in over the picture rather than replacing it,
/// so changing audio or captions never costs you the frame.
///
/// Deliberately not a Material dialog: a dialog would steal the whole screen
/// and this world has no rounded sheet.
class TrackSheet extends StatelessWidget {
  const TrackSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selectedId,
    required this.onSelect,
    required this.onClose,
    this.footer,
  });

  final String title;
  final List<TrackOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  /// An explanation under the list — why a list is empty, what a choice costs.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final width = (l.isTV ? 420.0 : 320.0).clamp(260.0, l.size.width * 0.86);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width.toDouble(),
          height: double.infinity,
          // A surface in this world is a fill or a 1px outline on black —
          // never a near-black of its own. The hairline is what separates the
          // panel from the picture behind it.
          decoration: const BoxDecoration(
            color: DZ.black,
            border: Border(
              left: BorderSide(color: DZ.white, width: DZ.hairline),
            ),
          ),
          padding: EdgeInsets.only(
            top: 24 + l.overscan.top,
            bottom: 16 + l.overscan.bottom,
            right: l.overscan.right,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 14, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title.toLowerCase(), style: l.t(DZ.subtitle)),
                    ),
                    _Close(onClose: onClose),
                  ],
                ),
              ),
              Expanded(
                child: options.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          'nothing to choose from for this video.',
                          style: l.t(DZ.body).copyWith(color: DZ.grey2),
                        ),
                      )
                    : ListView.builder(
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final o = options[i];
                          return _Row(
                            option: o,
                            selected: o.id == selectedId,
                            autofocus: o.id == selectedId,
                            onTap: () => onSelect(o.id),
                          );
                        },
                      ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  child: DefaultTextStyle(
                    style: l.t(DZ.caption),
                    child: footer!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Close extends StatelessWidget {
  const _Close({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'close',
    child: GestureDetector(
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.close, color: DZ.white, size: 22),
      ),
    ),
  );
}

class _Row extends StatefulWidget {
  const _Row({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.autofocus,
  });

  final TrackOption option;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final o = widget.option;
    final on = widget.selected;

    return FocusableActionDetector(
      autofocus: widget.autofocus,
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
          selected: on,
          inMutuallyExclusiveGroup: true,
          label: o.label,
          child: AnimatedContainer(
            duration: reducedMotion(context) ? Duration.zero : DZ.stateChange,
            curve: DZ.ease,
            padding: EdgeInsets.symmetric(
              horizontal: 22,
              vertical: l.isTV ? 16 : 13,
            ),
            decoration: BoxDecoration(
              color: _focused ? o.accent : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: on && !_focused ? o.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.label.toLowerCase(),
                        style: l
                            .t(DZ.body)
                            .copyWith(
                              color: _focused ? inkOn(o.accent) : DZ.white,
                              fontVariations: [
                                FontVariation('wght', on ? 600 : 400),
                              ],
                            ),
                      ),
                      if (o.detail != null)
                        Text(
                          o.detail!.toLowerCase(),
                          style: l
                              .t(DZ.caption)
                              .copyWith(
                                color: _focused ? inkOn(o.accent) : DZ.grey2,
                              ),
                        ),
                    ],
                  ),
                ),
                if (on)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: _focused ? inkOn(o.accent) : o.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
