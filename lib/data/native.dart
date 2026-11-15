import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/device.dart';

/// Remote and media-key actions the native side forwards to the player.
enum RemoteAction { toggle, play, pause, rewind, forward, next, previous, stop }

/// The bridge to the platform code this app needs and Flutter does not provide:
/// picture-in-picture, the media session (lock-screen and notification
/// transport), the download foreground service, and TV remote media keys.
///
/// Every method is a no-op where the platform has no such thing, so call sites
/// never branch on the OS.
class Native {
  Native._();
  static final Native i = Native._();

  static const _channel = MethodChannel('depressedzone/native');
  static const _events = EventChannel('depressedzone/events');

  final _remote = StreamController<RemoteAction>.broadcast();

  /// Media keys from a TV remote, a gamepad, a headset or the lock screen.
  Stream<RemoteAction> get remote => _remote.stream;

  final pipActive = ValueNotifier<bool>(false);

  bool _wired = false;

  void init() {
    if (_wired || kIsWeb || !Device.onAndroid) return;
    _wired = true;
    _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['type']?.toString();
      if (type == 'remote') {
        final action = RemoteAction.values
            .where((a) => a.name == event['action']?.toString())
            .firstOrNull;
        if (action != null) _remote.add(action);
      } else if (type == 'pip') {
        pipActive.value = event['active'] == true;
      }
    }, onError: (_) {});
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (kIsWeb || !Device.onAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[native] $method failed: ${e.message}');
      return null;
    }
  }

  // ───────────────────────── picture in picture ─────────────────────────

  Future<bool> enterPip({double aspectWidth = 16, double aspectHeight = 9}) async =>
      await _call<bool>('enterPip', {
        'width': aspectWidth.round(),
        'height': aspectHeight.round(),
      }) ??
      false;

  /// Arm automatic PiP, so leaving the app mid-video keeps the picture
  /// (Android 12+). Disarmed whenever the player is not on screen.
  Future<void> setAutoPip(bool enabled, {double aspectWidth = 16, double aspectHeight = 9}) =>
      _call('setAutoPip', {
        'enabled': enabled,
        'width': aspectWidth.round(),
        'height': aspectHeight.round(),
      });

  // ───────────────────────── media session ─────────────────────────

  /// Publish what is playing to the lock screen, the notification shade and
  /// the PiP window's own buttons.
  Future<void> setNowPlaying({
    required String title,
    required String subtitle,
    String? artworkUrl,
    required bool playing,
    required Duration position,
    required Duration duration,
    required bool hasNext,
  }) =>
      _call('setNowPlaying', {
        'title': title,
        'subtitle': subtitle,
        'artwork': artworkUrl,
        'playing': playing,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'hasNext': hasNext,
      });

  Future<void> clearNowPlaying() => _call('clearNowPlaying');

  /// While true, the activity keeps media keys and asks the system not to
  /// sleep the session.
  Future<void> setPlayerActive(bool active) => _call('setPlayerActive', {'active': active});

  // ───────────────────────── download service ─────────────────────────

  Future<void> startDownloadService({required String title, required String subtitle}) =>
      _call('startDownloadService', {'title': title, 'subtitle': subtitle});

  Future<void> updateDownloadProgress({required String title, required int percent}) =>
      _call('updateDownloadProgress', {'title': title, 'percent': percent});

  Future<void> notifyDownloadComplete({required String title, required String subtitle}) =>
      _call('notifyDownloadComplete', {'title': title, 'subtitle': subtitle});

  Future<void> stopDownloadService() => _call('stopDownloadService');

  /// Android 13+ asks before a notification may be posted.
  Future<bool> ensureNotificationPermission() async =>
      await _call<bool>('ensureNotificationPermission') ?? true;

  // ───────────────────────── screen ─────────────────────────

  /// Keep the display on and, where supported, hide the system bars while a
  /// video is on screen.
  Future<void> setImmersive(bool on) => _call('setImmersive', {'on': on});
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
