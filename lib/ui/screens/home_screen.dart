import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/downloads.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../data/progress.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/poster_tile.dart';
import '../widgets/tile.dart';

/// The rows a category is built from, so a category is data rather than code.
class CategorySpec {
  const CategorySpec({required this.label, required this.rows, this.feedTab});

  final String label;
  final List<({String title, FilterQuery query})> rows;

  /// When set, the category is an operating feed from the catalog rather than
  /// a set of filter queries.
  final int? feedTab;
}

const _categories = <CategorySpec>[
  CategorySpec(label: 'for you', rows: []),
  CategorySpec(label: 'movies', rows: [], feedTab: 2),
  CategorySpec(
    label: 'series',
    rows: [
      (title: 'popular series', query: FilterQuery(channelId: Channel.tv)),
      (
        title: 'k-drama',
        query: FilterQuery(channelId: Channel.tv, country: 'Korea'),
      ),
      (
        title: 'indian drama',
        query: FilterQuery(channelId: Channel.tv, country: 'India'),
      ),
      (
        title: 'from the us',
        query: FilterQuery(channelId: Channel.tv, country: 'United States'),
      ),
      (
        title: 'hindi dubbed',
        query: FilterQuery(channelId: Channel.tv, classify: 'Hindi dub'),
      ),
      (
        title: 'new episodes',
        query: FilterQuery(channelId: Channel.tv, sort: 'Latest'),
      ),
    ],
  ),
  CategorySpec(
    label: 'anime',
    rows: [
      (title: 'top anime', query: FilterQuery(channelId: Channel.anime)),
      (
        title: 'hindi dubbed anime',
        query: FilterQuery(channelId: Channel.anime, classify: 'Hindi dub'),
      ),
      (
        title: 'latest anime',
        query: FilterQuery(channelId: Channel.anime, sort: 'Latest'),
      ),
    ],
  ),
  CategorySpec(
    label: 'k-drama',
    rows: [
      (
        title: 'trending k-drama',
        query: FilterQuery(channelId: Channel.tv, country: 'Korea'),
      ),
      (
        title: 'korean films',
        query: FilterQuery(channelId: Channel.movie, country: 'Korea'),
      ),
      (
        title: 'newest first',
        query: FilterQuery(
          channelId: Channel.tv,
          country: 'Korea',
          sort: 'Latest',
        ),
      ),
    ],
  ),
];

final _homeFeedProvider = FutureProvider.autoDispose<Feed>(
  (ref) => Api.i.home(),
);
final _trendingProvider = FutureProvider.autoDispose<List<Subject>>(
  (ref) => Api.i.trending(perPage: 24),
);
final _tabFeedProvider = FutureProvider.autoDispose.family<Feed, int>(
  (ref, tab) => Api.i.tab(tab),
);
final _filterProvider = FutureProvider.autoDispose
    .family<List<Subject>, String>((ref, key) async {
      final q = _filterRegistry[key];
      if (q == null) return const [];
      final page = await Api.i.filter(q);
      return page.items;
    });

/// Filter queries are looked up by a stable string so the family key stays
/// comparable — a FilterQuery is not a value type.
final _filterRegistry = <String, FilterQuery>{};

String _registerFilter(FilterQuery q) {
  final key = q.cacheKey;
  _filterRegistry[key] = q;
  return key;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);

    return Pivot(
      labels: _categories.map((c) => c.label).toList(),
      index: _category,
      onChanged: (i) => setState(() => _category = i),
      padding: EdgeInsets.only(
        left: l.margin + l.overscan.left,
        right: l.margin + l.overscan.right,
      ),
      style: l.t(DZ.title),
      headerGap: 10,
      builder: (context, i) {
        final spec = _categories[i];
        if (i == 0) return const _ForYouPane();
        if (spec.feedTab != null) return _FeedPane(tab: spec.feedTab!);
        return _FilterPane(key: ValueKey(spec.label), spec: spec);
      },
    );
  }
}

/// The first viewport the direction contract commits to: the section word at
/// poster scale and cropped, then the tile field — a 2×2 lead, flat colour
/// count tiles, and the catalog's own rows.
class _ForYouPane extends ConsumerWidget {
  const _ForYouPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final feed = ref.watch(_homeFeedProvider);
    final trending = ref.watch(_trendingProvider);
    final history = ref.watch(historyProvider);
    final watchlist = ref.watch(watchlistProvider);
    final progress = ref.watch(progressProvider);
    final downloads =
        ref.watch(downloadsProvider).asData?.value ?? const <DownloadItem>[];

    final resumable = history
        .where((e) => !e.finished && e.position > 10)
        .toList();
    final lead = resumable.isNotEmpty
        ? resumable.first.subject
        : feed.asData?.value.bannerItems.firstOrNull?.subject ??
              trending.asData?.value.firstOrNull;
    final leadEntry = resumable.isNotEmpty ? resumable.first : null;
    final leadImage = feed.asData?.value.bannerItems
        .where((b) => b.subject.subjectId == lead?.subjectId)
        .firstOrNull
        ?.image
        .url;

