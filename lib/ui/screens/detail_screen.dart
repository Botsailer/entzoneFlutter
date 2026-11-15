import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/textures.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/downloads.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../data/playback.dart';
import '../../data/progress.dart';
import '../nav.dart';
import '../sheets/download_sheet.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/poster_tile.dart';
import '../widgets/tile.dart';

final _detailProvider =
    FutureProvider.autoDispose.family<DetailData, Subject>((ref, subject) async {
  try {
    return await Api.i.detail(subject.detailPath);
  } catch (e) {
    // A downloaded title stays openable with no connection at all.
    final offline = Downloads.i.offlineDetail(subject);
    if (offline != null) return offline;
    rethrow;
  }
});

final _relatedProvider = FutureProvider.autoDispose
    .family<List<Subject>, String>((ref, id) => Api.i.related(id));

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.subject});
  final Subject subject;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  int _seasonIndex = 0;
  bool _synopsisOpen = false;
  bool _seasonPinned = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final detail = ref.watch(_detailProvider(widget.subject));

    return Scaffold(
      backgroundColor: DZ.black,
      body: detail.when(
        loading: () => _Frame(
          subject: widget.subject,
          child: const Padding(
            padding: EdgeInsets.all(DZ.margin),
            child: LoadingBlock(label: 'loading this title'),
          ),
        ),
        error: (e, _) => _Frame(
          subject: widget.subject,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: l.margin),
            child: StateBlock(
              headline: 'could not open this title',
              detail: e.toString(),
              actionLabel: 'try again',
              onAction: () => ref.invalidate(_detailProvider(widget.subject)),
            ),
          ),
        ),
        data: (d) => _Body(
          subject: widget.subject,
          detail: d,
          seasonIndex: _seasonIndex,
          onSeason: (i) => setState(() {
            _seasonIndex = i;
            _seasonPinned = true;
          }),
          seasonPinned: _seasonPinned,
          synopsisOpen: _synopsisOpen,
          onToggleSynopsis: () => setState(() => _synopsisOpen = !_synopsisOpen),
        ),
      ),
    );
  }
}

