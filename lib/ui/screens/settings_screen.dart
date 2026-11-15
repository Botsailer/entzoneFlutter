import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/downloads.dart';
import '../../data/library.dart';
import '../../data/native.dart';
import '../../data/progress.dart';
import '../../data/settings.dart';
import '../nav.dart';
import '../widgets/controls.dart';
import '../widgets/pivot.dart';
import '../widgets/tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _pane = 0;
  int _cacheBytes = 0;

  @override
  void initState() {
    super.initState();
    _measureCache();
  }

  Future<void> _measureCache() async {
    final b = await Api.i.cacheBytes();
    if (mounted) setState(() => _cacheBytes = b);
  }

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
          child: const GiantWord('you'),
        ),
        Expanded(
          child: Pivot(
            labels: const ['playback', 'subtitles', 'downloads', 'storage', 'about'],
            index: _pane,
            onChanged: (i) => setState(() => _pane = i),
            padding: pad,
            style: l.t(DZ.subtitle),
            builder: (context, i) => switch (i) {
              0 => _PlaybackPane(padding: pad),
              1 => _SubtitlePane(padding: pad),
              2 => _DownloadPane(padding: pad),
              3 => _StoragePane(
                  padding: pad,
                  cacheBytes: _cacheBytes,
                  onCleared: _measureCache,
                ),
              _ => _AboutPane(padding: pad),
            },
          ),
        ),
      ],
    );
  }
}

class _PlaybackPane extends ConsumerWidget {
  const _PlaybackPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l = Layout.of(context);

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        _Choice<StreamQualityPref>(
          label: 'streaming quality',
          detail: 'the player starts on the closest rendition at or below this. '
              'you can still change it mid-video without losing your place.',
          value: s.streamQuality,
          options: StreamQualityPref.values,
          labelOf: (v) => v.label,
          hintOf: (v) => v.hint,
          onPick: (v) => n.update((x) => x.copyWith(streamQuality: v)),
        ),
        _Choice<int>(
          label: 'skip by',
          detail: 'used by the skip buttons, a double tap on the picture, the '
              'arrow keys, and the remote.',
          value: s.skipSeconds,
          options: Settings.skipChoices,
          labelOf: (v) => '$v seconds',
          onPick: (v) => n.update((x) => x.copyWith(skipSeconds: v)),
        ),
        _Choice<double>(
          label: 'speed while holding',
          detail: 'press and hold anywhere on the picture to run at this speed, '
              'release to go back.',
          value: s.longPressSpeed,
          options: Settings.speedChoices,
          labelOf: (v) => '${v}x',
          onPick: (v) => n.update((x) => x.copyWith(longPressSpeed: v)),
        ),
        _Toggle(
          label: 'play the next episode automatically',
          detail: 'when an episode ends, the next one starts. the player has '
              'the same switch on its bar.',
          value: s.autoplayNext,
          onChanged: (v) => n.update((x) => x.copyWith(autoplayNext: v)),
        ),
        _Toggle(
          label: 'load the next episode early',
          detail: 'resolves and buffers the next episode while this one plays, '
              'so next is instant. uses a little more data.',
          value: s.preloadNext,
          onChanged: (v) => n.update((x) => x.copyWith(preloadNext: v)),
        ),
        _Toggle(
          label: 'show cast and story when paused',
          detail: 'a paused frame answers "who is that?" instead of just '
              'sitting there.',
          value: s.pauseDetails,
          onChanged: (v) => n.update((x) => x.copyWith(pauseDetails: v)),
        ),
        if (Device.i.supportsAutoPip)
          _Toggle(
            label: 'shrink to a corner when i leave',
            detail: 'leaving the app mid-video keeps the picture in a small '
                'window. android 12 and later.',
            value: s.autoPip,
            onChanged: (v) => n.update((x) => x.copyWith(autoPip: v)),
          ),
        _Toggle(
          label: 'keep the sound going in the background',
          detail: 'audio continues when the app is not on screen and not in a '
              'corner window.',
          value: s.backgroundPlay,
          onChanged: (v) => n.update((x) => x.copyWith(backgroundPlay: v)),
        ),
        _Toggle(
          label: 'lock screen and notification controls',
          detail: 'play, pause and skip from outside the app.',
          value: s.mediaControls,
          onChanged: (v) => n.update((x) => x.copyWith(mediaControls: v)),
        ),
      ],
    );
  }
}

