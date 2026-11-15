import 'dart:async';

import 'package:dio/dio.dart';

import 'api.dart';
import 'downloads.dart';
import 'models.dart';
import 'progress.dart';
import 'settings.dart';

/// One selectable rendition.
class StreamQuality {
  const StreamQuality({
    required this.label,
    required this.url,
    this.height = 0,
    this.headers = const {},
    this.sizeBytes,
  });

  final String label;
  final String url;
  final int height;

  /// Sent with the media request. The catalog's CDN answers 429 without the
  /// Referer the play endpoint handed back, so this is never empty for a
  /// network stream.
  final Map<String, String> headers;

  final int? sizeBytes;
}

// Audio and subtitle track selection is media_kit's job: it enumerates what a
// container actually carries and switches between them without touching the
// position. Defining parallel types here would only shadow its own.

/// Everything the player needs to start. Resolved by a [StreamProvider].
class PlaybackSource {
  const PlaybackSource({
    required this.kind,
    required this.title,
    required this.qualities,
    this.poster,
    this.episode,
    this.offline = false,
    this.episodeTitle,
  });

  /// 'full' plays and counts toward history; 'trailer' does neither.
  final String kind;
  final String title;

  /// Best first.
  final List<StreamQuality> qualities;
  final String? poster;
  final EpisodeRef? episode;

  /// Playing a downloaded file from disk.
  final bool offline;
  final String? episodeTitle;

  bool get isFull => kind == 'full';

  PlaybackSource copyWith({
    EpisodeRef? episode,
    List<StreamQuality>? qualities,
  }) => PlaybackSource(
    kind: kind,
    title: title,
    qualities: qualities ?? this.qualities,
    poster: poster,
    episode: episode ?? this.episode,
    offline: offline,
    episodeTitle: episodeTitle,
  );
}

/// Resolves something playable. Swapping the backend is a one-line change at
/// startup; the player, episode grid, subtitles and resume logic are unaware.
abstract class StreamSourceProvider {
  String get id;

  /// Can this backend play individual episodes?
  bool get supportsEpisodes;

  Future<PlaybackSource?> resolve(
    Subject subject,
    DetailData? detail, [
    EpisodeRef? episode,
  ]);
}

/// Official trailers, which the catalog returns with the title details.
class TrailerProvider implements StreamSourceProvider {
  const TrailerProvider();

  @override
  String get id => 'trailer';

  @override
  bool get supportsEpisodes => false;

  @override
  Future<PlaybackSource?> resolve(
    Subject subject,
    DetailData? detail, [
    EpisodeRef? episode,
  ]) async {
    final s = detail?.subject ?? subject;
    final url = s.trailerUrl ?? subject.trailerUrl;
    if (url == null || url.isEmpty) return null;
    final h = s.trailerHeight ?? subject.trailerHeight;
    return PlaybackSource(
      kind: 'trailer',
      title: subject.cleanTitle,
      episodeTitle: 'trailer',
      qualities: [
        StreamQuality(
          label: h != null ? '${h}p' : 'auto',
          url: url,
          height: h ?? 0,
        ),
      ],
      poster: s.trailerPoster ?? subject.cover?.url,
    );
  }
}

/// Real streaming from MovieBox. A series plays per episode; a movie with no
/// free stream falls back to its trailer rather than a dead end.
class MovieBoxProvider implements StreamSourceProvider {
  const MovieBoxProvider();

  @override
  String get id => 'moviebox';

  @override
  bool get supportsEpisodes => true;

  @override
  Future<PlaybackSource?> resolve(
    Subject subject,
    DetailData? detail, [
    EpisodeRef? episode,
  ]) async {
    final isSeries = subject.isSeries;
    // A series has no single "main" source — the episode grid drives playback.
    if (isSeries && episode == null) return null;

    final se = episode?.season ?? 0;
    final ep = episode?.episode ?? 0;
    final title = subject.cleanTitle;
    final epTitle = episode == null ? null : 's$se · e$ep';

    // Downloaded? Play from disk — no data, no connection needed.
    await Downloads.i.ready;
    final local = Downloads.i.offlineFile(subject.subjectId, se, ep);
    if (local != null) {
      return PlaybackSource(
        kind: 'full',
        title: title,
        episodeTitle: epTitle,
        qualities: [
          StreamQuality(
            label: local.quality.isEmpty ? 'offline' : local.quality,
            url: local.path,
          ),
        ],
        poster: subject.cover?.url,
        episode: episode,
        offline: true,
      );
    }

    final playable = detail?.subject ?? subject;
    final result = await Api.i.play(
      playable.subjectId,
      playable.detailPath,
      se: se,
      ep: ep,
    );

    if (result.streams.isNotEmpty) {
      return PlaybackSource(
        kind: 'full',
        title: title,
        episodeTitle: epTitle,
        qualities: result.streams
            .map(
              (s) => StreamQuality(
                label: s.label,
                url: s.url,
                height: s.height,
                // Not optional: the CDN 429s without it.
                headers: result.mediaHeaders,
                sizeBytes: s.size,
              ),
            )
            .toList(),
        poster: subject.cover?.url,
        episode: episode,
      );
    }

    // Nothing playable: offer the trailer for a movie; an episode reports
    // "unavailable" so the grid can mark that tile rather than lie.
    if (episode == null) {
      return const TrailerProvider().resolve(subject, detail);
    }
    return null;
  }
}

