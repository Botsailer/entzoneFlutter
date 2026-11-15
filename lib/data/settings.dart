import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'store.dart';

enum StreamQualityPref { auto, p1080, p720, p480, p360 }

enum DownloadQualityPref { high, medium, low }

extension StreamQualityPrefX on StreamQualityPref {
  String get id => switch (this) {
    StreamQualityPref.auto => 'auto',
    StreamQualityPref.p1080 => '1080',
    StreamQualityPref.p720 => '720',
    StreamQualityPref.p480 => '480',
    StreamQualityPref.p360 => '360',
  };

  String get label => switch (this) {
    StreamQualityPref.auto => 'auto',
    StreamQualityPref.p1080 => '1080p',
    StreamQualityPref.p720 => '720p',
    StreamQualityPref.p480 => '480p',
    StreamQualityPref.p360 => '360p',
  };

  String get hint => switch (this) {
    StreamQualityPref.auto => 'best the title offers',
    StreamQualityPref.p1080 => 'full hd · uses the most data',
    StreamQualityPref.p720 => 'hd · balanced',
    StreamQualityPref.p480 => 'saves data',
    StreamQualityPref.p360 => 'lowest data use',
  };

  /// Target height; null means take the best available.
  int? get targetHeight =>
      this == StreamQualityPref.auto ? null : int.parse(id);

  static StreamQualityPref parse(String? v) => StreamQualityPref.values
      .firstWhere((e) => e.id == v, orElse: () => StreamQualityPref.auto);
}

extension DownloadQualityPrefX on DownloadQualityPref {
  String get id => name;

  String get label => switch (this) {
    DownloadQualityPref.high => 'high',
    DownloadQualityPref.medium => 'medium',
    DownloadQualityPref.low => 'low',
  };

  String get hint => switch (this) {
    DownloadQualityPref.high => '1080p · best picture, largest files',
    DownloadQualityPref.medium => '720p · good picture, moderate size',
    DownloadQualityPref.low => '480p · smallest files',
  };

  int get targetHeight => switch (this) {
    DownloadQualityPref.high => 1080,
    DownloadQualityPref.medium => 720,
    DownloadQualityPref.low => 480,
  };

  static DownloadQualityPref parse(String? v) => DownloadQualityPref.values
      .firstWhere((e) => e.name == v, orElse: () => DownloadQualityPref.medium);

  /// Closest preference for a height the user picked by hand.
  static DownloadQualityPref forHeight(int h) => h >= 1080
      ? DownloadQualityPref.high
      : h >= 720
      ? DownloadQualityPref.medium
      : DownloadQualityPref.low;
}

/// Index of the best entry at or below [target] in a best-first list of
/// heights. Falls back to the lowest entry when everything is above target.
int pickByHeight(List<int> heights, int? target) {
  if (heights.isEmpty) return 0;
  if (target == null) return 0;
  final i = heights.indexWhere((h) => h > 0 && h <= target);
  return i >= 0 ? i : heights.length - 1;
}

String qualityName(int h) => h >= 2160
    ? '4k ultra hd'
    : h >= 1080
    ? 'full hd'
    : h >= 720
    ? 'hd'
    : h >= 480
    ? 'standard'
    : h > 0
    ? 'data saver'
    : 'auto';

/// Everything the user can change. Persisted as one JSON blob.
class Settings {
  const Settings({
    this.streamQuality = StreamQualityPref.auto,
    this.downloadQuality = DownloadQualityPref.medium,
    this.askDownloadQuality = true,
    this.autoplayNext = true,
    this.autoPip = true,
    this.backgroundPlay = false,
    this.mediaControls = true,
    this.skipSeconds = 10,
    this.longPressSpeed = 2.0,
    this.subtitleSize = 1.0,
    this.subtitleBackground = 0.55,
    this.pauseDetails = true,
    this.wifiOnlyDownloads = true,
    this.preloadNext = true,
  });

  final StreamQualityPref streamQuality;
  final DownloadQualityPref downloadQuality;

  /// Show the quality picker, with real file sizes, before every download.
  final bool askDownloadQuality;

  /// Roll straight into the next episode when one finishes.
  final bool autoplayNext;

  /// Drop into picture-in-picture when leaving the app mid-video (Android 12+).
  final bool autoPip;

  /// Keep audio playing in the background without PiP.
  final bool backgroundPlay;

  /// Lock-screen and notification transport controls.
  final bool mediaControls;

  /// How far the skip buttons and the double-tap jump. User-configurable —
  /// 5, 10, 15, 30 or 60 seconds.
  final int skipSeconds;

  /// Speed while holding down on the video.
  final double longPressSpeed;