class _SubtitlePane extends ConsumerWidget {
  const _SubtitlePane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l = Layout.of(context);

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        // A live sample, so the sliders are not guesswork.
        Container(
          height: 150,
          margin: const EdgeInsets.only(bottom: 8),
          color: DZ.grey4,
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.all(16),
          child: Container(
            color: DZ.black.withValues(alpha: s.subtitleBackground),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              'this is how captions will look.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: DZ.family,
                fontSize: 20 * s.subtitleSize,
                height: 1.3,
                color: DZ.white,
              ),
            ),
          ),
        ),
        _Slider(
          label: 'caption size',
          value: s.subtitleSize,
          min: 0.75,
          max: 2.0,
          divisions: 5,
          display: '${(s.subtitleSize * 100).round()}%',
          onChanged: (v) => n.update((x) => x.copyWith(subtitleSize: v)),
        ),
        _Slider(
          label: 'plate behind the text',
          value: s.subtitleBackground,
          min: 0,
          max: 1,
          divisions: 4,
          display: s.subtitleBackground == 0
              ? 'none'
              : '${(s.subtitleBackground * 100).round()}%',
          onChanged: (v) => n.update((x) => x.copyWith(subtitleBackground: v)),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 22),
          child: Text(
            'captions come from the video file itself. most titles in this '
            'catalog ship one track or none, and the player lists whatever a '
            'title actually has.',
            style: DZ.caption,
          ),
        ),
      ],
    );
  }
}

class _DownloadPane extends ConsumerWidget {
  const _DownloadPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l = Layout.of(context);

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        _Choice<DownloadQualityPref>(
          label: 'download quality',
          detail: 'the rendition a download uses when you do not pick one.',
          value: s.downloadQuality,
          options: DownloadQualityPref.values,
          labelOf: (v) => v.label,
          hintOf: (v) => v.hint,
          onPick: (v) => n.update((x) => x.copyWith(downloadQuality: v)),
        ),
        _Toggle(
          label: 'ask every time',
          detail: 'shows the real file size of each rendition before the '
              'download starts.',
          value: s.askDownloadQuality,
          onChanged: (v) => n.update((x) => x.copyWith(askDownloadQuality: v)),
        ),
        _Toggle(
          label: 'only on wi-fi',
          detail: 'downloads wait until you are off mobile data.',
          value: s.wifiOnlyDownloads,
          onChanged: (v) => n.update((x) => x.copyWith(wifiOnlyDownloads: v)),
        ),
        if (Device.i.hasDownloadService)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: MetroButton(
              label: 'allow download notifications',
              icon: Icons.notifications_none,
              chevron: false,
              onPressed: () async {
                final ok = await Native.i.ensureNotificationPermission();
                if (context.mounted) {
                  notify(
                    context,
                    ok ? 'notifications allowed' : 'notifications are blocked in system settings',
                    fill: ok ? DZ.white : DZ.amber,
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

class _StoragePane extends ConsumerWidget {
  const _StoragePane({
    required this.padding,
    required this.cacheBytes,
    required this.onCleared,
  });

  final EdgeInsets padding;
  final int cacheBytes;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = Layout.of(context);
    final downloads = ref.watch(downloadsProvider).asData?.value ?? Downloads.i.items;
    final onDisk = downloads
        .where((d) => d.status == DownloadStatus.done)
        .fold<int>(0, (a, b) => a + b.total);

    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        // Magnitude as extent: two tiles sized by what they actually hold.
        TileField(
          columns: 2,
          children: [
            TileSpan(
              child: CountTile(
                label: 'downloaded',
                count: downloads.where((d) => d.status == DownloadStatus.done).length,
                fill: DZ.magenta,
                caption: formatBytes(onDisk),
                onTap: () => Nav.openLibrary(context, LibraryTab.downloads),
              ),
            ),
            TileSpan(
              child: CountTile(
                label: 'cached pages',
                count: (cacheBytes / 1024).round(),
                fill: DZ.grey4,
                caption: formatBytes(cacheBytes),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        MetroButton(
          label: 'clear the catalog cache',
          icon: Icons.cleaning_services_outlined,
          chevron: false,
          onPressed: () async {
            await Api.i.clearCache();
            onCleared();
            if (context.mounted) notify(context, 'cache cleared');
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'clears stored catalog pages only. downloads, your list, history and '
          'watch positions are untouched.',
          style: DZ.caption,
        ),
        const SizedBox(height: 28),
        MetroButton(
          label: 'delete every download',
          icon: Icons.delete_outline,
          chevron: false,
          fill: DZ.red,
          primary: true,
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: 'delete every download?',
              body: 'All ${downloads.length} files (${formatBytes(onDisk)}) are '
                  'removed from this device. You can download them again later.',
              confirm: 'delete them',
            );
            if (ok != true) return;
            await Downloads.i.removeAll();
            if (context.mounted) notify(context, 'downloads deleted');
          },
        ),
        const SizedBox(height: 28),
        MetroButton(
          label: 'reset everything',
          icon: Icons.restart_alt,
          chevron: false,
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: 'reset the app?',
              body: 'Forgets your list, history, watch positions, settings and '
                  'the cache, and deletes downloads. This cannot be undone.',
              confirm: 'reset everything',
            );
            if (ok != true) return;
            await Downloads.i.removeAll();
            await Api.i.clearCache();
            await ref.read(historyProvider.notifier).clear();
            await ref.read(progressProvider.notifier).clearAll();
            await ref.read(watchlistProvider.notifier).clear();
            await ref.read(recentSearchProvider.notifier).clear();
            ref.read(settingsProvider.notifier).update((_) => const Settings());
            onCleared();
            if (context.mounted) notify(context, 'the app has been reset');
          },
        ),
      ],
    );
  }
}

class _AboutPane extends StatelessWidget {
  const _AboutPane({required this.padding});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return ListView(
      padding: padding.copyWith(bottom: 48 + l.overscan.bottom),
      children: [
        Text('depressedzone', style: l.t(DZ.title)),
        const SizedBox(height: 6),
        const Text('version 1.0.0', style: DZ.caption),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: const Text(
            'one client for an unofficial third-party catalog, on your phone, '
            'your television and your desktop. what is available, which '
            'renditions a title has, and which audio and caption tracks exist '
            'are all decided upstream and change without notice.\n\n'
            'nothing you watch leaves this device. there is no account, and the '
            'session is anonymous and disposable.',
            style: DZ.body,
          ),
        ),
        const SizedBox(height: 30),
        Text('how it is driven here', style: l.t(DZ.subtitle)),
        const SizedBox(height: 12),
        const _Keys(rows: [
          ('space  ·  k', 'play or pause'),
          ('← →', 'skip by your interval'),
          ('j  ·  l', 'jump ten seconds'),
          ('↑ ↓', 'volume'),
          ('m', 'mute'),
          ('f', 'cycle fit, fill, stretch'),
          ('c  ·  a  ·  q', 'subtitles, audio, quality'),
          ('n', 'next episode'),
          ('esc', 'close the player'),
          ('[  ·  ]', 'previous or next season'),
        ]),
        const SizedBox(height: 26),
        const Text(
          'on a television the d-pad moves between tiles, select plays, the '
          'menu key opens a tile\'s actions, and the media keys work in the '
          'player.',
          style: DZ.caption,
        ),
      ],
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (key, what) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 128,
                  child: Text(key, style: DZ.caption.copyWith(color: DZ.cyan)),
                ),
                Expanded(child: Text(what, style: DZ.caption.copyWith(color: DZ.white))),
              ]),
            ),
        ],
      );
}