StreamSourceProvider _provider = const MovieBoxProvider();

StreamSourceProvider get streamProvider => _provider;

void setStreamProvider(StreamSourceProvider p) => _provider = p;

/// Index of the rendition to start on, given the Stream Quality setting.
int pickQualityIndex(List<StreamQuality> qualities, StreamQualityPref pref) =>
    pickByHeight(
      qualities
          .map(
            (q) => q.height > 0
                ? q.height
                : int.tryParse(q.label.replaceAll(RegExp(r'\D'), '')) ?? 0,
          )
          .toList(),
      pref.targetHeight,
    );

// ───────────────────────── next episode ─────────────────────────

/// What the player gets when it asks for the next episode: something to play,
/// and the handle to whatever follows it. A class rather than a record because
/// the chain refers to itself and a typedef cannot.
class NextEpisode {
  const NextEpisode(this.source, this.next);
  final PlaybackSource source;
  final NextResolver? next;
}

/// Resolves the next episode, chainably. Drives the Next button and the
/// auto-advance toggle.
typedef NextResolver = Future<NextEpisode?> Function();

EpisodeRef? nextEpisodeRef(List<SeasonResource> seasons, EpisodeRef ep) {
  final list = seasons.where((s) => s.se > 0).toList()
    ..sort((a, b) => a.se.compareTo(b.se));
  for (final s in list) {
    if (s.se == ep.season && ep.episode < s.maxEp) {
      return EpisodeRef(ep.season, ep.episode + 1);
    }
  }
  for (final s in list) {
    if (s.se > ep.season) return EpisodeRef(s.se, 1);
  }
  return null;
}

NextResolver? makeNextResolver(
  Subject subject,
  DetailData? detail,
  List<SeasonResource> seasons,
  EpisodeRef ep,
) {
  final n = seasons.isEmpty ? null : nextEpisodeRef(seasons, ep);
  if (n == null) return null;
  return () async {
    final src = await streamProvider.resolve(subject, detail, n);
    if (src == null) return null;
    return NextEpisode(
      src.copyWith(episode: n),
      makeNextResolver(subject, detail, seasons, n),
    );
  };
}

/// Resolve what to play to continue a history entry, plus the next-episode
/// chain for a series. Null means nothing is playable — open the title instead.
Future<NextEpisode?> resolveResume(Subject subject, EpisodeRef? episode) async {
  final src = await streamProvider.resolve(subject, null, episode);
  if (src == null || !src.isFull) return null;
  NextResolver? next;
  if (episode != null) {
    final detail = await Api.i
        .detail(subject.detailPath)
        .then<DetailData?>((d) => d)
        .catchError((_) => null);
    next = makeNextResolver(
      subject,
      detail,
      detail?.seasons ?? const [],
      episode,
    );
  }
  return NextEpisode(src.copyWith(episode: episode), next);
}

// ───────────────────────── pre-buffering ─────────────────────────

/// "The next complete state is already loaded" — the discipline donated by the
/// vertical-feed challenger. While the current episode plays, the next one's
/// stream is resolved and its first bytes are pulled, so pressing Next or
/// letting auto-advance fire cuts straight in with no spinner.
class NextPreloader {
  NextPreloader();

  final _dio = Dio();
  CancelToken? _cancel;
  NextResolver? _for;
  NextEpisode? _ready;

  /// The pre-resolved next episode, if it is the one being asked for.
  NextEpisode? take(NextResolver? resolver) {
    if (resolver != null && identical(resolver, _for)) {
      final r = _ready;
      _ready = null;
      _for = null;
      return r;
    }
    return null;
  }

  /// Start warming [resolver]. Safe to call repeatedly; it only works once per
  /// resolver and never throws into the player.
  void warm(NextResolver? resolver) {
    if (resolver == null || identical(resolver, _for)) return;
    cancel();
    _for = resolver;
    unawaited(() async {
      try {
        final r = await resolver();
        if (!identical(resolver, _for) || r == null) return;
        _ready = r;
        await _touch(r.source);
      } catch (_) {
        // A failed warm-up is invisible: the player resolves normally instead.
      }
    }());
  }

  /// Ask the CDN for the first few hundred KB so the connection is open, the
  /// redirect is followed, and the file's head is in the OS cache.
  Future<void> _touch(PlaybackSource src) async {
    if (src.offline || src.qualities.isEmpty) return;
    final q = src
        .qualities[pickQualityIndex(q0(src), currentSettings().streamQuality)];
    _cancel = CancelToken();
    try {
      await _dio.get<List<int>>(
        q.url,
        cancelToken: _cancel,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {...q.headers, 'Range': 'bytes=0-262143'},
          validateStatus: (s) => s != null && s < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
    } catch (_) {}
  }

  static List<StreamQuality> q0(PlaybackSource s) => s.qualities;

  void cancel() {
    _cancel?.cancel();
    _cancel = null;
    _ready = null;
    _for = null;
  }

  void dispose() {
    cancel();
    _dio.close(force: true);
  }
}
