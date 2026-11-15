import 'package:material_ui/material_ui.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../widgets/poster_tile.dart';

/// What the screen says while the video is paused.
///
/// A paused frame is the moment someone asks "wait, who is that?" — so instead
/// of dimming the picture and waiting, the player answers: the title, where
/// you are in it, the synopsis, and the faces. The overlay is drawn in the same
/// flat tile vocabulary as the rest of the app, over a flat scrim rather than a
/// blur, because this world has no glass.
///
/// It only appears on a deliberate pause, never while buffering or seeking, and
/// it disappears the instant playback resumes.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.subject,
    required this.detail,
    required this.episodeLabel,
    required this.position,
    required this.duration,
    required this.visible,
    this.onCastTap,
  });

  final Subject subject;
  final DetailData? detail;
  final String? episodeLabel;
  final Duration position;
  final Duration duration;
  final bool visible;
  final void Function(Staff person)? onCastTap;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final reduced = reducedMotion(context);
    final s = detail?.subject ?? subject;
    final cast = detail?.cast ?? const <Staff>[];
    final directors = detail?.directors ?? const <Staff>[];
    final remaining = duration - position;

    // On a phone in landscape the overlay takes the left half and leaves the
    // picture visible; on a TV and a wide window it takes a third.
    final width = switch (l.hands) {
      Hands.remote => l.size.width * 0.42,
      Hands.pointer => l.size.width * 0.38,
      Hands.touch => l.size.width * 0.52,
    }.clamp(280.0, 620.0);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
        curve: DZ.ease,
        child: Row(
          children: [
            Container(
              width: width,
              height: double.infinity,
              color: DZ.scrim,
              padding: EdgeInsets.only(
                left: 28 + l.overscan.left,
                right: 24,
                top: 70 + l.overscan.top,
                bottom: 100 + l.overscan.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'paused',
                      style: l.t(DZ.label).copyWith(color: DZ.cyan),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.cleanTitle.toLowerCase(),
                      style: l.t(DZ.title),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      meta([
                        episodeLabel,
                        s.year,
                        s.rating == null ? null : '${s.rating} imdb',
                        formatLeft(remaining.inSeconds.toDouble()),
                      ]),
                      style: l.t(DZ.caption),
                      maxLines: 2,
                    ),

                    if ((s.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          s.description!,
                          style: l.t(DZ.body).copyWith(color: DZ.grey1),
                          maxLines: l.isTV ? 6 : 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],

                    if (directors.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Line(
                        label: directors.length == 1 ? 'director' : 'directors',
                        value: directors.map((d) => d.name).join(', '),
                      ),
                    ],

                    if (cast.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text(
                        'cast',
                        style: l.t(DZ.label).copyWith(color: DZ.cyan),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: l.isTV ? 128 : 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: cast.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: DZ.gap),
                          itemBuilder: (context, i) {
                            final p = cast[i];
                            final side = l.isTV ? 78.0 : 62.0;
                            return SizedBox(
                              width: side,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: side,
                                    child: Art(
                                      url: p.avatarUrl,
                                      fallbackTitle: p.name,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p.name.toLowerCase(),
                                    style: l
                                        .t(DZ.caption)
                                        .copyWith(color: DZ.white),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if ((p.character ?? '').isNotEmpty)
                                    Text(
                                      p.character!.toLowerCase(),
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

                    if (s.genres.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Line(label: 'genres', value: s.genres.join(', ')),
                    ],
                  ],
                ),
              ),
            ),
            // The picture stays visible beside the panel — the paused frame is
            // part of the answer.
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: l.t(DZ.caption).copyWith(color: DZ.grey2)),
        ),
        Expanded(
          child: Text(
            value.toLowerCase(),
            style: l.t(DZ.caption).copyWith(color: DZ.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
