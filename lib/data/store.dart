import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Flat key-value persistence, the Flutter counterpart of the RN app's
/// AsyncStorage layer. Everything the app remembers between launches goes
/// through here: the session token, the response cache, settings, watch
/// progress, history, the watchlist and the download queue.
///
/// Reads are served from an in-memory mirror so a widget build never awaits,
/// and writes are coalesced — watch progress is saved every few seconds while
/// a video plays, and hitting the disk on each one would be wasteful.
class Store {
  Store._();
  static final Store i = Store._();

  late final SharedPreferences _prefs;
  bool _ready = false;

  final _pending = <String, String?>{};
  Timer? _flush;

  Future<void> init() async {
    if (_ready) return;
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  bool get isReady => _ready;

  // ───────────────────────── strings ─────────────────────────

  String? getStringSync(String key) {
    if (_pending.containsKey(key)) return _pending[key];
    return _ready ? _prefs.getString(key) : null;
  }

  Future<String?> getString(String key) async {
    await init();
    return getStringSync(key);
  }

  Future<void> setString(String key, String value) async {
    await init();
    _pending[key] = value;
    _scheduleFlush();
  }

  Future<void> remove(String key) async {
    await init();
    _pending[key] = null;
    _scheduleFlush();
  }

  // ───────────────────────── json ─────────────────────────

  T? getJson<T>(String key, T Function(Object?) parse) {
    final raw = getStringSync(key);
    if (raw == null) return null;
    try {
      return parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Object? value) =>
      setString(key, jsonEncode(value));

  // ───────────────────────── bulk ─────────────────────────

  Set<String> get keys {
    final all = _ready ? {..._prefs.getKeys()} : <String>{};
    for (final e in _pending.entries) {
      if (e.value == null) {
        all.remove(e.key);
      } else {
        all.add(e.key);
      }
    }
    return all;
  }

  Future<void> removeWhere(bool Function(String key) test) async {
    await init();
    await flush();
    for (final k in keys.where(test).toList()) {
      await _prefs.remove(k);
      _pending.remove(k);
    }
  }

  /// Byte size of the values under matching keys — what the settings screen
  /// reports as "cached". Approximate by design: it counts UTF-16 code units.
  Future<int> bytesWhere(bool Function(String key) test) async {
    await init();
    var total = 0;
    for (final k in keys.where(test)) {
      total += (getStringSync(k)?.length ?? 0) * 2;
    }
    return total;
  }

  /// Read many keys at once — used to load a whole season's watch progress in
  /// one pass instead of one await per episode.
  Map<String, String?> getMany(Iterable<String> ks) => {
    for (final k in ks) k: getStringSync(k),
  };

  // ───────────────────────── flushing ─────────────────────────

  void _scheduleFlush() {
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 400), flush);
  }

  /// Write everything buffered. Called on a timer, and explicitly when the app
  /// goes to the background or the player closes, so nothing is lost on a kill.
  Future<void> flush() async {
    _flush?.cancel();
    _flush = null;
    if (!_ready || _pending.isEmpty) return;
    final batch = Map<String, String?>.from(_pending);
    _pending.clear();
    for (final e in batch.entries) {
      try {
        if (e.value == null) {
          await _prefs.remove(e.key);
        } else {
          await _prefs.setString(e.key, e.value!);
        }
      } catch (_) {
        // A failed write is not worth taking the app down for; the value stays
        // correct in memory for this session.
      }
    }
  }
}

/// A tiny observable value. Riverpod owns app state; this exists for the few
/// places a plain module (the downloader, the player's progress writer) needs
/// to publish changes without depending on the widget tree.
class Signal<T> {
  Signal(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Stream<T> get stream => _controller.stream;

  void dispose() => _controller.close();
}
