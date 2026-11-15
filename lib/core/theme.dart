import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Flutter's own chrome — the caret, the selection handles, the scrollbar, the
/// overscroll glow, the focus ring, the dialog barrier — ships defaults that
/// belong to no design system. Every one of them is themed here, because they
/// are the parts of the surface nobody draws and everybody sees.
ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: DZ.cyan,
    onPrimary: DZ.white,
    secondary: DZ.magenta,
    onSecondary: DZ.white,
    tertiary: DZ.lime,
    onTertiary: DZ.black,
    error: DZ.red,
    onError: DZ.white,
    surface: DZ.black,
    onSurface: DZ.white,
    outline: DZ.grey3,
    outlineVariant: DZ.grey4,
  );

  const text = TextTheme(
    displayLarge: DZ.poster,
    displayMedium: DZ.hero,
    displaySmall: DZ.title,
    headlineMedium: DZ.title,
    headlineSmall: DZ.subtitle,
    titleLarge: DZ.subtitle,
    titleMedium: DZ.bodyStrong,
    bodyLarge: DZ.body,
    bodyMedium: DZ.body,
    bodySmall: DZ.caption,
    labelLarge: DZ.bodyStrong,
    labelMedium: DZ.label,
    labelSmall: DZ.label,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: DZ.black,
    canvasColor: DZ.black,
    fontFamily: DZ.family,
    textTheme: text,
    primaryTextTheme: text,
    splashFactory: NoSplash.splashFactory, // tiles tilt; they do not ripple
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: DZ.cyan,
    dividerTheme: const DividerThemeData(
      color: DZ.grey4,
      thickness: DZ.hairline,
      space: DZ.hairline,
    ),
    // The caret and selection, in the live-state colour.
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: DZ.cyan,
      selectionColor: Color(0x5900BDE3),
      selectionHandleColor: DZ.cyan,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.dragged) || s.contains(WidgetState.hovered)
            ? DZ.cyan
            : DZ.grey3,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      radius: Radius.zero,
      thickness: const WidgetStatePropertyAll(4),
      crossAxisMargin: 0,
      mainAxisMargin: 0,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DZ.cyan,
      linearTrackColor: DZ.grey4,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 2,
      // Metro's own loading mark is a travelling run of dots, not a spinner;
      // Flutter's indicator is themed here for the few places it still shows.
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: DZ.cyan,
      inactiveTrackColor: DZ.grey4,
      thumbColor: DZ.white,
      overlayColor: Colors.transparent,
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DZ.white : DZ.grey2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DZ.cyan : DZ.grey4,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DZ.cyan : DZ.grey3,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(DZ.hairline),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DZ.cyan : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(DZ.white),
      side: const BorderSide(color: DZ.grey2, width: DZ.hairline),
      shape: const RoundedRectangleBorder(borderRadius: DZ.radius),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? DZ.cyan : DZ.grey2,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: DZ.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: DZ.radius,
        side: BorderSide(color: DZ.white, width: DZ.hairline),
      ),
      titleTextStyle: DZ.subtitle,
      contentTextStyle: DZ.body,
      barrierColor: DZ.scrim,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DZ.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalBarrierColor: DZ.scrim,
      shape: RoundedRectangleBorder(borderRadius: DZ.radius),
      showDragHandle: false,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: DZ.white, borderRadius: DZ.radius),
      textStyle: TextStyle(
        fontFamily: DZ.family,
        fontSize: 12,
        height: 20 / 12,
        color: DZ.black,
        fontWeight: FontWeight.w600,
        // Mulish is a variable font: fontWeight alone does not move it, so
        // without this the label rendered at 400 instead of 600.
        fontVariations: DZ.semiboldWeight,
      ),
      waitDuration: Duration(milliseconds: 600),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: DZ.white,
      contentTextStyle: TextStyle(
        fontFamily: DZ.family,
        // 16/24 — body. 14 is not a step on the ramp.
        fontSize: 16,
        height: 24 / 16,
        color: DZ.black,
        fontWeight: FontWeight.w600,
        fontVariations: DZ.semiboldWeight,
      ),
      actionTextColor: DZ.cyan,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: DZ.radius),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: DZ.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: DZ.subtitle,
      iconTheme: IconThemeData(color: DZ.white, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: DZ.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    iconTheme: const IconThemeData(color: DZ.white, size: 22),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: TextStyle(
        fontFamily: DZ.family,
        fontSize: 16,
        color: DZ.grey2,
      ),
      border: OutlineInputBorder(
        borderRadius: DZ.radius,
        borderSide: BorderSide(color: DZ.white, width: DZ.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: DZ.radius,
        borderSide: BorderSide(color: DZ.white, width: DZ.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: DZ.radius,
        borderSide: BorderSide(color: DZ.cyan, width: DZ.hairline),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: DZ.radius,
        borderSide: BorderSide(color: DZ.red, width: DZ.hairline),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _MetroTransition(),
        TargetPlatform.iOS: _MetroTransition(),
        TargetPlatform.windows: _MetroTransition(),
        TargetPlatform.macOS: _MetroTransition(),
        TargetPlatform.linux: _MetroTransition(),
      },
    ),
  );
}

/// Metro's own page move: type leads, the field follows. The incoming page
/// slides a short distance from the leading edge while the outgoing one holds —
/// no cross-dissolve, no scale, no shadow between layers.
class _MetroTransition extends PageTransitionsBuilder {
  const _MetroTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final curved = CurvedAnimation(parent: animation, curve: DZ.ease);
    if (reduced) return FadeTransition(opacity: curved, child: child);
    return SlideTransition(
      position: Tween(
        begin: const Offset(0.12, 0),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

/// Flutter's overscroll glow is a Material artifact with no place here.
class NoGlow extends ScrollBehavior {
  const NoGlow();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // A pointer gets a scrollbar; a finger and a remote do not.
    final platform = getPlatform(context);
    if (platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux) {
      return Scrollbar(controller: details.controller, child: child);
    }
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}