    final offlineIds = {
      for (final d in downloads.where((d) => d.status == DownloadStatus.done))
        d.subject.subjectId,
    };

    // The hero block is one composition, not four tiles that happen to sit in
    // a row: the lead holds the left of a two-row band and the four count
    // tiles fill the rest of it, two to a row. Sized from the live column
    // count so the band closes exactly — at four columns on a phone that is
    // the contract's own 2×2 lead with 1×1 tiles, and at ten on a desktop the
    // same picture drawn wider, instead of four small tiles stranded beside a
    // field of black.
    final countCols = (l.columns / 4).round().clamp(1, l.columns);
    final leadCols = (l.columns - countCols * 2).clamp(2, l.columns);

    return RefreshIndicator(
      color: DZ.cyan,
      backgroundColor: DZ.black,
      onRefresh: () async {
        await Api.i.clearCache();
        ref.invalidate(_homeFeedProvider);
        ref.invalidate(_trendingProvider);
      },
      child: ListView(
        padding: EdgeInsets.only(
          left: l.margin + l.overscan.left,
          right: l.margin + l.overscan.right,
          bottom: 48 + l.overscan.bottom,
        ),
        children: [
          // The word, cropped. It names where you are before any artwork loads.
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: GiantWord('watch'),
          ),

          if (feed.isLoading && lead == null)
            const LoadingBlock(label: 'loading the catalog')
          else if (feed.hasError && lead == null)
            StateBlock(
              headline: 'the catalog is not answering',
              detail:
                  feed.error?.toString() ??
                  'Check your connection and try again.',
              actionLabel: 'try again',
              onAction: () {
                ref.invalidate(_homeFeedProvider);
                ref.invalidate(_trendingProvider);
              },
            )
          else
            TileField(
              children: [
                if (lead != null)
                  TileSpan(
                    cols: leadCols,
                    rows: 2,
                    child: LeadTile(
                      subject: lead,
                      imageUrl: leadImage,
                      autofocus: l.isTV,
                      progress:
                          progress[progressKey(
                            lead.subjectId,
                            leadEntry?.episode,
                          )],
                      caption: leadEntry == null
                          ? null
                          : meta([
                              leadEntry.episode?.short,
                              formatLeft(leadEntry.remaining),
                            ]),
                      onTap: () => leadEntry != null
                          ? Nav.resume(context, ref, leadEntry)
                          : Nav.openTitle(context, lead),
                      onHold: () => Nav.openTitle(context, lead),
                    ),
                  ),
                TileSpan(
                  cols: countCols,
                  child: CountTile(
                    label: 'continue',
                    count: resumable.length,
                    fill: DZ.cyan,
                    caption: resumable.isEmpty ? 'nothing started' : null,
                    onTap: () =>
                        Nav.openLibrary(context, LibraryTab.continueWatching),
                  ),
                ),
                TileSpan(
                  cols: countCols,
                  child: CountTile(
                    label: 'downloads',
                    count: downloads
                        .where((d) => d.status == DownloadStatus.done)
                        .length,
                    fill: DZ.magenta,
                    caption: downloads.any((d) => d.active)
                        ? 'in progress'
                        : null,
                    onTap: () => Nav.openLibrary(context, LibraryTab.downloads),
                  ),
                ),
                TileSpan(
                  cols: countCols,
                  child: CountTile(
                    label: 'my list',
                    count: watchlist.length,
                    fill: DZ.lime,
                    onTap: () => Nav.openLibrary(context, LibraryTab.list),
                  ),
                ),
                TileSpan(
                  cols: countCols,
                  child: CountTile(
                    label: 'search',
                    count: 0,
                    fill: DZ.grey4,
                    caption: 'find a title',
                    onTap: () => Nav.openSearch(context),
                  ),
                ),
              ],
            ),

          // Continue, as its own strip — the single most-used row.
          if (resumable.length > 1)
            _Row(
              title: 'continue watching',
              subjects: resumable.skip(1).map((e) => e.subject).toList(),
              progressOf: (s) {
                final e = resumable.firstWhere(
                  (x) => x.subject.subjectId == s.subjectId,
                );
                return progress[progressKey(s.subjectId, e.episode)];
              },
              offlineIds: offlineIds,
              onSeeAll: () =>
                  Nav.openLibrary(context, LibraryTab.continueWatching),
            ),

          if (trending.asData?.value.isNotEmpty ?? false)
            _Row(
              title: 'trending now',
              subjects: trending.asData!.value,
              offlineIds: offlineIds,
              onSeeAll: () => Nav.openGrid(
                context,
                title: 'trending now',
                loader: (page) => Api.i.trending(page: page, perPage: 24),
              ),
            ),

          for (final section
              in feed.asData?.value.subjectSections ?? const <Section>[])
            _Row(
              title: section.cleanTitle,
              subjects: section.subjects,
              offlineIds: offlineIds,
            ),

          if (feed.isLoading && lead != null) const LoadingBlock(),
        ],
      ),
    );
  }
}

