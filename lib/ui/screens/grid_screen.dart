import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../data/progress.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/poster_tile.dart';
import '../widgets/tile.dart';

/// A paged field of titles behind any "see all". One screen serves every row
/// in the app because the row passes in its own loader.
class GridScreen extends ConsumerStatefulWidget {
  const GridScreen({super.key, required this.title, required this.loader});

  final String title;
  final Future<List<Subject>> Function(int page) loader;

  @override
  ConsumerState<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends ConsumerState<GridScreen> {
  final _scroll = ScrollController();
  final _items = <Subject>[];
  final _seen = <String>{};

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(first: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_exhausted || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 900) _load();
  }

  Future<void> _load({bool first = false}) async {
    setState(() {
      if (first) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = first ? 1 : _page + 1;
      final batch = await widget.loader(page);
      if (!mounted) return;
      // The catalog repeats entries across pages; de-duplicate rather than
      // showing the same poster twice.
      final fresh = batch.where((s) => _seen.add(s.subjectId)).toList();
      setState(() {
        _page = page;
        _items.addAll(fresh);
        _exhausted = batch.isEmpty || fresh.isEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = first ? e.toString() : null;
        _loading = false;
        _loadingMore = false;
        if (!first) _exhausted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final progress = ref.watch(progressProvider);
    final pad = EdgeInsets.only(
      left: l.margin + l.overscan.left,
      right: l.margin + l.overscan.right,
    );

    return Scaffold(
      backgroundColor: DZ.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: pad.copyWith(top: 10),
              child: Row(
                children: [
                  MetroIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'back',
                    size: l.isTV ? 52 : 42,
                    outlined: false,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  if (!_loading && _items.isNotEmpty)
                    Text('${_items.length}${_exhausted ? '' : '+'} titles',
                        style: l.t(DZ.caption)),
                ],
              ),
            ),
            Padding(
              padding: pad.copyWith(top: 4, bottom: 12),
              child: GiantWord(widget.title),
            ),
            Expanded(
              child: _loading
                  ? Padding(padding: pad, child: const LoadingBlock())
                  : _error != null
                      ? Padding(
                          padding: pad,
                          child: StateBlock(
                            headline: 'could not load this list',
                            detail: _error,
                            actionLabel: 'try again',
                            onAction: () => _load(first: true),
                          ),
                        )
                      : _items.isEmpty
                          ? Padding(
                              padding: pad,
                              child: const StateBlock(
                                headline: 'nothing in this list',
                                detail: 'The catalog returned no titles here.',
                              ),
                            )
                          : GridView.builder(
                              controller: _scroll,
                              padding: pad.copyWith(bottom: 48 + l.overscan.bottom),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: l.columns,
                                mainAxisSpacing: DZ.gap,
                                crossAxisSpacing: DZ.gap,
                                childAspectRatio: 1 / 1.5,
                              ),
                              itemCount:
                                  _items.length + (_loadingMore ? l.columns : 0),
                              itemBuilder: (context, i) {
                                if (i >= _items.length) {
                                  return TileSkeleton(delayIndex: i);
                                }
                                final s = _items[i];
                                return PosterTile(
                                  subject: s,
                                  autofocus: i == 0 && Device.i.isTV,
                                  progress: progress[progressKey(s.subjectId)],
                                  onTap: () => Nav.openTitle(context, s),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
