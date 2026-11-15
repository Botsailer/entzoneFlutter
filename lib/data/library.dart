import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'progress.dart';
import 'store.dart';

// ───────────────────────── watch history ─────────────────────────

/// One entry per title — the latest episode watched and where it stopped.
/// Newest first. Written by the player while it plays.
class HistoryEntry {
  const HistoryEntry({
    required this.subject,
    required this.position,
    required this.duration,
    required this.at,
    this.episode,
  });

  final Subject subject;
  final EpisodeRef? episode;
  final double position;
  final double duration;
  final int at;

  double get ratio => duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
  bool get finished => isWatchedAt(position, duration);
  double get remaining => (duration - position).clamp(0, double.infinity);

  Map<String, Object?> toJson() => {
        'subject': subject.toJson(),
        'episode': episode?.toJson(),
        'position': position,
        'duration': duration,
        'at': at,
      };

  static HistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = Subject.from(j['subject']);
    if (s == null) return null;
    return HistoryEntry(
      subject: s,
      episode: EpisodeRef.fromJson(j['episode']),
      position: (j['position'] as num?)?.toDouble() ?? 0,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      at: (j['at'] as num?)?.toInt() ?? 0,
    );
  }
}

const _historyKey = 'history:v1';
const _historyMax = 120;

class HistoryNotifier extends Notifier<List<HistoryEntry>> {
  @override
  List<HistoryEntry> build() =>
      Store.i.getJson(
          _historyKey,
          (j) => (j as List? ?? const [])
              .map(HistoryEntry.fromJson)
              .whereType<HistoryEntry>()
              .toList()) ??
      const [];

  /// Called repeatedly by the player. Titles that were barely opened are
  /// ignored so a mis-tap never shows up in Continue Watching.
  void record(Subject subject, EpisodeRef? episode, double position, double duration) {
    if (subject.subjectId.isEmpty || position < 3) return;
    final entry = HistoryEntry(
      subject: subject,
      episode: episode,
      position: position,
      duration: duration,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    state = [
      entry,
      ...state.where((e) => e.subject.subjectId != subject.subjectId),
    ].take(_historyMax).toList();
    _persist();
  }

  void remove(String subjectId) {
    state = state.where((e) => e.subject.subjectId != subjectId).toList();
    _persist();
  }

  Future<void> clear() async {
    state = const [];
    await Store.i.remove(_historyKey);
  }

  HistoryEntry? of(String subjectId) {
    for (final e in state) {
      if (e.subject.subjectId == subjectId) return e;
    }
    return null;
  }

  /// Titles worth offering as "continue": started, not finished.
  List<HistoryEntry> get continueWatching =>
      state.where((e) => !e.finished && e.position > 10).toList();

  void _persist() =>
      Store.i.setJson(_historyKey, state.map((e) => e.toJson()).toList());
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<HistoryEntry>>(HistoryNotifier.new);

/// Day bucket for grouping the history list.
String dayBucket(int ms) {
  final start = DateTime.now().copyWith(
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
  final d = start.millisecondsSinceEpoch;
  const day = 86400000;
  if (ms >= d) return 'today';
  if (ms >= d - day) return 'yesterday';
  if (ms >= d - 6 * day) return 'this week';
  if (ms >= d - 29 * day) return 'this month';
  return 'earlier';
}

// ───────────────────────── watchlist ─────────────────────────

const _listKey = 'watchlist:v1';

class WatchlistNotifier extends Notifier<List<Subject>> {
  @override
  List<Subject> build() =>
      Store.i.getJson(
          _listKey,
          (j) => (j as List? ?? const [])
              .map(Subject.from)
              .whereType<Subject>()
              .toList()) ??
      const [];

  bool contains(String subjectId) =>
      state.any((s) => s.subjectId == subjectId);

  /// Returns true when the title is now saved.
  bool toggle(Subject s) {
    final has = contains(s.subjectId);
    state = has
        ? state.where((x) => x.subjectId != s.subjectId).toList()
        : [s, ...state];
    _persist();
    return !has;
  }

  void remove(String subjectId) {
    state = state.where((s) => s.subjectId != subjectId).toList();
    _persist();
  }

  Future<void> clear() async {
    state = const [];
    await Store.i.remove(_listKey);
  }

  void _persist() =>
      Store.i.setJson(_listKey, state.map((s) => s.toJson()).toList());
}

final watchlistProvider =
    NotifierProvider<WatchlistNotifier, List<Subject>>(WatchlistNotifier.new);

// ───────────────────────── recent searches ─────────────────────────

const _searchKey = 'search:recent:v1';
const _searchMax = 12;

class RecentSearchNotifier extends Notifier<List<String>> {
  @override
  List<String> build() =>
      Store.i.getJson(
          _searchKey,
          (j) => (j as List? ?? const []).map((e) => e.toString()).toList()) ??
      const [];

  void add(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    state = [t, ...state.where((s) => s.toLowerCase() != t.toLowerCase())]
        .take(_searchMax)
        .toList();
    Store.i.setJson(_searchKey, state);
  }

  void remove(String term) {
    state = state.where((s) => s != term).toList();
    Store.i.setJson(_searchKey, state);
  }

  Future<void> clear() async {
    state = const [];
    await Store.i.remove(_searchKey);
  }
}

final recentSearchProvider =
    NotifierProvider<RecentSearchNotifier, List<String>>(RecentSearchNotifier.new);