// ───────────────────────── rows ─────────────────────────

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Semantics(
      toggled: value,
      label: label,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: l.t(DZ.body)),
                    if (detail != null) ...[
                      const SizedBox(height: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(detail!, style: l.t(DZ.caption)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onPick,
    this.hintOf,
    this.detail,
  });

  final String label;
  final String? detail;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? hintOf;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final hint = hintOf?.call(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: l.t(DZ.body)),
          if (detail != null) ...[
            const SizedBox(height: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(detail!, style: l.t(DZ.caption)),
            ),
          ],
          const SizedBox(height: 11),
          Wrap(
            spacing: DZ.gap,
            runSpacing: DZ.gap,
            children: [
              for (final o in options)
                MetroButton(
                  label: labelOf(o),
                  dense: true,
                  chevron: false,
                  primary: o == value,
                  onPressed: () => onPick(o),
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: l.t(DZ.caption).copyWith(color: DZ.grey2)),
          ],
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: l.t(DZ.body))),
            Text(display, style: l.t(DZ.caption).copyWith(color: DZ.cyan)),
          ]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DZ.black,
        title: Text(title, style: DZ.subtitle),
        content: Text(body, style: DZ.body),
        actions: [
          MetroButton(
            label: 'cancel',
            chevron: false,
            dense: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          MetroButton(
            label: confirm,
            chevron: false,
            dense: true,
            primary: true,
            fill: DZ.red,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