/// Backdrop plus a close control — shown while the detail is still loading so
/// the screen is never an empty black field.
class _Frame extends StatelessWidget {
  const _Frame({required this.subject, required this.child});
  final Subject subject;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(height: l.size.height * 0.34, child: Art(url: subject.cover?.url)),
            child,
          ],
        ),
        Positioned(
          left: l.margin + l.overscan.left,
          top: l.safe.top + 10 + l.overscan.top,
          child: const _CloseButton(),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) => MetroIconButton(
        icon: Icons.arrow_back,
        tooltip: 'back',
        size: Device.i.isTV ? 54 : 44,
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.subject,
    required this.detail,
    required this.seasonIndex,
    required this.onSeason,
    required this.seasonPinned,
    required this.synopsisOpen,
    required this.onToggleSynopsis,
  });

  final Subject subject;
  final DetailData detail;
  final int seasonIndex;
  final ValueChanged<int> onSeason;
  final bool seasonPinned;
  final bool synopsisOpen;
  final VoidCallback onToggleSynopsis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final s = detail.subject;
    final seasons = detail.seasons;
    final isSeries = s.isSeries && seasons.isNotEmpty;
    final progress = ref.watch(progressProvider);
    final history = ref.watch(historyProvider);
    final saved = ref.watch(watchlistProvider).any((x) => x.subjectId == s.subjectId);
    final related = ref.watch(_relatedProvider(s.subjectId));
    final downloads = ref.watch(downloadsByIdProvider);

    // Where a series' main button should land:
    //   never watched            → s1 e1
    //   last episode unfinished  → continue it
    //   last episode finished    → the next one, into the next season
    //   whole series finished    → start again
    final hist = history.where((e) => e.subject.subjectId == s.subjectId).firstOrNull;
    final histEp = (hist?.episode != null &&
            seasons.any((x) => x.se == hist!.episode!.season))
        ? hist!.episode
        : null;

    EpisodeRef? target;
    var mode = 'play';
    if (isSeries) {
      final first = EpisodeRef(seasons.first.se, 1);
      if (histEp == null) {
        target = first;
      } else if (progress[progressKey(s.subjectId, histEp)]?.done ?? false) {
        final n = nextEpisodeRef(seasons, histEp);
        target = n ?? first;
        mode = n != null ? 'next' : 'watch again';
      } else {
        target = histEp;
        mode = 'resume';
      }
    } else {
      final p = progress[progressKey(s.subjectId)];
      if (p != null && !p.done && p.position > 10) mode = 'resume';
      if (p?.done ?? false) mode = 'watch again';
    }

    // The season the pivot opens on: the one the viewer is in, unless they
    // have since moved it by hand.
    final landingSeason = seasonPinned
        ? seasonIndex
        : () {
            if (histEp == null) return 0;
            final i = seasons.indexWhere((x) => x.se == (target?.season ?? histEp.season));
            return i < 0 ? 0 : i;
          }();

    final targetProgress =
        target != null ? progress[progressKey(s.subjectId, target)] : progress[progressKey(s.subjectId)];

    final movieDownload = downloads[downloadId(s.subjectId, 0, 0)];

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // ── backdrop ──
            SliverToBoxAdapter(
              child: SizedBox(
                height: l.isTouch && l.size.width < 600
                    ? l.size.height * 0.46
                    : l.size.height * 0.52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Art(url: s.cover?.url, alignment: Alignment.topCenter),
                    // A flat plate, not a gradient — the world has none.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 150,
                      child: const FlatScrim(heavy: true),
                    ),
                    Positioned(
                      left: l.margin + l.overscan.left,
                      right: l.margin + l.overscan.right,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GiantWord(
                            s.cleanTitle,
                            scale: s.cleanTitle.length > 18 ? 0.52 : 0.74,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            meta([
                              s.typeLabel,
                              s.year,
                              if (isSeries)
                                '${seasons.length} season${seasons.length == 1 ? '' : 's'}'
                              else
                                formatDuration(s.duration),
                              s.rating == null ? null : '${s.rating} imdb',
                              s.countryName,
                            ]),
                            style: l.t(DZ.caption),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.only(
                left: l.margin + l.overscan.left,
                right: l.margin + l.overscan.right,
                bottom: 56 + l.overscan.bottom,
              ),
              sliver: SliverList.list(children: [
                const SizedBox(height: 18),

                // ── actions ──
                Wrap(
                  spacing: DZ.gap,
                  runSpacing: DZ.gap,
                  children: [
                    _PlayAction(
                      subject: s,
                      detail: detail,
                      target: target,
                      mode: mode,
                      progress: targetProgress,
                      isSeries: isSeries,
                    ),
                    MetroButton(
                      label: saved ? 'in my list' : 'my list',
                      icon: saved ? Icons.check : Icons.add,
                      chevron: false,
                      onPressed: () {
                        final now = ref.read(watchlistProvider.notifier).toggle(s);
                        notify(context, now ? 'added to my list' : 'removed from my list');
                      },
                    ),
                    if (!isSeries)
                      _MovieDownloadAction(
                        subject: s,
                        detail: detail,
                        item: movieDownload,
                      ),
                  ],
                ),

                // ── synopsis ──
                if ((s.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _Synopsis(
                    text: s.description!,
                    open: synopsisOpen,
                    onToggle: onToggleSynopsis,
                  ),
                ],

                if (s.genres.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: DZ.gap,
                    runSpacing: DZ.gap,
                    children: [
                      for (final g in s.genres)
                        _Chip(
                          label: g,
                          onTap: () => Nav.openGrid(
                            context,
                            title: g,
                            loader: (page) async {
                              final r = await Api.i.filter(FilterQuery(
                                channelId: s.isSeries ? Channel.tv : Channel.movie,
                                genre: g,
                                page: page,
                              ));
                              return r.items;
                            },
                          ),
                        ),
                    ],
                  ),
                ],

                // ── the season pivot: the signature move ──
                if (isSeries)
                  _Seasons(
                    subject: s,
                    detail: detail,
                    seasons: seasons,
                    index: landingSeason.clamp(0, seasons.length - 1),
                    onSeason: onSeason,
                  ),

                // ── cast ──
                if (detail.stars.isNotEmpty) _Cast(stars: detail.stars),

                // ── related ──
                related.maybeWhen(
                  data: (list) => list.isEmpty
                      ? const SizedBox.shrink()
                      : _RelatedRow(subjects: list),
                  orElse: () => const SizedBox.shrink(),
                ),
              ]),
            ),
          ],
        ),
        Positioned(
          left: l.margin + l.overscan.left,
          top: l.safe.top + 10 + l.overscan.top,
          child: const _CloseButton(),
        ),
      ],
    );
  }
}