  /// Subtitle scale multiplier, 0.75 to 2.0.
  final double subtitleSize;

  /// Opacity of the flat plate behind subtitle text, 0 to 1.
  final double subtitleBackground;

  /// Show cast and description when the video is paused.
  final bool pauseDetails;

  final bool wifiOnlyDownloads;

  /// Resolve and pre-buffer the next episode while the current one plays.
  final bool preloadNext;

  static const skipChoices = [5, 10, 15, 30, 60];
  static const speedChoices = [1.5, 2.0, 2.5, 3.0];

  Settings copyWith({
    StreamQualityPref? streamQuality,
    DownloadQualityPref? downloadQuality,
    bool? askDownloadQuality,
    bool? autoplayNext,
    bool? autoPip,
    bool? backgroundPlay,
    bool? mediaControls,
    int? skipSeconds,
    double? longPressSpeed,
    double? subtitleSize,
    double? subtitleBackground,
    bool? pauseDetails,
    bool? wifiOnlyDownloads,
    bool? preloadNext,
  }) => Settings(
    streamQuality: streamQuality ?? this.streamQuality,
    downloadQuality: downloadQuality ?? this.downloadQuality,
    askDownloadQuality: askDownloadQuality ?? this.askDownloadQuality,
    autoplayNext: autoplayNext ?? this.autoplayNext,
    autoPip: autoPip ?? this.autoPip,
    backgroundPlay: backgroundPlay ?? this.backgroundPlay,
    mediaControls: mediaControls ?? this.mediaControls,
    skipSeconds: skipSeconds ?? this.skipSeconds,
    longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    subtitleSize: subtitleSize ?? this.subtitleSize,
    subtitleBackground: subtitleBackground ?? this.subtitleBackground,
    pauseDetails: pauseDetails ?? this.pauseDetails,
    wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
    preloadNext: preloadNext ?? this.preloadNext,
  );

  Map<String, Object?> toJson() => {
    'streamQuality': streamQuality.id,
    'downloadQuality': downloadQuality.id,
    'askDownloadQuality': askDownloadQuality,
    'autoplayNext': autoplayNext,
    'autoPip': autoPip,
    'backgroundPlay': backgroundPlay,
    'mediaControls': mediaControls,
    'skipSeconds': skipSeconds,
    'longPressSpeed': longPressSpeed,
    'subtitleSize': subtitleSize,
    'subtitleBackground': subtitleBackground,
    'pauseDetails': pauseDetails,
    'wifiOnlyDownloads': wifiOnlyDownloads,
    'preloadNext': preloadNext,
  };

  static Settings fromJson(Object? j) {
    if (j is! Map) return const Settings();
    const d = Settings();
    return Settings(
      streamQuality: StreamQualityPrefX.parse(j['streamQuality'] as String?),
      downloadQuality: DownloadQualityPrefX.parse(
        j['downloadQuality'] as String?,
      ),
      askDownloadQuality:
          j['askDownloadQuality'] as bool? ?? d.askDownloadQuality,
      autoplayNext: j['autoplayNext'] as bool? ?? d.autoplayNext,
      autoPip: j['autoPip'] as bool? ?? d.autoPip,
      backgroundPlay: j['backgroundPlay'] as bool? ?? d.backgroundPlay,
      mediaControls: j['mediaControls'] as bool? ?? d.mediaControls,
      skipSeconds: (j['skipSeconds'] as num?)?.toInt() ?? d.skipSeconds,
      longPressSpeed:
          (j['longPressSpeed'] as num?)?.toDouble() ?? d.longPressSpeed,
      subtitleSize: (j['subtitleSize'] as num?)?.toDouble() ?? d.subtitleSize,
      subtitleBackground:
          (j['subtitleBackground'] as num?)?.toDouble() ?? d.subtitleBackground,
      pauseDetails: j['pauseDetails'] as bool? ?? d.pauseDetails,
      wifiOnlyDownloads: j['wifiOnlyDownloads'] as bool? ?? d.wifiOnlyDownloads,
      preloadNext: j['preloadNext'] as bool? ?? d.preloadNext,
    );
  }
}

const _key = 'settings:v1';

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() =>
      Store.i.getJson(_key, Settings.fromJson) ?? const Settings();

  void update(Settings Function(Settings) change) {
    final next = change(state);
    state = next;
    Store.i.setJson(_key, next.toJson());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

/// Read settings outside the widget tree (the downloader, the player's native
/// bridge) without threading a Ref through every call.
Settings currentSettings() =>
    Store.i.getJson(_key, Settings.fromJson) ?? const Settings();
