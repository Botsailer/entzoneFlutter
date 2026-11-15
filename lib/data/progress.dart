import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store.dart';

/// Where you stopped, per movie or per episode.
///
/// This is the app's most sacred piece of state: the direction contract's first
/// principle is that the user's position is never lost — not to a quality
/// change, not to an episode switch, not to a rotation or a window resize.
class Progress {
  const Progress({
    required this.position,
    required this.duration,
    required this.at,
    this.done = false,
  });

  /// Seconds.
  final double position;
  final double duration;

  /// When it was saved, in millis.
  final int at;

  /// Watched to the end (credits count). The next play starts from zero.
  final bool done;

  double get ratio => done
      ? 1
      : duration > 0
          ? (position / duration).clamp(0.0, 1.0)
          : 0.0;

  double get remaining => (duration - position).clamp(0, double.infinity);

  Map<String, Object?> toJson() => {
        'position': position,
        'duration': duration,
        'at': at,
        if (done) 'done': true,
      };

  static Progress? fromJson(Object? j) {
    if (j is! Map) return null;
    return Progress(
      position: (j['position'] as num?)?.toDouble() ?? 0,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      at: (j['at'] as num?)?.toInt() ?? 0,
      done: j['done'] == true,
    );
  }
}

class EpisodeRef {
  const EpisodeRef(this.season, this.episode);
  final int season;
  final int episode;

  @override
  bool operator ==(Object other) =>
      other is EpisodeRef && other.season == season && other.episode == episode;

  @override
  int get hashCode => Object.hash(season, episode);

  @override
  String toString() => 's$season e$episode';

  String get short => 's$season·e$episode';

  Map<String, Object?> toJson() => {'season': season, 'episode': episode};

  static EpisodeRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = (j['season'] as num?)?.toInt();
    final e = (j['episode'] as num?)?.toInt();
    if (s == null || e == null) return null;
    return EpisodeRef(s, e);
  }
}

const progressPrefix = 'progress:';

String progressKey(String subjectId, [EpisodeRef? ep]) =>
    '$progressPrefix$subjectId:${ep == null ? 'main' : '${ep.season}:${ep.episode}'}';

/// One rule for "watched": inside the last 4%, or the last 15 seconds,
/// whichever is longer — i.e. the credits are rolling.
bool isWatchedAt(double position, double duration) =>
    duration > 0 && position >= duration - (15.0 > duration * 0.04 ? 15.0 : duration * 0.04);

/// Live map of every known resume point, so an episode tile's progress bar and
/// a Continue button update the moment the player saves — no reload, no
/// invalidation dance.
class ProgressNotifier extends Notifier<Map<String, Progress>> {
  @override
  Map<String, Progress> build() {
    final out = <String, Progress>{};
    for (final k in Store.i.keys.where((k) => k.startsWith(progressPrefix))) {
      final p = Store.i.getJson<Progress?>(k, Progress.fromJson);
      if (p != null) out[k] = p;
    }
    return out;
  }

  Progress? of(String subjectId, [EpisodeRef? ep]) => state[progressKey(subjectId, ep)];

  /// Save a position. Watched to the end → keep a `done` marker so the episode
  /// shows as finished and Continue moves on. Barely started → forget it, so a
  /// mis-tap does not litter the library.
  void save(String subjectId, EpisodeRef? ep, double position, double duration) {
    final key = progressKey(subjectId, ep);
    final done = isWatchedAt(position, duration);
    final now = DateTime.now().millisecondsSinceEpoch;

    final Progress? value = done
        ? Progress(position: duration, duration: duration, at: now, done: true)
        : position < 5
            ? null
            : Progress(position: position, duration: duration, at: now);

    final next = Map<String, Progress>.from(state);
    if (value == null) {
      if (next.remove(key) == null) return; // nothing changed
      Store.i.remove(key);
    } else {
      next[key] = value;
      Store.i.setJson(key, value.toJson());
    }
    state = next;
  }

  void clearOne(String subjectId, [EpisodeRef? ep]) {
    final key = progressKey(subjectId, ep);
    if (!state.containsKey(key)) return;
    final next = Map<String, Progress>.from(state)..remove(key);
    state = next;
    Store.i.remove(key);
  }

  /// Forget every saved position.
  Future<void> clearAll() async {
    state = const {};
    await Store.i.removeWhere((k) => k.startsWith(progressPrefix));
  }
}

final progressProvider =
    NotifierProvider<ProgressNotifier, Map<String, Progress>>(ProgressNotifier.new);

/// Read a resume point from outside the widget tree.
Progress? readProgress(String subjectId, [EpisodeRef? ep]) =>
    Store.i.getJson<Progress?>(progressKey(subjectId, ep), Progress.fromJson);
