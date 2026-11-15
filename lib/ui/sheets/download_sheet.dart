import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/downloads.dart';
import '../../data/models.dart';
import '../../data/native.dart';
import '../../data/settings.dart';
import '../nav.dart';

/// Start a download.
///
/// When "ask every time" is on, the renditions are shown with the real byte
/// size the catalog reported for each — so the choice is made with the actual
/// cost in view rather than a word like "high". Magnitude as extent: the bar
/// under each rendition is sized against the largest one.
Future<void> startDownloadFlow(
  BuildContext context,
  WidgetRef ref, {
  required Subject subject,
  required int se,
  required int ep,
}) async {
  final settings = ref.read(settingsProvider);

  if (Device.i.hasDownloadService) {
    await Native.i.ensureNotificationPermission();
  }

  PlayResult result;
  try {
    result = await Api.i.play(
      subject.subjectId,
      subject.detailPath,
      se: se,
      ep: ep,
    );
  } catch (e) {
    if (context.mounted) notify(context, e.toString(), fill: DZ.red);
    return;
  }

  if (result.streams.isEmpty) {
    if (context.mounted) {
      notify(
        context,
        'there is nothing downloadable for this one',
        fill: DZ.amber,
      );
    }
    return;
  }

  final headers = result.mediaHeaders;

  Future<void> queue(PlayStream s) async {
    await Downloads.i.add(
      subject: subject,
      se: se,
      ep: ep,
      quality: StreamQualityLike(
        label: s.label,
        url: s.url,
        height: s.height,
        headers: headers,
        sizeBytes: s.size,
      ),
    );
    if (context.mounted) {
      notify(context, 'downloading ${s.label} · ${formatBytes(s.size)}');
    }
  }

  if (!settings.askDownloadQuality) {
    final idx = pickByHeight(
      result.streams.map((s) => s.height).toList(),
      settings.downloadQuality.targetHeight,
    );
    await queue(result.streams[idx]);
    return;
  }

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: DZ.black,
    isScrollControlled: true,
    builder: (ctx) => _QualitySheet(
      subject: subject,
      se: se,
      ep: ep,
      streams: result.streams,
      onPick: (s, remember) async {
        Navigator.pop(ctx);
        if (remember) {
          ref
              .read(settingsProvider.notifier)
              .update(
                (x) => x.copyWith(
                  downloadQuality: DownloadQualityPrefX.forHeight(s.height),
                  askDownloadQuality: false,
                ),
              );
        }
        await queue(s);
      },
    ),
  );
}

class _QualitySheet extends StatefulWidget {
  const _QualitySheet({
    required this.subject,
    required this.se,
    required this.ep,
    required this.streams,
    required this.onPick,
  });

  final Subject subject;
  final int se;
  final int ep;
  final List<PlayStream> streams;
  final void Function(PlayStream stream, bool remember) onPick;

  @override
  State<_QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<_QualitySheet> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final largest = widget.streams
        .map((s) => s.size ?? 0)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DZ.margin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 22),
            Text('download', style: l.t(DZ.title)),
            const SizedBox(height: 4),
            Text(
              meta([
                widget.subject.cleanTitle.toLowerCase(),
                widget.se > 0 ? 's${widget.se} · e${widget.ep}' : null,
              ]),
              style: l.t(DZ.caption),
            ),
            const SizedBox(height: 20),
            for (final s in widget.streams)
              _QualityRow(
                stream: s,
                widthFactor: largest > 1 ? (s.size ?? 0) / largest : 1,
                onTap: () => widget.onPick(s, _remember),
              ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _remember = !_remember),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'always use this quality and stop asking',
                        style: l.t(DZ.caption).copyWith(color: DZ.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.stream,
    required this.widthFactor,
    required this.onTap,
  });

  final PlayStream stream;
  final double widthFactor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DZ.gap),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border.fromBorderSide(
              BorderSide(color: DZ.grey3, width: DZ.hairline),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(stream.label, style: l.t(DZ.subtitle)),
                  const SizedBox(width: 10),
                  Text(qualityName(stream.height), style: l.t(DZ.caption)),
                  const Spacer(),
                  Text(
                    formatBytes(stream.size),
                    style: l.t(DZ.body).copyWith(color: DZ.magenta),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The size, read as extent before it is read as text.
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: widthFactor.clamp(0.04, 1.0),
                child: Container(height: 4, color: DZ.magenta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