/// The main action. Resolving what is playable takes a round trip, so the
/// button says what it is doing rather than going dead.
class _PlayAction extends ConsumerStatefulWidget {
  const _PlayAction({
    required this.subject,
    required this.detail,
    required this.target,
    required this.mode,
    required this.progress,
    required this.isSeries,
  });

  final Subject subject;
  final DetailData detail;
  final EpisodeRef? target;
  final String mode;
  final Progress? progress;
  final bool isSeries;

  @override
  ConsumerState<_PlayAction> createState() => _PlayActionState();
}

class _PlayActionState extends ConsumerState<_PlayAction> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = await streamProvider.resolve(
        widget.subject,
        widget.detail,
        widget.target,
      );
      if (!mounted) return;
      if (source == null) {
        notify(
          context,
          widget.isSeries
              ? 'that episode has no source right now'
              : 'this title has nothing playable right now',
          fill: DZ.amber,
        );
        return;
      }
      if (source.kind == 'trailer') {
        notify(context, 'only the trailer is available for this title');
      }
      await Nav.play(
        context,
        subject: widget.subject,
        source: widget.target == null ? source : source.copyWith(episode: widget.target),
        next: widget.target == null
            ? null
            : makeNextResolver(
                widget.subject, widget.detail, widget.detail.seasons, widget.target!),
        detail: widget.detail,
      );
    } catch (e) {
      if (mounted) notify(context, e.toString(), fill: DZ.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final ep = widget.target;
    final label = _busy
        ? 'starting…'
        : switch (widget.mode) {
            'resume' => ep != null
                ? 'resume ${ep.short}'
                : 'resume ${formatTime(p?.position ?? 0)}',
            'next' => 'play ${ep?.short ?? 'next'}',
            'watch again' => 'watch again',
            _ => ep != null ? 'play ${ep.short}' : 'play',
          };

    return MetroButton(
      label: label,
      icon: Icons.play_arrow,
      primary: true,
      chevron: false,
      autofocus: Device.i.isTV,
      onPressed: _busy ? null : _go,
    );
  }
}

class _MovieDownloadAction extends ConsumerWidget {
  const _MovieDownloadAction({
    required this.subject,
    required this.detail,
    required this.item,
  });

  final Subject subject;
  final DetailData detail;
  final DownloadItem? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final it = item;
    if (it == null) {
      return MetroButton(
        label: 'download',
        icon: Icons.download_outlined,
        chevron: false,
        onPressed: () => startDownloadFlow(
          context,
          ref,
          subject: subject,
          se: 0,
          ep: 0,
        ),
      );
    }
    return switch (it.status) {
      DownloadStatus.done => MetroButton(
          label: 'downloaded · ${formatBytes(it.total)}',
          icon: Icons.offline_pin_outlined,
          chevron: false,
          fill: DZ.magenta,
          primary: true,
          onPressed: () => Nav.openLibrary(context, LibraryTab.downloads),
        ),
      DownloadStatus.downloading => MetroButton(
          label: '${(it.ratio * 100).round()}%  ·  pause',
          icon: Icons.pause,
          chevron: false,
          onPressed: () => Downloads.i.pause(it.id),
        ),
      DownloadStatus.paused || DownloadStatus.queued => MetroButton(
          label: 'resume download',
          icon: Icons.download_outlined,
          chevron: false,
          onPressed: () => Downloads.i.resume(it.id),
        ),
      DownloadStatus.failed => MetroButton(
          label: 'retry download',
          icon: Icons.refresh,
          chevron: false,
          fill: DZ.red,
          onPressed: () => Downloads.i.resume(it.id),
        ),
    };
  }
}

/// Synopsis, clamped to a readable measure and expandable in place rather than
/// behind a modal.
class _Synopsis extends StatelessWidget {
  const _Synopsis({required this.text, required this.open, required this.onToggle});

