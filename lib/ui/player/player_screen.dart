import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../data/api.dart';
import '../../data/library.dart';
import '../../data/media_proxy.dart';
import '../../data/models.dart';
import '../../data/native.dart';
import '../../data/playback.dart';
import '../../data/progress.dart';
import '../../data/settings.dart';
import '../../data/store.dart';
import 'pause_overlay.dart';
import 'player_controls.dart';
import 'track_sheet.dart';

enum PlayerSheet { none, quality, audio, captions, speed, settings }

/// The full-screen player.
///
/// One engine for the whole session: changing quality or rolling into the next
/// episode re-opens the *same* player at the *same* position rather than
/// building a new one, which is what keeps picture-in-picture alive across an
/// auto-advance and what makes a quality switch cost nothing.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.subject,
    required this.source,
    this.next,
    this.detail,
  });

  final Subject subject;
  final PlaybackSource source;
  final NextResolver? next;

  /// Cast and synopsis for the pause overlay. Fetched here when not supplied.
  final DetailData? detail;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, WindowListener {
  late final Player _player;
  late final VideoController _video;
  final _preloader = NextPreloader();
  final _mediaProxy = MediaProxy();
  final _subs = <StreamSubscription>[];
  final _focus = FocusNode(debugLabel: 'player');

  late PlaybackSource _source;
  NextResolver? _next;
  DetailData? _detail;

  int _qualityIndex = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  double _volume = 100;

  /// Where mute returns to. Restoring to a flat 100% instead would shout at
  /// anyone who had turned the film down before muting it.
  double _lastAudible = 100;
  bool _completed = false;
  String? _error;

  bool _controlsVisible = true;
  bool _locked = false;
  bool _windowFullscreen = false;
  bool _windowMaximized = false;
  bool _fullscreenOwned = false;
  PlayerSheet _sheet = PlayerSheet.none;
  BoxFit _fit = BoxFit.contain;
  double _speed = 1.0;
  double? _speedBeforeHold;

  /// Set while scrubbing, so the bar follows the finger and not the stream.
  Duration? _scrub;

  String _toast = '';
  Timer? _toastTimer;
  Timer? _hideTimer;
  Timer? _saveTimer;

  /// The position to restore once the newly-opened media reports a duration.
  Duration? _restoreTo;

  /// Guards the window between opening a new media and it becoming ready, so
  /// progress for the *old* episode is never written under the new one.
  bool _switching = false;

  /// Set once the player is on its way out, so a second back press, an
  /// Escape repeat or a remote `stop` cannot pop twice.
  bool _closing = false;

  String? _audioTrackId;
  String? _subtitleTrackId;
  Tracks _tracks = const Tracks();

  static const _hideAfter = Duration(seconds: 4);

  Settings get _settings => ref.read(settingsProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      windowManager.addListener(this);
      _syncWindowState();
    }

    _source = widget.source;
    _next = widget.next;
    _detail = widget.detail;
    _qualityIndex = pickQualityIndex(
      _source.qualities,
      currentSettings().streamQuality,
    );

    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'depressedzone',
        bufferSize: 48 * 1024 * 1024,
      ),
    );
    _video = VideoController(_player);

    _wire();
    _openCurrent(restoreFromSaved: true);

    WakelockPlus.enable();
    Native.i.setPlayerActive(true);
    Native.i.setImmersive(true);
    _applyOrientation(lock: true);

    if (_detail == null) _loadDetail();
    _poke();
  }

  void _wire() {
    _subs.addAll([
      _player.stream.playing.listen((v) {
        if (!mounted) return;
        setState(() => _playing = v);
        _publishNowPlaying();
        if (v) {
          _poke();
        } else {
          // A deliberate pause holds the controls and the detail panel open.
          _hideTimer?.cancel();
          setState(() => _controlsVisible = true);
        }
      }),
      _player.stream.position.listen((p) {
        if (!mounted) return;
        setState(() => _position = p);
        _maybeSave();
        _maybeWarmNext();
      }),
      _player.stream.duration.listen((d) {
        if (!mounted) return;
        setState(() => _duration = d);
        if (d > Duration.zero) _onReady();
      }),
      _player.stream.buffer.listen((b) {
        if (mounted) setState(() => _buffer = b);
      }),
      _player.stream.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      _player.stream.volume.listen((v) {
        if (mounted && v != _volume) setState(() => _volume = v);
      }),
      _player.stream.completed.listen((c) {
        if (!mounted || !c) return;
        setState(() => _completed = true);
        _onCompleted();
      }),
      _player.stream.tracks.listen((t) {
        if (mounted) setState(() => _tracks = t);
      }),
      _player.stream.error.listen((e) {
        if (!mounted || e.isEmpty) return;
        setState(() => _error = _mediaError());
      }),
      // Remote, headset and lock-screen keys.
      Native.i.remote.listen(_onRemote),
    ]);
  }

  Future<void> _loadDetail() async {
    try {
      final d = await Api.i.detail(widget.subject.detailPath);
      if (mounted) setState(() => _detail = d);
    } catch (_) {
      // The pause overlay simply shows less; it is never an error state.
    }
  }

  // ───────────────────────── opening media ─────────────────────────

  StreamQuality get _quality =>
      _source.qualities[_qualityIndex.clamp(0, _source.qualities.length - 1)];

  String _mediaError() {
    final status = _mediaProxy.lastUpstreamStatus;
    if (status != null) {
      return 'video host rejected this stream (HTTP $status).';
    }
    return 'this video could not be opened.';
  }

  Future<RefreshedMedia?> _refreshMedia(int height, EpisodeRef? episode) async {
    final subject = _detail?.subject ?? widget.subject;
    final result = await Api.i.play(
      subject.subjectId,
      subject.detailPath,
      se: episode?.season ?? 0,
      ep: episode?.episode ?? 0,
      forceRefresh: true,
    );
    if (result.streams.isEmpty) return null;
    final matches = result.streams.where((stream) => stream.height == height);
    final stream = matches.isEmpty ? result.streams.first : matches.first;
    return (url: stream.url, headers: result.mediaHeaders);
  }

  Future<void> _openCurrent({
    bool restoreFromSaved = false,
    Duration? at,
    bool autoplay = true,
  }) async {
    if (_source.qualities.isEmpty) {
      setState(() => _error = 'This title returned no playable video.');
      return;
    }

    var start = at;
    if (restoreFromSaved) {
      final saved = readProgress(widget.subject.subjectId, _source.episode);
      if (saved != null && !saved.done && saved.position > 5) {
        start = Duration(seconds: saved.position.round());
      }
    }

    _restoreTo = start;
    _switching = true;
    setState(() {
      _error = null;
      _completed = false;
      _buffering = true;
    });

    final q = _quality;
    try {
      var mediaUrl = q.url;
      Map<String, String>? mediaHeaders = q.headers.isEmpty ? null : q.headers;
      if (!kIsWeb && Platform.isWindows && _source.isFull && !_source.offline) {
        final episode = _source.episode;
        mediaUrl = await _mediaProxy.register(
          url: q.url,
          headers: q.headers,
          refresh: () => _refreshMedia(q.height, episode),
        );
        mediaHeaders = null;
      }
      await _player.open(
        Media(mediaUrl, httpHeaders: mediaHeaders, start: start),
        play: autoplay,
      );
      await _player.setRate(_speed);
      if (start != null && start > Duration.zero) {
        _flash('resumed from ${formatTime(start.inSeconds)}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = _mediaError());
    }
  }

  Future<void> _retryCurrent() async {
    if (_source.isFull && !_source.offline) {
      try {
        final previousHeight = _quality.height;
        final refreshed = await _refreshMedia(previousHeight, _source.episode);
        if (!mounted) return;
        if (refreshed == null) {
          setState(
            () => _error = 'this episode has no playable stream right now.',
          );
          return;
        }
        final old = _quality;
        final updated = StreamQuality(
          label: old.label,
          url: refreshed.url,
          height: old.height,
          headers: refreshed.headers,
          sizeBytes: old.sizeBytes,
        );
        final qualities = [..._source.qualities];
        qualities[_qualityIndex] = updated;
        setState(() => _source = _source.copyWith(qualities: qualities));
      } catch (e) {
        if (mounted) {
          setState(
            () => _error = e is ApiError
                ? e.message
                : 'could not refresh this stream.',
          );
        }
        return;
      }
    }
    await _openCurrent(at: _position);
  }

  /// Called the first time the newly-opened media reports a real duration.
  void _onReady() {
    if (!_switching) return;
    _switching = false;
    final to = _restoreTo;
    _restoreTo = null;
    if (to != null && to > Duration.zero && to < _duration) {
      // `start:` handles this for most sources; the seek is the belt to its
      // braces, because a stream that ignores --start would otherwise lose the
      // position, which this app treats as unacceptable.
      if ((_position - to).abs() > const Duration(seconds: 3)) {
        _player.seek(to);
      }
    }
    _restoreTrackSelections();
    _publishNowPlaying();
  }

  /// Re-apply the viewer's audio and caption choices to the newly opened file.
  void _restoreTrackSelections() {
    final audioId = _audioTrackId;
    if (audioId != null) {
      final match = _player.state.tracks.audio.where((t) => t.id == audioId);
      if (match.isNotEmpty) _player.setAudioTrack(match.first);
    }
    final subId = _subtitleTrackId;
    if (subId != null) {
      if (subId == 'off') {
        _player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        final match = _player.state.tracks.subtitle.where((t) => t.id == subId);
        if (match.isNotEmpty) _player.setSubtitleTrack(match.first);
      }
    }
  }

  // ───────────────────────── progress ─────────────────────────

  double _lastSavedAt = 0;

  void _maybeSave() {
    if (_switching || _duration == Duration.zero) return;
    final secs = _position.inMilliseconds / 1000.0;
    if ((secs - _lastSavedAt).abs() < 5) return;
    _lastSavedAt = secs;
    _writeProgress();
  }

  void _writeProgress() {
    if (_duration == Duration.zero) return;
    final secs = _position.inMilliseconds / 1000.0;
    final total = _duration.inMilliseconds / 1000.0;
    ref
        .read(progressProvider.notifier)
        .save(widget.subject.subjectId, _source.episode, secs, total);
    if (_source.isFull) {
      ref
          .read(historyProvider.notifier)
          .record(widget.subject, _source.episode, secs, total);
    }
  }

  // ───────────────────────── next episode ─────────────────────────

  void _maybeWarmNext() {
    if (!_settings.preloadNext || _next == null || _duration == Duration.zero) {
      return;
    }
    // Warm once the episode is most of the way through — early enough that the
    // handover is instant, late enough not to spend data on a title the viewer
    // abandons in the first minute.
    final left = _duration - _position;
    if (left <= const Duration(minutes: 2)) _preloader.warm(_next);
  }

  Future<void> _playNext({bool auto = false}) async {
    final resolver = _next;
    if (resolver == null) {
      if (!auto) _flash('this is the last episode');
      return;
    }

    _writeProgress();
    if (!auto) _flash('loading the next episode…');

    final preloaded = _preloader.take(resolver);
    final result = preloaded ?? await resolver();

    if (!mounted) return;
    if (result == null) {
      _flash('the next episode has no source right now');
      return;
    }

    _preloader.cancel();
    _lastSavedAt = 0;
    setState(() {
      _source = result.source;
      _next = result.next;
      _duration = Duration.zero;
      _position = Duration.zero;
      _qualityIndex = pickQualityIndex(
        _source.qualities,
        currentSettings().streamQuality,
      );
      _completed = false;
    });
    await _openCurrent(restoreFromSaved: true);
    final ep = _source.episode;
    if (ep != null) _flash('now playing ${ep.short}');
  }

  void _onCompleted() {
    _writeProgress();
    if (_settings.autoplayNext && _next != null) {
      _playNext(auto: true);
    } else {
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
    }
  }

  // ───────────────────────── controls ─────────────────────────

  void _poke() {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (_playing && _sheet == PlayerSheet.none && _scrub == null) {
      _hideTimer = Timer(_hideAfter, () {
        if (mounted && _playing) setState(() => _controlsVisible = false);
      });
    }
  }

  void _flash(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = '');
    });
  }

  void _togglePlay() {
    _player.playOrPause();
    _poke();
  }

  void _skip(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration
              ? _duration
              : target);
    _player.seek(clamped);
    _flash('${seconds > 0 ? '+' : ''}$seconds seconds');
    _poke();
  }

  void _seekTo(Duration d) {
    _player.seek(d);
    _poke();
  }

  Future<void> _changeQuality(int index) async {
    if (index == _qualityIndex) {
      setState(() => _sheet = PlayerSheet.none);
      return;
    }
    final at = _position;
    final wasPlaying = _playing;
    setState(() {
      _qualityIndex = index;
      _sheet = PlayerSheet.none;
    });
    await _openCurrent(at: at, autoplay: wasPlaying);
    _flash('quality ${_quality.label}');
  }

  void _changeSpeed(double s) {
    setState(() {
      _speed = s;
      _sheet = PlayerSheet.none;
    });
    _player.setRate(s);
    _flash(s == 1 ? 'normal speed' : '${s}x');
  }

  void _cycleFit() {
    const order = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
    final next = order[(order.indexOf(_fit) + 1) % order.length];
    setState(() => _fit = next);
    _flash(switch (next) {
      BoxFit.contain => 'fit',
      BoxFit.cover => 'fill',
      _ => 'stretch',
    });
    _poke();
  }

  void _selectAudio(String id) {
    final t = _tracks.audio.where((t) => t.id == id);
    if (t.isEmpty) return;
    _player.setAudioTrack(t.first);
    setState(() {
      _audioTrackId = id;
      _sheet = PlayerSheet.none;
    });
    _flash('audio: ${_audioLabel(t.first)}');
  }

  void _selectSubtitle(String id) {
    setState(() {
      _subtitleTrackId = id;
      _sheet = PlayerSheet.none;
    });
    if (id == 'off') {
      _player.setSubtitleTrack(SubtitleTrack.no());
      _flash('captions off');
      return;
    }
    final t = _tracks.subtitle.where((t) => t.id == id);
    if (t.isEmpty) return;
    _player.setSubtitleTrack(t.first);
    _flash('captions: ${_subtitleLabel(t.first)}');
  }

  void _holdSpeed(bool on) {
    if (on) {
      if (_speedBeforeHold != null) return;
      _speedBeforeHold = _speed;
      final fast = _settings.longPressSpeed;
      _player.setRate(fast);
      setState(() => _speed = fast);
      _flash('${fast}x');
    } else {
      final before = _speedBeforeHold;
      if (before == null) return;
      _speedBeforeHold = null;
      _player.setRate(before);
      setState(() => _speed = before);
      _toastTimer?.cancel();
      setState(() => _toast = '');
    }
  }

  Future<void> _enterPip() async {
    setState(() => _sheet = PlayerSheet.none);
    final ok = await Native.i.enterPip();
    if (!ok && mounted) _flash('picture-in-picture is not available here');
  }

  void _onRemote(RemoteAction a) {
    if (!mounted) return;
    switch (a) {
      case RemoteAction.toggle:
        _togglePlay();
      case RemoteAction.play:
        _player.play();
      case RemoteAction.pause:
        _player.pause();
      case RemoteAction.rewind:
        _skip(-_settings.skipSeconds);
      case RemoteAction.forward:
        _skip(_settings.skipSeconds);
      case RemoteAction.next:
        _playNext();
      case RemoteAction.previous:
        _skip(-_settings.skipSeconds);
      case RemoteAction.stop:
        _close();
    }
  }

  void _publishNowPlaying() {
    if (!_settings.mediaControls) return;
    Native.i.setNowPlaying(
      title: widget.subject.cleanTitle,
      subtitle:
          _source.episodeTitle ??
          (_source.kind == 'trailer' ? 'trailer' : 'depressedzone'),
      artworkUrl: _source.poster,
      playing: _playing,
      position: _position,
      duration: _duration,
      hasNext: _next != null,
    );
  }

  // ───────────────────────── lifecycle ─────────────────────────

  void _applyOrientation({required bool lock}) {
    if (!Device.i.isTouch) return;
    SystemChrome.setPreferredOrientations(
      lock
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
            ],
    );
  }

  Future<void> _syncWindowState() async {
    final fullscreen = await windowManager.isFullScreen();
    final maximized = await windowManager.isMaximized();
    if (mounted) {
      setState(() {
        _windowFullscreen = fullscreen;
        _windowMaximized = maximized;
      });
    }
  }

  Future<void> _toggleFullscreen() async {
    if (kIsWeb || !Platform.isWindows) return;
    final next = !(await windowManager.isFullScreen());
    await windowManager.setFullScreen(next);
    _fullscreenOwned = next;
    if (mounted) setState(() => _windowFullscreen = next);
    _poke();
  }

  Future<void> _toggleMaximize() async {
    if (kIsWeb || !Platform.isWindows) return;
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      _fullscreenOwned = false;
    } else if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncWindowState();
    _poke();
  }

  @override
  void onWindowMaximize() => _syncWindowState();

  @override
  void onWindowUnmaximize() => _syncWindowState();

  @override
  void onWindowEnterFullScreen() => _syncWindowState();

  @override
  void onWindowLeaveFullScreen() => _syncWindowState();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is transient — the notification shade, the app switcher, an
    // incoming call. Pausing there would stop the video every time the shade
    // is pulled down, so only a real background counts.
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    try {
      _writeProgress();
    } catch (_) {}
    unawaited(Store.i.flush());
    if (_settings.backgroundPlay) return;
    // Entering picture-in-picture backgrounds the activity *before* the
    // platform reports the mode change, so `pipActive` is still false here.
    // Pausing on that signal alone paused every PiP window the instant it
    // opened; an armed auto-PiP is given a moment to confirm.
    if (Native.i.pipActive.value) return;
    if (_pipPossible) {
      Timer(const Duration(milliseconds: 400), () {
        if (!mounted || Native.i.pipActive.value) return;
        if (!_settings.backgroundPlay) _player.pause();
      });
      return;
    }
    _player.pause();
  }

  /// True when this exit may still turn into a picture-in-picture window.
  bool get _pipPossible =>
      Device.i.supportsPip && _settings.autoPip && _playing && !_closing;

  /// Every volume change runs through here: the drag, the arrow keys and the
  /// control in the bar all have to agree on what mute returns to.
  void _setVolume(double value, {bool flash = true}) {
    final v = value.clamp(0.0, 100.0);
    if (v > 0) _lastAudible = v;
    _player.setVolume(v);
    if (mounted) setState(() => _volume = v);
    if (flash) _flash(v == 0 ? 'muted' : 'volume ${v.round()}%');
  }

  void _toggleMute() {
    if (_volume == 0) {
      _setVolume(_lastAudible > 0 ? _lastAudible : 100);
    } else {
      _lastAudible = _volume;
      _setVolume(0);
    }
  }

  /// The single back path: sheets and the lock close first, a full-screen
  /// window un-full-screens, and only then does the player leave.
  ///
  /// Returns true when it handled the gesture without leaving.
  bool _handleBack() {
    if (_sheet != PlayerSheet.none) {
      setState(() => _sheet = PlayerSheet.none);
      return true;
    }
    if (_locked) {
      setState(() => _locked = false);
      _poke();
      return true;
    }
    if (_windowFullscreen && !kIsWeb && Platform.isWindows) {
      _toggleFullscreen();
      return true;
    }
    _close();
    return false;
  }

  /// Leaves the player. Pops directly rather than through `maybePop`, which
  /// this route's `PopScope(canPop: false)` would refuse — re-entering the
  /// pop callback instead of closing.
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    try {
      _writeProgress();
    } catch (_) {}
    unawaited(Store.i.flush());
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      _closing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      windowManager.removeListener(this);
      if (_fullscreenOwned) unawaited(windowManager.setFullScreen(false));
    }
    // The last write happens here as well as on the way out, because the OS
    // can tear this route down without a close. `ref` is still live during
    // dispose, but a provider that has already gone must not take the app
    // with it.
    try {
      _writeProgress();
    } catch (_) {}
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    _saveTimer?.cancel();
    // Streams first: an event delivered after this point would call setState
    // on a dead element.
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _preloader.dispose();
    _focus.dispose();
    // The player owns a native texture that the `Video` child below is still
    // rendering at this instant — a State is disposed before its children.
    // Tearing libmpv down now takes the process with it on Windows, so the
    // engine is released once the tree is gone.
    final player = _player;
    final proxy = _mediaProxy;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The loopback server has to die first. `Player.dispose` ends in
      // `mpv_terminate_destroy`, which blocks until libmpv's demuxer thread
      // joins -- and that thread is parked on a Range read against this very
      // server, which is served by the isolate the dispose is blocking. Wait
      // for libmpv before closing and the two wait on each other forever:
      // the window stops painting and Windows marks it Not Responding.
      // Forcing the sockets shut makes the read fail, the demuxer exits, and
      // dispose returns.
      proxy.close();
      try {
        await player.dispose();
      } catch (_) {}
    });
    WakelockPlus.disable();
    Native.i.setPlayerActive(false);
    Native.i.setImmersive(false);
    Native.i.clearNowPlaying();
    Native.i.setAutoPip(false);
    _applyOrientation(lock: false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Store.i.flush();
    super.dispose();
  }

  // ───────────────────────── labels ─────────────────────────

  String _audioLabel(AudioTrack t) {
    final title = (t.title ?? '').trim();
    final lang = (t.language ?? '').trim();
    if (title.isNotEmpty &&
        lang.isNotEmpty &&
        !title.toLowerCase().contains(lang.toLowerCase())) {
      return '$title · $lang';
    }
    if (title.isNotEmpty) return title;
    if (lang.isNotEmpty) return lang;
    return 'track ${t.id}';
  }

  String _subtitleLabel(SubtitleTrack t) {
    final title = (t.title ?? '').trim();
    final lang = (t.language ?? '').trim();
    if (title.isNotEmpty) return lang.isNotEmpty ? '$title · $lang' : title;
    if (lang.isNotEmpty) return lang;
    return 'track ${t.id}';
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final l = Layout.of(context);

    // Arm automatic picture-in-picture only while this screen is alive.
    if (Device.i.supportsAutoPip) {
      Native.i.setAutoPip(settings.autoPip && _playing);
    }

    final showPauseDetails =
        settings.pauseDetails &&
        !_playing &&
        !_buffering &&
        !_completed &&
        _sheet == PlayerSheet.none &&
        !_locked &&
        _error == null &&
        _duration > Duration.zero;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: DZ.black,
        body: Shortcuts(
          shortcuts: _shortcuts(settings),
          child: Actions(
            actions: _actions(),
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              child: ValueListenableBuilder<bool>(
                valueListenable: Native.i.pipActive,
                builder: (context, inPip, _) {
                  // In picture-in-picture only the video is visible.
                  if (inPip) {
                    return Video(
                      controller: _video,
                      fit: BoxFit.contain,
                      controls: NoVideoControls,
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── the picture ──
                      Video(
                        controller: _video,
                        fit: _fit,
                        controls: NoVideoControls,
                        subtitleViewConfiguration: SubtitleViewConfiguration(
                          visible: true,
                          style: TextStyle(
                            fontFamily: DZ.family,
                            fontSize:
                                30 *
                                settings.subtitleSize *
                                (l.isTV ? 1.4 : 1.0),
                            height: 1.3,
                            color: DZ.white,
                            backgroundColor: DZ.black.withValues(
                              alpha: settings.subtitleBackground,
                            ),
                          ),
                          padding: EdgeInsets.only(
                            bottom:
                                (_controlsVisible ? 140 : 44) +
                                l.overscan.bottom,
                            left: 32,
                            right: 32,
                          ),
                        ),
                      ),

                      // ── gestures ──
                      PlayerGestures(
                        locked: _locked,
                        skipSeconds: settings.skipSeconds,
                        onTap: () {
                          if (_sheet != PlayerSheet.none) {
                            setState(() => _sheet = PlayerSheet.none);
                          } else if (_controlsVisible && _playing) {
                            _hideTimer?.cancel();
                            setState(() => _controlsVisible = false);
                          } else {
                            _poke();
                          }
                        },
                        onDoubleTapLeft: () => _skip(-settings.skipSeconds),
                        onDoubleTapRight: () => _skip(settings.skipSeconds),
                        onDoubleTapFullscreen: !kIsWeb && Platform.isWindows
                            ? _toggleFullscreen
                            : null,
                        onHoldStart: () => _holdSpeed(true),
                        onHoldEnd: () => _holdSpeed(false),
                        onVolumeDelta: (d) => _setVolume(_volume - d * 100),
                      ),

                      // ── netflix-style pause panel ──
                      if (_detail != null || showPauseDetails)
                        PauseOverlay(
                          subject: widget.subject,
                          detail: _detail,
                          episodeLabel: _source.episodeTitle,
                          position: _position,
                          duration: _duration,
                          visible: showPauseDetails,
                        ),

                      // ── buffering ──
                      if (_buffering && _error == null)
                        const Center(child: MetroBuffering()),

                      // ── chrome ──
                      if (_error == null && _locked)
                        LockedChrome(
                          visible: _controlsVisible,
                          onUnlock: () {
                            setState(() => _locked = false);
                            _poke();
                          },
                        )
                      else if (_error == null)
                        PlayerChrome(
                          visible:
                              _controlsVisible && _sheet == PlayerSheet.none,
                          title: widget.subject.cleanTitle,
                          subtitle: _source.episodeTitle,
                          offline: _source.offline,
                          trailer: _source.kind == 'trailer',
                          playing: _playing,
                          position: _scrub ?? _position,
                          duration: _duration,
                          buffered: _buffer,
                          speed: _speed,
                          qualityLabel: _source.qualities.isEmpty
                              ? '—'
                              : _quality.label,
                          fitLabel: switch (_fit) {
                            BoxFit.contain => 'fit',
                            BoxFit.cover => 'fill',
                            _ => 'stretch',
                          },
                          captionsOn:
                              _subtitleTrackId != null &&
                              _subtitleTrackId != 'off',
                          hasNext: _next != null,
                          autoNext: settings.autoplayNext,
                          skipSeconds: settings.skipSeconds,
                          canPip: Device.i.supportsPip,
                          onMinimize: !kIsWeb && Platform.isWindows
                              ? () => windowManager.minimize()
                              : null,
                          onToggleMaximize: !kIsWeb && Platform.isWindows
                              ? _toggleMaximize
                              : null,
                          onToggleFullscreen: !kIsWeb && Platform.isWindows
                              ? _toggleFullscreen
                              : null,
                          isMaximized: _windowMaximized,
                          isFullscreen: _windowFullscreen,
                          onClose: _close,
                          onPlayPause: _togglePlay,
                          onSkip: _skip,
                          onSeekStart: () {
                            _hideTimer?.cancel();
                            setState(() => _scrub = _position);
                          },
                          onSeekUpdate: (d) => setState(() => _scrub = d),
                          onSeekEnd: (d) {
                            setState(() => _scrub = null);
                            _seekTo(d);
                          },
                          onNext: _next == null ? null : () => _playNext(),
                          volume: _volume,
                          onVolume: _setVolume,
                          onToggleMute: _toggleMute,
                          onToggleAutoNext: () {
                            final on = !settings.autoplayNext;
                            ref
                                .read(settingsProvider.notifier)
                                .update((s) => s.copyWith(autoplayNext: on));
                            _flash(
                              on
                                  ? 'auto-play next is on'
                                  : 'auto-play next is off',
                            );
                            _poke();
                          },
                          onLock: () {
                            setState(() => _locked = true);
                            _poke();
                          },
                          onFit: _cycleFit,
                          onPip: _enterPip,
                          onSheet: (s) {
                            _hideTimer?.cancel();
                            setState(() => _sheet = s);
                          },
                        ),

                      // ── up next ──
                      if (_completed && _next != null && !settings.autoplayNext)
                        UpNextCard(onPlay: () => _playNext(), onClose: _close),

                      // ── the settings panel ──
                      if (_sheet != PlayerSheet.none) _buildSheet(settings),

                      // ── toast ──
                      if (_toast.isNotEmpty) PlayerToast(message: _toast),
                      if (_error != null)
                        PlayerError(
                          message: _error!,
                          onRetry: _retryCurrent,
                          onClose: _close,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(Settings settings) {
    void close() => setState(() => _sheet = PlayerSheet.none);

    return switch (_sheet) {
      PlayerSheet.quality => TrackSheet(
        title: 'quality',
        selectedId: '$_qualityIndex',
        onClose: close,
        onSelect: (id) => _changeQuality(int.parse(id)),
        options: [
          for (var i = 0; i < _source.qualities.length; i++)
            TrackOption(
              id: '$i',
              label: _source.qualities[i].label,
              detail: meta([
                qualityName(_source.qualities[i].height),
                _source.qualities[i].sizeBytes == null
                    ? null
                    : formatBytes(_source.qualities[i].sizeBytes),
              ]),
            ),
        ],
        footer: const Text('changing quality keeps your place in the video.'),
      ),
      PlayerSheet.audio => TrackSheet(
        title: 'audio',
        selectedId: _audioTrackId ?? _player.state.track.audio.id,
        onClose: close,
        onSelect: _selectAudio,
        options: [
          for (final t in _tracks.audio.where(
            (t) => t.id != 'auto' && t.id != 'no',
          ))
            TrackOption(id: t.id, label: _audioLabel(t)),
        ],
        footer: const Text(
          'audio tracks come from the video file. most titles in this '
          'catalog ship a single track.',
        ),
      ),
      PlayerSheet.captions => TrackSheet(
        title: 'subtitles',
        selectedId: _subtitleTrackId ?? 'off',
        onClose: close,
        onSelect: _selectSubtitle,
        options: [
          const TrackOption(id: 'off', label: 'off'),
          for (final t in _tracks.subtitle.where(
            (t) => t.id != 'auto' && t.id != 'no',
          ))
            TrackOption(id: t.id, label: _subtitleLabel(t)),
        ],
        footer: const Text('size and background are in settings → playback.'),
      ),
      PlayerSheet.speed => TrackSheet(
        title: 'speed',
        selectedId: '$_speed',
        onClose: close,
        onSelect: (id) => _changeSpeed(double.parse(id)),
        options: [
          for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            TrackOption(id: '$s', label: s == 1.0 ? 'normal' : '${s}x'),
        ],
      ),
      PlayerSheet.settings => TrackSheet(
        title: 'skip by',
        selectedId: '${settings.skipSeconds}',
        onClose: close,
        onSelect: (id) {
          ref
              .read(settingsProvider.notifier)
              .update((s) => s.copyWith(skipSeconds: int.parse(id)));
          setState(() => _sheet = PlayerSheet.none);
          _flash('skip is now $id seconds');
        },
        options: [
          for (final s in Settings.skipChoices)
            TrackOption(id: '$s', label: '$s seconds'),
        ],
        footer: const Text(
          'applies to the skip buttons, a double tap on the picture, '
          'the arrow keys and the remote.',
        ),
      ),
      PlayerSheet.none => const SizedBox.shrink(),
    };
  }

  // ───────────────────────── keyboard ─────────────────────────

  Map<ShortcutActivator, Intent> _shortcuts(Settings s) => {
    const SingleActivator(LogicalKeyboardKey.space): const _TogglePlay(),
    const SingleActivator(LogicalKeyboardKey.keyK): const _TogglePlay(),
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
        const _TogglePlay(),
    SingleActivator(LogicalKeyboardKey.arrowRight): _Skip(s.skipSeconds),
    SingleActivator(LogicalKeyboardKey.arrowLeft): _Skip(-s.skipSeconds),
    const SingleActivator(LogicalKeyboardKey.keyL): const _Skip(10),
    const SingleActivator(LogicalKeyboardKey.keyJ): const _Skip(-10),
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _Volume(0.1),
    const SingleActivator(LogicalKeyboardKey.arrowDown): const _Volume(-0.1),
    const SingleActivator(LogicalKeyboardKey.keyM): const _Mute(),
    const SingleActivator(LogicalKeyboardKey.keyF): const _Fit(),
    const SingleActivator(LogicalKeyboardKey.keyC): const _Sheet(
      PlayerSheet.captions,
    ),
    const SingleActivator(LogicalKeyboardKey.keyA): const _Sheet(
      PlayerSheet.audio,
    ),
    const SingleActivator(LogicalKeyboardKey.keyQ): const _Sheet(
      PlayerSheet.quality,
    ),
    const SingleActivator(LogicalKeyboardKey.keyN): const _Next(),
    const SingleActivator(LogicalKeyboardKey.escape): const _Back(),
    const SingleActivator(LogicalKeyboardKey.f11): const _Fullscreen(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): const _Next(),
  };

  Map<Type, Action<Intent>> _actions() => {
    _TogglePlay: CallbackAction<_TogglePlay>(
      onInvoke: (_) {
        _togglePlay();
        return null;
      },
    ),
    _Skip: CallbackAction<_Skip>(
      onInvoke: (i) {
        _skip(i.seconds);
        return null;
      },
    ),
    _Volume: CallbackAction<_Volume>(
      onInvoke: (i) {
        _setVolume(_volume + i.delta * 100);
        return null;
      },
    ),
    _Mute: CallbackAction<_Mute>(
      onInvoke: (_) {
        _toggleMute();
        return null;
      },
    ),
    _Fit: CallbackAction<_Fit>(
      onInvoke: (_) {
        _cycleFit();
        return null;
      },
    ),
    _Sheet: CallbackAction<_Sheet>(
      onInvoke: (i) {
        setState(() => _sheet = i.sheet);
        return null;
      },
    ),
    _Next: CallbackAction<_Next>(
      onInvoke: (_) {
        _playNext();
        return null;
      },
    ),
    _Back: CallbackAction<_Back>(
      onInvoke: (_) {
        _handleBack();
        return null;
      },
    ),
    _Fullscreen: CallbackAction<_Fullscreen>(
      onInvoke: (_) {
        _toggleFullscreen();
        return null;
      },
    ),
  };
}

class _TogglePlay extends Intent {
  const _TogglePlay();
}

class _Fullscreen extends Intent {
  const _Fullscreen();
}

class _Skip extends Intent {
  const _Skip(this.seconds);
  final int seconds;
}

class _Volume extends Intent {
  const _Volume(this.delta);
  final double delta;
}

class _Mute extends Intent {
  const _Mute();
}

class _Fit extends Intent {
  const _Fit();
}

class _Sheet extends Intent {
  const _Sheet(this.sheet);
  final PlayerSheet sheet;
}

class _Next extends Intent {
  const _Next();
}

class _Back extends Intent {
  const _Back();
}
