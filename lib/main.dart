import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/device.dart';
import 'core/theme.dart';
import 'core/tokens.dart';
import 'data/downloads.dart';
import 'data/native.dart';
import 'data/store.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // libmpv, once, before any Player is constructed.
  MediaKit.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: DZ.black,
      systemNavigationBarDividerColor: DZ.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: DepressedZoneApp()));
}

Future<void> _initializeApp() async {
  final splashMinimum = Future<void>.delayed(const Duration(milliseconds: 650));
  await Store.i.init();
  await Device.detect();
  Native.i.init();

  // Reconcile interrupted downloads while the splash is visible.
  await Downloads.i.init();

  if (Device.i.isDesktop && !kIsWeb) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(760, 560),
        backgroundColor: DZ.black,
        title: 'depressedzone',
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  if (!kIsWeb && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }

  if (Device.i.isTouch) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  await splashMinimum;
}

class DepressedZoneApp extends StatefulWidget {
  const DepressedZoneApp({super.key});

  @override
  State<DepressedZoneApp> createState() => _DepressedZoneAppState();
}

class _DepressedZoneAppState extends State<DepressedZoneApp>
    with WidgetsBindingObserver {
  late Future<void> _startup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup = _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Buffered writes — watch positions above all — reach disk before the OS
    // is free to kill the process.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      Store.i.flush();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'depressedzone',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    darkTheme: buildTheme(),
    themeMode: ThemeMode.dark,
    scrollBehavior: const NoGlow(),
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      // A television's select key and a gamepad's A button activate the
      // focused tile, exactly as Enter does.
      const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.gameButtonA):
          const ActivateIntent(),
    },
    builder: (context, child) {
      // The type ramp is fixed by the design system and scaled per device
      // class in Layout; the OS text-size slider is honoured within bounds
      // rather than allowed to break every tile.
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          textScaler: TextScaler.linear(
            mq.textScaler.scale(1.0).clamp(0.9, 1.35),
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: FutureBuilder<void>(
      future: _startup,
      builder: (context, state) {
        if (state.hasError) {
          return SplashScreen(
            error: 'could not finish starting the app',
            onRetry: () => setState(() => _startup = _initializeApp()),
          );
        }
        if (state.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }
        return const AppShell();
      },
    ),
  );
}