  final String text;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Semantics(
      button: true,
      label: open ? 'collapse description' : 'expand description',
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          // 65–75 characters, whatever the window is doing.
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: reducedMotion(context) ? Duration.zero : DZ.stateChange,
                curve: DZ.ease,
                alignment: Alignment.topLeft,
                child: Text(
                  text,
                  style: l.t(DZ.body).copyWith(color: DZ.grey1),
                  maxLines: open ? null : 3,
                  overflow: open ? null : TextOverflow.ellipsis,
                ),
              ),
              if (text.length > 160) ...[
                const SizedBox(height: 6),
                Text(
                  open ? 'less' : 'more',
                  style: l.t(DZ.caption).copyWith(color: DZ.cyan),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      MetroButton(label: label, onPressed: onTap, chevron: false, dense: true);
}

/// **The season pivot.** Seasons are panorama panes; the next season's word is
/// clipped into view at the right edge. One flick, one D-pad right, or one
/// arrow key moves between them, and each pane is that season's episode field.
class _Seasons extends ConsumerWidget {
  const _Seasons({
    required this.subject,
    required this.detail,
    required this.seasons,
    required this.index,
    required this.onSeason,
  });

  final Subject subject;
  final DetailData detail;
  final List<SeasonResource> seasons;
  final int index;
  final ValueChanged<int> onSeason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final season = seasons[index];
    // Episode tiles are short and wide; the field holds fewer of them per row
    // than posters do.
    final cols = (l.columns / 2).ceil().clamp(2, 5);
    final cell = (l.fieldWidth - DZ.gap * (cols - 1)) / cols;
    final rows = (season.maxEp / cols).ceil();
    final height = rows * (cell * 0.62) + (rows - 1) * DZ.gap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: DZ.sectionTop),
        SizedBox(
          height: height + 52,
          child: Pivot(
            labels: [for (final s in seasons) 'season ${s.se}'],
            index: index,
            onChanged: onSeason,
            style: l.t(DZ.subtitle),
            headerGap: 12,
            trailing: Text(
              '${season.maxEp} episodes',
              style: l.t(DZ.caption),
            ),
            builder: (context, i) => _EpisodeField(
              subject: subject,
              detail: detail,
              season: seasons[i],
              columns: cols,
            ),
          ),
        ),
      ],
    );
  }
}

/// A season's episodes as a tile field.
///
/// Magnitude is physical extent: where the catalog reports a runtime, a longer
/// episode takes a wider tile, so the shape of a season is readable before any
/// number is.
class _EpisodeField extends ConsumerWidget {
  const _EpisodeField({
    required this.subject,
    required this.detail,
    required this.season,
    required this.columns,
  });

  final Subject subject;
  final DetailData detail;
  final SeasonResource season;
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final downloads = ref.watch(downloadsByIdProvider);

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: DZ.gap,
        crossAxisSpacing: DZ.gap,
        childAspectRatio: 1 / 0.62,
      ),
      itemCount: season.maxEp,
      itemBuilder: (context, i) {
        final ep = EpisodeRef(season.se, i + 1);
        return _EpisodeTile(
          subject: subject,
          detail: detail,
          episode: ep,
          progress: progress[progressKey(subject.subjectId, ep)],
          download: downloads[downloadId(subject.subjectId, ep.season, ep.episode)],
        );
      },
    );
  }
}

class _EpisodeTile extends ConsumerStatefulWidget {
  const _EpisodeTile({
    required this.subject,
    required this.detail,
    required this.episode,
    required this.progress,
    required this.download,
  });

  final Subject subject;
  final DetailData detail;
  final EpisodeRef episode;
  final Progress? progress;
  final DownloadItem? download;

  @override
  ConsumerState<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends ConsumerState<_EpisodeTile> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Nav.playEpisode(
      context,
      subject: widget.subject,
      detail: widget.detail,
      episode: widget.episode,
      onUnavailable: () =>
          notify(context, 'this episode has no source right now', fill: DZ.amber),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final p = widget.progress;
    final d = widget.download;
    final done = p?.done ?? false;
    final started = p != null && !done && p.ratio > 0;
    final offline = d?.status == DownloadStatus.done;

    // State as a flat fill, not a tint: finished is lime, in progress keeps the
    // ladder's inert grey and shows cyan as a bar.
    final fill = done ? DZ.lime : DZ.grey4;
    final ink = done ? DZ.black : DZ.white;

    return MetroTile(
      fill: fill,
      onTap: _busy ? null : _play,
      onHold: () => _episodeMenu(context, ref, widget.subject, widget.detail, widget.episode, d),
      semanticLabel: 'episode ${widget.episode.episode}'
          '${done ? ', watched' : started ? ', ${(p.ratio * 100).round()} percent watched' : ''}'
          '${offline ? ', downloaded' : ''}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${widget.episode.episode}',
                      style: l.t(DZ.numeral).copyWith(
                            color: ink,
                            fontSize: (DZ.numeral.fontSize! * l.textScale) * 0.62,
                          ),
                    ),
                    const Spacer(),
                    if (offline)
                      Container(width: 8, height: 8, color: DZ.magenta)
                    else if (d != null && d.active)
                      SizedBox(
                        width: 26,
                        child: TileProgress(ratio: d.ratio, color: DZ.magenta, height: 3),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  _busy
                      ? 'starting…'
                      : done
                          ? 'watched'
                          : started
                              ? formatLeft(p.remaining)
                              : 'episode ${widget.episode.episode}',
                  style: l.t(DZ.caption).copyWith(
                        color: done ? DZ.black.withValues(alpha: 0.72) : DZ.grey1,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (started)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TileProgress(ratio: p.ratio, color: DZ.cyan, height: 4, track: false),
            ),
        ],
      ),
    );
  }
}

