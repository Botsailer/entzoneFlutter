import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/textures.dart';
import '../../core/tokens.dart';
import '../../data/downloads.dart';
import '../../data/models.dart' as m;
import '../../data/progress.dart';
import 'tile.dart';

/// Artwork that fills its tile edge to edge, with a flat placeholder while it
/// loads and an honest fallback when the catalog's image 404s — which it does.
class Art extends StatelessWidget {
  const Art({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackTitle,
  });

  final String? url;
  final BoxFit fit;
  final Alignment alignment;

  /// Shown as flat type when there is no image. Better than a broken-image
  /// glyph: the user still learns what the tile is.
  final String? fallbackTitle;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return _fallback(context);
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 160),
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => const TileSkeleton(),
      errorWidget: (_, _, _) => _fallback(context),
      memCacheWidth: 900,
    );
  }

  Widget _fallback(BuildContext context) {
    final t = fallbackTitle;
    return Container(
      color: DZ.grey4,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(8),
      child: t == null || t.isEmpty
          ? const SizedBox.shrink()
          : Text(
              t.toLowerCase(),
              style: DZ.caption.copyWith(color: DZ.grey2),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }
}

/// A catalog title as a tile: artwork to all four edges, its name on a flat
/// scrim at the bottom, and state read off colour alone — cyan for in progress,
/// lime for finished, magenta for on this device.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.subject,
    required this.onTap,
    this.onHold,
    this.progress,
    this.downloaded = false,
    this.autofocus = false,
    this.showName = true,
    this.corner,
    this.landscape = false,
  });

  final m.Subject subject;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final Progress? progress;
  final bool downloaded;
  final bool autofocus;
  final bool showName;

  /// Override for the catalog's own corner flag ("CAM", "HD", …).
  final String? corner;

  /// Use the backdrop crop rather than the poster crop.
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final p = progress;
    final flag = corner ?? subject.corner;
    final finished = p?.done ?? false;

    return MetroTile(
      onTap: onTap,
      onHold: onHold,
      autofocus: autofocus,
      semanticLabel:
          '${subject.cleanTitle}, ${subject.typeLabel}${subject.year.isEmpty ? '' : ', ${subject.year}'}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Art(
            url: subject.cover?.url,
            fallbackTitle: subject.cleanTitle,
            alignment: landscape ? Alignment.topCenter : Alignment.center,
          ),

          // The name, on a flat plate — not a gradient. This world has none.
          if (showName)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: DZ.scrim,
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subject.cleanTitle.toLowerCase(),
                      style: l.t(DZ.body).copyWith(height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subject.year.isNotEmpty || subject.rating != null)
                      Text(
                        meta([subject.year, subject.rating]),
                        style: l.t(DZ.caption),
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ),

          // State. Colour alone, flush to the bottom edge.
          if (p != null && p.ratio > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TileProgress(
                ratio: p.ratio,
                color: finished ? DZ.lime : DZ.cyan,
                height: Device.i.isTV ? 6 : 4,
              ),
            ),

          if (downloaded)
            const Positioned(
              left: 0,
              top: 0,
              child: TileBadge(text: 'offline', fill: DZ.magenta),
            ),

          if (flag != null && flag.isNotEmpty && !downloaded)
            Positioned(
              left: 0,
              top: 0,
              child: TileBadge(text: flag, fill: DZ.white),
            ),
        ],
      ),
    );
  }
}

/// The lead tile: a 2×2 field of backdrop with the title at subtitle scale, the
/// dot-matrix patch in its empty quarter, and its own resume state. This is the
/// primary action on the home screen — the whole field is the play target.
class LeadTile extends StatelessWidget {
  const LeadTile({
    super.key,
    required this.subject,
    required this.onTap,
    this.onHold,
    this.progress,
    this.imageUrl,
    this.autofocus = false,
    this.caption,
  });

  final m.Subject subject;
  final VoidCallback onTap;
  final VoidCallback? onHold;
  final Progress? progress;
  final String? imageUrl;
  final bool autofocus;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final p = progress;

    return MetroTile(
      onTap: onTap,
      onHold: onHold,
      autofocus: autofocus,
      semanticLabel: 'play ${subject.cleanTitle}',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Art(
            url: imageUrl ?? subject.cover?.url,
            alignment: Alignment.topCenter,
            fallbackTitle: subject.cleanTitle,
          ),
          Positioned(
            top: 10,
            right: 10,
            child: CornerDots(
              color: DZ.white,
              opacity: 0.4,
              cell: Device.i.isTV ? 10 : 7,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: DZ.scrim,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    subject.cleanTitle.toLowerCase(),
                    style: l.t(DZ.subtitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption ??
                        meta([
                          subject.typeLabel,
                          subject.year,
                          subject.rating,
                          if (p != null && !p.done) formatLeft(p.remaining),
                        ]),
                    style: l.t(DZ.caption),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          if (p != null && p.ratio > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TileProgress(
                ratio: p.ratio,
                color: p.done ? DZ.lime : DZ.cyan,
                height: Device.i.isTV ? 7 : 5,
              ),
            ),
        ],
      ),
    );
  }
}

/// A download's tile in the library: artwork, its real magnitude as a bar, and
/// the transfer state in the colour that means "on this device".
class DownloadTile extends StatelessWidget {
  const DownloadTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onHold,
  });

  final DownloadItem item;
  final VoidCallback onTap;
  final VoidCallback? onHold;

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final (Color bar, String state) = switch (item.status) {
      DownloadStatus.done => (DZ.lime, 'ready'),
      DownloadStatus.downloading => (
          DZ.magenta,
          '${formatBytes(item.received)} of ${formatBytes(item.total)}'
              '${item.bytesPerSecond > 0 ? '  ·  ${formatSpeed(item.bytesPerSecond)}' : ''}'
        ),
      DownloadStatus.paused => (DZ.grey2, 'paused  ·  ${formatBytes(item.received)}'),
      DownloadStatus.queued => (DZ.grey2, 'waiting'),
      DownloadStatus.failed => (DZ.red, item.error ?? 'failed'),
    };

    return MetroTile(
      onTap: onTap,
      onHold: onHold,
      semanticLabel: '${item.subject.cleanTitle}, $state',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Art(url: item.subject.cover?.url, fallbackTitle: item.subject.cleanTitle),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: DZ.scrim,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.subject.cleanTitle.toLowerCase(),
                    style: l.t(DZ.body).copyWith(height: 1.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.isEpisode ? 's${item.se} · e${item.ep}  ·  $state' : state,
                    style: l.t(DZ.caption).copyWith(
                        color: item.status == DownloadStatus.failed ? DZ.red : DZ.grey1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: TileProgress(
              ratio: item.status == DownloadStatus.done ? 1 : item.ratio,
              color: bar,
              height: 4,
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: TileBadge(text: item.quality, fill: DZ.magenta),
          ),
        ],
      ),
    );
  }
}
