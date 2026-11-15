import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// How the app is being driven. This is the only thing that changes layout —
/// not screen size alone, because a 10-foot TV and a 10-inch tablet can report
/// similar logical widths while needing completely different targets.
enum Hands {
  /// Phone or tablet: fingers, portrait-first, bottom navigation.
  touch,

  /// Android TV / leanback: a D-pad ten feet away, landscape, no pointer.
  remote,

  /// Windows / macOS / Linux / web: pointer, keyboard, a resizable window.
  pointer,
}

class Device {
  Device._();
  static final Device i = Device._();

  Hands hands = Hands.touch;
  bool get isTV => hands == Hands.remote;
  bool get isDesktop => hands == Hands.pointer;
  bool get isTouch => hands == Hands.touch;

  int androidSdk = 0;

  /// Picture-in-picture needs API 26; automatic PiP on leaving the app needs 31.
  bool get supportsPip => !isTV && onAndroid && androidSdk >= 26;
  bool get supportsAutoPip => !isTV && onAndroid && androidSdk >= 31;

  /// A native foreground download service exists only on Android.
  bool get hasDownloadService => onAndroid;

  static bool get onAndroid => !kIsWeb && Platform.isAndroid;
  static bool get onIOS => !kIsWeb && Platform.isIOS;
  static bool get onDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Resolve once at startup, before the first frame.
  static Future<void> detect() async {
    final d = Device.i;
    if (kIsWeb) {
      d.hands = Hands.pointer;
      return;
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      d.hands = Hands.pointer;
      return;
    }
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        d.androidSdk = info.version.sdkInt;
        // Leanback is the honest signal: Android TV declares it, phones do not.
        final tv =
            info.systemFeatures.contains('android.software.leanback') ||
            info.systemFeatures.contains('android.hardware.type.television');
        d.hands = tv ? Hands.remote : Hands.touch;
      } catch (_) {
        d.hands = Hands.touch;
      }
      return;
    }
    d.hands = Hands.touch; // iOS
  }
}

/// Everything the layout needs, derived once per build from the real constraints.
///
/// Metro's grid is a fixed column count, not a fixed tile size: the tile grows
/// with the field. That is what makes one grammar work from 390px to a 4K TV.
class Layout {
  const Layout({
    required this.hands,
    required this.size,
    required this.columns,
    required this.margin,
    required this.textScale,
    required this.overscan,
    required this.safe,
  });

  final Hands hands;
  final Size size;

  /// Columns in the tile field.
  final int columns;

  /// Side margin.
  final double margin;

  /// Multiplier on the type ramp. A TV sits ten feet away and needs every step
  /// larger; a phone uses the ramp as drawn.
  final double textScale;

  /// TV safe area — the 5% a television may crop.
  final EdgeInsets overscan;

  /// OS insets (notch, nav bar, window chrome).
  final EdgeInsets safe;

  bool get isTV => hands == Hands.remote;
  bool get isDesktop => hands == Hands.pointer;
  bool get isTouch => hands == Hands.touch;

  /// Navigation lives at the bottom for a thumb, and down the left edge for a
  /// remote or a pointer — where the hero's own left rail sits.
  bool get railNav => hands != Hands.touch;

  /// Width of one grid column, gutters removed.
  double get columnWidth {
    final usable = size.width - margin * 2 - DZ.gap * (columns - 1);
    return usable / columns;
  }

  /// Pixel width of a tile spanning [span] columns.
  double span(int span) => columnWidth * span + DZ.gap * (span - 1);

  double get fieldWidth => size.width - margin * 2;

  TextStyle t(TextStyle base) =>
      base.copyWith(fontSize: (base.fontSize ?? 16) * textScale);

  static Layout of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final hands = Device.i.hands;

    final (int cols, double marginPx, double scale) = switch (hands) {
      // A remote at ten feet: fewer, larger tiles and bigger type.
      Hands.remote => (
        w >= 1800 ? 8 : 6,
        DZ.marginWide,
        w >= 1800 ? 1.45 : 1.3,
      ),
      // A pointer: the field fills the window, so column count follows width.
      Hands.pointer => (
        w >= 1920
            ? 10
            : w >= 1440
            ? 8
            : w >= 1100
            ? 6
            : w >= 760
            ? 5
            : 4,
        w >= 1100 ? DZ.marginWide : 24.0,
        1.0,
      ),
      // Fingers: four columns on a phone, six on a tablet.
      Hands.touch => (
        w >= 900
            ? 6
            : w >= 600
            ? 5
            : 4,
        w >= 600 ? 24.0 : DZ.margin,
        w >= 600 ? 1.08 : 1.0,
      ),
    };

    return Layout(
      hands: hands,
      size: mq.size,
      columns: cols,
      margin: marginPx,
      textScale: scale,
      overscan: hands == Hands.remote
          ? EdgeInsets.symmetric(
              horizontal: mq.size.width * 0.04,
              vertical: mq.size.height * 0.04,
            )
          : EdgeInsets.zero,
      safe: mq.padding,
    );
  }
}

/// Reduced motion, read from the OS. Every authored move degrades to a fade.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