Future<void> _episodeMenu(
  BuildContext context,
  WidgetRef ref,
  Subject subject,
  DetailData detail,
  EpisodeRef ep,
  DownloadItem? item,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: DZ.black,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(DZ.margin, 20, DZ.margin, 14),
            child: Text('${subject.cleanTitle.toLowerCase()} · ${ep.short}',
                style: DZ.subtitle),
          ),
          if (item == null)
            _MenuRow(
              label: 'download this episode',
              icon: Icons.download_outlined,
              onTap: () {
                Navigator.pop(ctx);
                startDownloadFlow(context, ref,
                    subject: subject, se: ep.season, ep: ep.episode);
              },
            )
          else if (item.status == DownloadStatus.done)
            _MenuRow(
              label: 'remove download · ${formatBytes(item.total)}',
              icon: Icons.delete_outline,
              tone: DZ.red,
              onTap: () {
                Navigator.pop(ctx);
                Downloads.i.remove(item.id);
              },
            )
          else
            _MenuRow(
              label: item.status == DownloadStatus.downloading ? 'pause download' : 'resume download',
              icon: item.status == DownloadStatus.downloading ? Icons.pause : Icons.play_arrow,
              onTap: () {
                Navigator.pop(ctx);
                item.status == DownloadStatus.downloading
                    ? Downloads.i.pause(item.id)
                    : Downloads.i.resume(item.id);
              },
            ),
          _MenuRow(
            label: 'mark as watched',
            icon: Icons.check,
            onTap: () {
              Navigator.pop(ctx);
              ref.read(progressProvider.notifier).save(subject.subjectId, ep, 1, 1);
            },
          ),
          _MenuRow(
            label: 'clear watch position',
            icon: Icons.restart_alt,
            onTap: () {
              Navigator.pop(ctx);
              ref.read(progressProvider.notifier).clearOne(subject.subjectId, ep);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone = DZ.white,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color tone;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DZ.margin, vertical: 15),
          child: Row(children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: DZ.body.copyWith(color: tone))),
          ]),
        ),
      );
}

/// Cast, as square tiles with the face bled to the edge — not circular avatars,
/// which this world has no shape for.
class _Cast extends StatelessWidget {
  const _Cast({required this.stars});
  final List<Staff> stars;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final cell = (l.columnWidth * 0.86).clamp(84.0, 150.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead(label: 'cast & crew'),
        SizedBox(
          height: cell + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stars.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, _) => const SizedBox(width: DZ.gap),
            itemBuilder: (context, i) {
              final p = stars[i];
              return SizedBox(
                width: cell,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: cell,
                      child: Art(url: p.avatarUrl, fallbackTitle: p.name),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p.name.toLowerCase(),
                      style: l.t(DZ.caption).copyWith(color: DZ.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      (p.isDirector ? 'director' : p.character ?? '').toLowerCase(),
                      style: l.t(DZ.caption),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.subjects});
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final cell = l.columnWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHead(label: 'more like this'),
        SizedBox(
          height: cell * 1.5,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: subjects.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, _) => const SizedBox(width: DZ.gap),
            itemBuilder: (context, i) => SizedBox(
              width: cell,
              child: PosterTile(
                subject: subjects[i],
                onTap: () => Nav.openTitle(context, subjects[i]),
              ),
            ),
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
