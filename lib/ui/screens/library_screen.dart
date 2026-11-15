import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/downloads.dart';
import '../../data/library.dart';
import '../../data/progress.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/poster_tile.dart';

enum LibraryTab { continueWatching, list, downloads, history }

extension LibraryTabX on LibraryTab {
  String get label => switch (this) {
        LibraryTab.continueWatching => 'continue',
        LibraryTab.list => 'my list',
        LibraryTab.downloads => 'downloads',
        LibraryTab.history => 'history',
      };
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab = LibraryTab.continueWatching});
  final LibraryTab initialTab;

  @override
  ConsumerState<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends ConsumerState<LibraryScreen> {
  late int _index = LibraryTab.values.indexOf(widget.initialTab);

  void showTab(LibraryTab tab) =>
      setState(() => _index = LibraryTab.values.indexOf(tab));

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final pad = EdgeInsets.only(
      left: l.margin + l.overscan.left,
      right: l.margin + l.overscan.right,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: pad.copyWith(top: 8, bottom: 6),
          child: const GiantWord('yours'),
        ),
        Expanded(
          child: Pivot(
            labels: LibraryTab.values.map((t) => t.label).toList(),
            index: _index,
            onChanged: (i) => setState(() => _index = i),
            padding: pad,
            style: l.t(DZ.subtitle),
            builder: (context, i) => switch (LibraryTab.values[i]) {
              LibraryTab.continueWatching => _ContinuePane(padding: pad),
              LibraryTab.list => _ListPane(padding: pad),
              LibraryTab.downloads => _DownloadsPane(padding: pad),
              LibraryTab.history => _HistoryPane(padding: pad),
            },
          ),
        ),
      ],
    );
  }
}

class _ContinuePane extends ConsumerWidget {
  const _ContinuePane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final entries = ref.watch(historyProvider).where((e) => !e.finished).toList();
    final progress = ref.watch(progressProvider);

    if (entries.isEmpty) {
      return Padding(
        padding: padding,
        child: StateBlock(
          headline: 'nothing started yet',
          detail: 'Play something and it will wait for you here, at the exact '
              'second you stopped.',
          actionLabel: 'browse the catalog',
          onAction: () => Nav.openLibrary(context, LibraryTab.continueWatching),
        ),
      );
    }

    return GridView.builder(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (l.columns / 2).ceil().clamp(2, 5),
        mainAxisSpacing: DZ.gap,
        crossAxisSpacing: DZ.gap,
        childAspectRatio: 16 / 10,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        return LeadTile(
          subject: e.subject,
          progress: progress[progressKey(e.subject.subjectId, e.episode)],
          caption: meta([e.episode?.short, formatLeft(e.remaining), timeAgo(e.at)]),
          onTap: () => Nav.resume(context, ref, e),
          onHold: () => _entryMenu(context, ref, e),
        );
      },
    );
  }
}

class _ListPane extends ConsumerWidget {
  const _ListPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final items = ref.watch(watchlistProvider);
    final progress = ref.watch(progressProvider);

    if (items.isEmpty) {
      return Padding(
        padding: padding,
        child: const StateBlock(
          headline: 'your list is empty',
          detail: 'Add a title from its page and it will be here on every '
              'device you sign this app into.',
        ),
      );
    }

    return GridView.builder(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: l.columns,
        mainAxisSpacing: DZ.gap,
        crossAxisSpacing: DZ.gap,
        childAspectRatio: 1 / 1.5,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => PosterTile(
        subject: items[i],
        progress: progress[progressKey(items[i].subjectId)],
        onTap: () => Nav.openTitle(context, items[i]),
        onHold: () {
          ref.read(watchlistProvider.notifier).remove(items[i].subjectId);
          notify(context, 'removed from my list');
        },
      ),
    );
  }
}

class _DownloadsPane extends ConsumerWidget {
  const _DownloadsPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final items = ref.watch(downloadsProvider).asData?.value ?? Downloads.i.items;

    if (items.isEmpty) {
      return Padding(
        padding: padding,
        child: const StateBlock(
          headline: 'nothing downloaded',
          detail: 'Download a film or an episode from its page and it plays '
              'here with no connection at all.',
        ),
      );
    }

    final active = items.where((d) => d.active || d.status == DownloadStatus.paused).toList();
    final done = items.where((d) => d.status == DownloadStatus.done).toList();
    final failed = items.where((d) => d.status == DownloadStatus.failed).toList();
    final onDisk = done.fold<int>(0, (a, b) => a + b.total);

    Widget grid(List<DownloadItem> list) => GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: l.columns,
            mainAxisSpacing: DZ.gap,
            crossAxisSpacing: DZ.gap,
            childAspectRatio: 1 / 1.5,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => DownloadTile(
            item: list[i],
            onTap: () => _downloadAction(context, ref, list[i]),
            onHold: () => _downloadMenu(context, ref, list[i]),
          ),
        );

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        if (active.isNotEmpty) ...[
          SectionHead(
            label: 'in progress',
            topGap: 8,
            color: DZ.magenta,
            trailing: GestureDetector(
              onTap: () => Downloads.i.pauseAll(),
              child: Text('pause all', style: l.t(DZ.caption).copyWith(color: DZ.grey1)),
            ),
          ),
          grid(active),
        ],
        if (failed.isNotEmpty) ...[
          const SectionHead(label: 'could not finish', color: DZ.red),
          grid(failed),
        ],
        if (done.isNotEmpty) ...[
          SectionHead(
            label: 'on this device',
            color: DZ.lime,
            trailing: Text(formatBytes(onDisk), style: l.t(DZ.caption)),
          ),
          grid(done),
        ],
      ],
    );
  }
}