/// An operating feed from the catalog (the Movies tab).
class _FeedPane extends ConsumerWidget {
  const _FeedPane({required this.tab});
  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final feed = ref.watch(_tabFeedProvider(tab));

    return feed.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: DZ.margin),
        child: LoadingBlock(label: 'loading films'),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.symmetric(horizontal: l.margin),
        child: StateBlock(
          headline: 'could not load films',
          detail: e.toString(),
          actionLabel: 'try again',
          onAction: () => ref.invalidate(_tabFeedProvider(tab)),
        ),
      ),
      data: (f) {
        final sections = f.subjectSections;
        final banner = f.bannerItems;
        if (sections.isEmpty && banner.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: l.margin),
            child: const StateBlock(
              headline: 'nothing here right now',
              detail: 'The catalog returned no films for this tab. Pull down to retry.',
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.only(
            left: l.margin + l.overscan.left,
            right: l.margin + l.overscan.right,
            bottom: 48 + l.overscan.bottom,
          ),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: GiantWord('films'),
            ),
            if (banner.isNotEmpty)
              TileField(
                children: [
                  TileSpan(
                    cols: 2,
                    rows: 2,
                    child: LeadTile(
                      subject: banner.first.subject,
                      imageUrl: banner.first.image.url,
                      onTap: () => Nav.openTitle(context, banner.first.subject),
                    ),
                  ),
                  for (final b in banner.skip(1).take(4))
                    TileSpan(
                      child: PosterTile(
                        subject: b.subject,
                        onTap: () => Nav.openTitle(context, b.subject),
                      ),
                    ),
                ],
              ),
            for (final s in sections)
              _Row(title: s.cleanTitle, subjects: s.subjects),
          ],
        );
      },
    );
  }
}

/// A category built from filter queries.
class _FilterPane extends ConsumerWidget {
  const _FilterPane({super.key, required this.spec});
  final CategorySpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    return ListView(
      padding: EdgeInsets.only(
        left: l.margin + l.overscan.left,
        right: l.margin + l.overscan.right,
        bottom: 48 + l.overscan.bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GiantWord(spec.label),
        ),
        for (final row in spec.rows)
          _FilterRow(title: row.title, query: row.query),
      ],
    );
  }
}

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.title, required this.query});
  final String title;
  final FilterQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = _registerFilter(query);
    final items = ref.watch(_filterProvider(key));

    return items.when(
      loading: () => _RowSkeleton(title: title),
      error: (_, _) =>
          const SizedBox.shrink(), // a dead row is removed, not shouted about
      data: (list) => list.isEmpty
          ? const SizedBox.shrink()
          : _Row(
              title: title,
              subjects: list,
              onSeeAll: () => Nav.openGrid(
                context,
                title: title,
                loader: (page) async {
                  final r = await Api.i.filter(query.copyWith(page: page));
                  return r.items;
                },
              ),
            ),
    );
  }
}

/// A horizontal strip of poster tiles. Cells are grid columns wide, so a strip
/// on a phone and a strip on a TV are the same grammar at different scales.
class _Row extends ConsumerWidget {
  const _Row({
    required this.title,
    required this.subjects,
    this.onSeeAll,
    this.progressOf,
    this.offlineIds = const {},
  });

  final String title;
  final List<Subject> subjects;
  final VoidCallback? onSeeAll;
  final Progress? Function(Subject)? progressOf;
  final Set<String> offlineIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final cell = l.columnWidth;
    final tall = cell * 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(
          label: title,
          onTap: onSeeAll,
          trailing: Text('${subjects.length}', style: l.t(DZ.caption)),
        ),
        SizedBox(
          height: tall,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: subjects.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, _) => const SizedBox(width: DZ.gap),
            itemBuilder: (context, i) {
              final s = subjects[i];
              return SizedBox(
                width: cell,
                child: PosterTile(
                  subject: s,
                  progress: progressOf?.call(s),
                  downloaded: offlineIds.contains(s.subjectId),
                  onTap: () => Nav.openTitle(context, s),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final cell = l.columnWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHead(label: title, color: DZ.grey2),
        SizedBox(
          height: cell * 1.5,
          child: Row(
            children: [
              for (var i = 0; i < l.columns + 1; i++) ...[
                SizedBox(
                  width: cell,
                  child: TileSkeleton(delayIndex: i),
                ),
                const SizedBox(width: DZ.gap),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
