import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/poster_tile.dart';
import '../widgets/tile.dart';

final _searchHomeProvider = FutureProvider.autoDispose<SearchHome>(
  (ref) => Api.i.searchHome(),
);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.takeFocus = false});
  final String? initialQuery;

  /// Whether the field claims focus as soon as this screen is built.
  ///
  /// False inside the shell: its destinations live in an IndexedStack, so
  /// every one of them is built and alive at launch. A field that autofocused
  /// there took the caret the moment the app opened, while the home tiles
  /// were the thing on screen. The shell asks for focus with [focusField]
  /// when search actually becomes the destination.
  final bool takeFocus;

  @override
  ConsumerState<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  Timer? _debounce;
  String _query = '';
  int _typeFilter = 0; // 0 all · 1 movies · 2 series

  List<Subject> _results = const [];
  List<String> _suggestions = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _run(q);
    }
  }

  /// Put the caret in the field. Called by the shell when the viewer moves to
  /// the search destination.
  void focusField() {
    if (!mounted) return;
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 900) {
      _more();
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _suggestions = const [];
        _error = null;
        _hasMore = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final s = await Api.i.suggest(value.trim());
      if (mounted && _controller.text.trim() == value.trim()) {
        setState(() => _suggestions = s);
      }
    });
  }

  Future<void> _run(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    _focus.unfocus();
    ref.read(recentSearchProvider.notifier).add(q);
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _suggestions = const [];
      _page = 1;
      _results = const [];
    });
    try {
      final r = await Api.i.search(q, page: 1, subjectType: _typeFilter);
      if (!mounted) return;
      setState(() {
        _results = r.items;
        _hasMore = r.pager.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    setState(() => _loadingMore = true);
    try {
      final r = await Api.i.search(
        _query,
        page: _page + 1,
        subjectType: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _page += 1;
        _results = [..._results, ...r.items];
        _hasMore = r.pager.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
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
              padding: pad.copyWith(top: 12, bottom: 4),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    MetroIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'back',
                      size: l.isTV ? 52 : 42,
                      outlined: false,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: MetroField(
                      controller: _controller,
                      focusNode: _focus,
                      hint: 'search films and series',
                      autofocus: widget.takeFocus,
                      onChanged: _onChanged,
                      onSubmitted: _run,
                      onClear: () => setState(() {
                        _query = '';
                        _results = const [];
                        _suggestions = const [];
                      }),
                    ),
                  ),
                ],
              ),
            ),

            // type filter — three words, the active one white
            Padding(
              padding: pad.copyWith(top: 10, bottom: 6),
              child: Row(
                children: [
                  for (final (i, label) in const [
                    (0, 'everything'),
                    (1, 'films'),
                    (2, 'series'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: DZ.gap),
                      child: MetroButton(
                        label: label,
                        dense: true,
                        chevron: false,
                        primary: _typeFilter == i,
                        onPressed: () {
                          setState(() => _typeFilter = i);
                          if (_query.isNotEmpty) _run(_query);
                        },
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _suggestions.isNotEmpty && _query.isEmpty
                  ? _Suggestions(
                      items: _suggestions,
                      padding: pad,
                      onPick: (s) {
                        _controller.text = s;
                        _run(s);
                      },
                    )
                  : _query.isEmpty
                  ? _StartPage(
                      padding: pad,
                      onPick: (s) {
                        _controller.text = s;
                        _run(s);
                      },
                    )
                  : _Results(
                      padding: pad,
                      query: _query,
                      results: _results,
                      loading: _loading,
                      loadingMore: _loadingMore,
                      error: _error,
                      scroll: _scroll,
                      onRetry: () => _run(_query),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.items,
    required this.padding,
    required this.onPick,
  });

  final List<String> items;
  final EdgeInsets padding;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: padding.copyWith(top: 8),
    itemCount: items.length,
    itemBuilder: (context, i) => InkWell(
      onTap: () => onPick(items[i]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.north_west, size: 16, color: DZ.grey2),
            const SizedBox(width: 12),
            Expanded(child: Text(items[i].toLowerCase(), style: DZ.body)),
          ],
        ),
      ),
    ),
  );
}

/// The start page: what everyone is searching for, what the viewer searched
/// before, and the catalog's own top lists.
class _StartPage extends ConsumerWidget {
  const _StartPage({required this.padding, required this.onPick});

  final EdgeInsets padding;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final home = ref.watch(_searchHomeProvider);
    final recent = ref.watch(recentSearchProvider);

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, bottom: 10),
          child: GiantWord('find'),
        ),
        if (recent.isNotEmpty) ...[
          SectionHead(
            label: 'you searched for',
            topGap: 16,
            trailing: GestureDetector(
              onTap: () => ref.read(recentSearchProvider.notifier).clear(),
              child: Text(
                'clear',
                style: l.t(DZ.caption).copyWith(color: DZ.grey2),
              ),
            ),
          ),
          Wrap(
            spacing: DZ.gap,
            runSpacing: DZ.gap,
            children: [
              for (final r in recent)
                MetroButton(
                  label: r,
                  dense: true,
                  chevron: false,
                  onPressed: () => onPick(r),
                ),
            ],
          ),
        ],
        home.when(
          loading: () => const LoadingBlock(label: 'loading suggestions'),
          error: (e, _) => StateBlock(
            headline: 'suggestions are unavailable',
            detail: 'You can still search by typing a title above.',
          ),
          data: (h) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (h.everyoneSearch.isNotEmpty) ...[
                const SectionHead(label: 'everyone is searching'),
                Wrap(
                  spacing: DZ.gap,
                  runSpacing: DZ.gap,
                  children: [
                    for (final t in h.everyoneSearch.take(14))
                      MetroButton(
                        label: t,
                        dense: true,
                        chevron: false,
                        onPressed: () => onPick(t),
                      ),
                  ],
                ),
              ],
              for (final group in h.hot)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHead(
                      label: group.name.isEmpty ? group.category : group.name,
                    ),
                    SizedBox(
                      height: l.columnWidth * 1.5,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: group.items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: DZ.gap),
                        itemBuilder: (context, i) => SizedBox(
                          width: l.columnWidth,
                          child: PosterTile(
                            subject: group.items[i],
                            onTap: () => Nav.openTitle(context, group.items[i]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.padding,
    required this.query,
    required this.results,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.scroll,
    required this.onRetry,
  });

  final EdgeInsets padding;
  final String query;
  final List<Subject> results;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final ScrollController scroll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);

    if (loading) {
      return Padding(
        padding: padding,
        child: const LoadingBlock(label: 'searching'),
      );
    }
    if (error != null) {
      return Padding(
        padding: padding,
        child: StateBlock(
          headline: 'the search did not go through',
          detail: error,
          actionLabel: 'try again',
          onAction: onRetry,
        ),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: padding,
        child: StateBlock(
          headline: 'nothing matched "$query"',
          detail:
              'Try a shorter phrase, the original-language title, or check '
              'the spelling. This catalog indexes titles, not actors.',
        ),
      );
    }

    return GridView.builder(
      controller: scroll,
      padding: padding.copyWith(top: 10, bottom: 48 + l.overscan.bottom),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: l.columns,
        mainAxisSpacing: DZ.gap,
        crossAxisSpacing: DZ.gap,
        childAspectRatio: 1 / 1.5,
      ),
      itemCount: results.length + (loadingMore ? l.columns : 0),
      itemBuilder: (context, i) {
        if (i >= results.length) return TileSkeleton(delayIndex: i);
        return PosterTile(
          subject: results[i],
          onTap: () => Nav.openTitle(context, results[i]),
        );
      },
    );
  }
}