class _HistoryPane extends ConsumerWidget {
  const _HistoryPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final entries = ref.watch(historyProvider);
    final progress = ref.watch(progressProvider);

    if (entries.isEmpty) {
      return Padding(
        padding: padding,
        child: const StateBlock(
          headline: 'no history yet',
          detail: 'Everything you watch is recorded here, on this device only.',
        ),
      );
    }

    // Grouped by day, newest first.
    final groups = <String, List<HistoryEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(dayBucket(e.at), () => []).add(e);
    }

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        for (final entry in groups.entries) ...[
          SectionHead(
            label: entry.key,
            topGap: entry.key == groups.keys.first ? 8 : DZ.sectionTop,
            trailing: Text('${entry.value.length}', style: l.t(DZ.caption)),
          ),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: l.columns,
              mainAxisSpacing: DZ.gap,
              crossAxisSpacing: DZ.gap,
              childAspectRatio: 1 / 1.5,
            ),
            itemCount: entry.value.length,
            itemBuilder: (context, i) {
              final e = entry.value[i];
              return PosterTile(
                subject: e.subject,
                progress: progress[progressKey(e.subject.subjectId, e.episode)],
                onTap: () => Nav.openTitle(context, e.subject),
                onHold: () => _entryMenu(context, ref, e),
              );
            },
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 34),
          child: MetroButton(
            label: 'clear watch history',
            icon: Icons.delete_outline,
            chevron: false,
            onPressed: () => _confirmClearHistory(context, ref),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── actions ─────────────────────────

void _downloadAction(BuildContext context, WidgetRef ref, DownloadItem d) {
  switch (d.status) {
    case DownloadStatus.done:
      Nav.openTitle(context, d.subject);
    case DownloadStatus.downloading:
      Downloads.i.pause(d.id);
    case DownloadStatus.paused || DownloadStatus.queued || DownloadStatus.failed:
      Downloads.i.resume(d.id);
  }
}

Future<void> _downloadMenu(BuildContext context, WidgetRef ref, DownloadItem d) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: DZ.black,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DZ.margin, 20, DZ.margin, 6),
              child: Text(d.subject.cleanTitle.toLowerCase(), style: DZ.subtitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(DZ.margin, 0, DZ.margin, 16),
              child: Text(
                meta([
                  d.isEpisode ? 's${d.se} · e${d.ep}' : 'film',
                  d.quality,
                  formatBytes(d.total),
                ]),
                style: DZ.caption,
              ),
            ),
            if (d.status == DownloadStatus.done)
              _Row(
                label: 'open this title',
                icon: Icons.play_arrow,
                onTap: () {
                  Navigator.pop(ctx);
                  Nav.openTitle(context, d.subject);
                },
              ),
            if (d.active)
              _Row(
                label: 'pause',
                icon: Icons.pause,
                onTap: () {
                  Navigator.pop(ctx);
                  Downloads.i.pause(d.id);
                },
              ),
            if (d.status == DownloadStatus.paused || d.status == DownloadStatus.failed)
              _Row(
                label: 'resume',
                icon: Icons.play_arrow,
                onTap: () {
                  Navigator.pop(ctx);
                  Downloads.i.resume(d.id);
                },
              ),
            _Row(
              label: 'delete from this device',
              icon: Icons.delete_outline,
              tone: DZ.red,
              onTap: () {
                Navigator.pop(ctx);
                Downloads.i.remove(d.id);
                notify(context, 'download removed');
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

Future<void> _entryMenu(BuildContext context, WidgetRef ref, HistoryEntry e) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: DZ.black,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(DZ.margin, 20, DZ.margin, 14),
              child: Text(e.subject.cleanTitle.toLowerCase(), style: DZ.subtitle),
            ),
            _Row(
              label: 'open this title',
              icon: Icons.open_in_new,
              onTap: () {
                Navigator.pop(ctx);
                Nav.openTitle(context, e.subject);
              },
            ),
            _Row(
              label: 'start from the beginning',
              icon: Icons.restart_alt,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(progressProvider.notifier)
                    .clearOne(e.subject.subjectId, e.episode);
                notify(context, 'watch position cleared');
              },
            ),
            _Row(
              label: 'remove from history',
              icon: Icons.delete_outline,
              tone: DZ.red,
              onTap: () {
                Navigator.pop(ctx);
                ref.read(historyProvider.notifier).remove(e.subject.subjectId);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: DZ.black,
      title: const Text('clear watch history?', style: DZ.subtitle),
      content: const Text(
        'This removes every title from history and forgets where you stopped '
        'in each one. Downloads and your list are not touched.',
        style: DZ.body,
      ),
      actions: [
        MetroButton(
          label: 'keep it',
          chevron: false,
          dense: true,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        MetroButton(
          label: 'clear everything',
          chevron: false,
          dense: true,
          primary: true,
          fill: DZ.red,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(historyProvider.notifier).clear();
  await ref.read(progressProvider.notifier).clearAll();
  if (context.mounted) notify(context, 'history cleared');
}

class _Row extends StatelessWidget {
  const _Row({
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
