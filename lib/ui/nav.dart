import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tokens.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../data/playback.dart';
import '../data/progress.dart';
import 'screens/detail_screen.dart';
import 'screens/grid_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'player/player_screen.dart';

export 'screens/library_screen.dart' show LibraryTab;

/// Every navigation the app performs, in one place, so a screen never has to
/// know how another screen is constructed.
class Nav {
  const Nav._();

  static void openTitle(BuildContext context, Subject subject) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DetailScreen(subject: subject)));
  }

  static void openSearch(BuildContext context, {String? query}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: query, takeFocus: true),
      ),
    );
  }

  static void openGrid(
    BuildContext context, {
    required String title,
    required Future<List<Subject>> Function(int page) loader,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GridScreen(title: title, loader: loader),
      ),
    );
  }

  /// The library is a shell destination, not a pushed route — so this asks the
  /// shell to switch rather than stacking another copy on top.
  static void openLibrary(BuildContext context, LibraryTab tab) {
    ShellRequest.of(context)?.showLibrary(tab);
  }

  /// Back to the catalog, from anywhere inside the shell. Pops any pushed
  /// routes first, so "browse the catalog" lands on the catalog rather than
  /// switching a tab underneath whatever is on top.
  static void goHome(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    ShellRequest.of(context)?.showHome();
  }

  /// Start the player. Returns when it closes.
  static Future<void> play(
    BuildContext context, {
    required Subject subject,
    required PlaybackSource source,
    NextResolver? next,
    DetailData? detail,
  }) => Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: true,
      barrierColor: DZ.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => PlayerScreen(
        subject: subject,
        source: source,
        next: next,
        detail: detail,
      ),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: DZ.ease),
        child: child,
      ),
    ),
  );

  /// Continue a history entry at its saved position, from disk when the title
  /// is downloaded. Falls back to opening the title when nothing is playable.
  static Future<void> resume(
    BuildContext context,
    WidgetRef ref,
    HistoryEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final resolved = await resolveResume(entry.subject, entry.episode);
    if (!context.mounted) return;
    if (resolved == null) {
      openTitle(context, entry.subject);
      return;
    }
    await play(
      context,
      subject: entry.subject,
      source: resolved.source,
      next: resolved.next,
    );
    messenger?.hideCurrentSnackBar();
  }

  /// Resolve and play one episode, with the chain for whatever follows it.
  static Future<void> playEpisode(
    BuildContext context, {
    required Subject subject,
    required DetailData detail,
    required EpisodeRef episode,
    VoidCallback? onUnavailable,
  }) async {
    PlaybackSource? source;
    try {
      source = await streamProvider.resolve(subject, detail, episode);
    } catch (e) {
      if (context.mounted) {
        notify(
          context,
          e is ApiError ? e.message : 'could not reach the player service',
          fill: DZ.red,
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (source == null) {
      onUnavailable?.call();
      return;
    }
    await play(
      context,
      subject: subject,
      source: source.copyWith(episode: episode),
      next: makeNextResolver(subject, detail, detail.seasons, episode),
      detail: detail,
    );
  }
}

/// Lets any screen ask the shell to change destination, without a global key
/// or a navigator hack.
class ShellRequest extends InheritedWidget {
  const ShellRequest({
    super.key,
    required this.showLibrary,
    required this.showHome,
    required super.child,
  });

  final void Function(LibraryTab tab) showLibrary;
  final VoidCallback showHome;

  static ShellRequest? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellRequest>();

  @override
  bool updateShouldNotify(ShellRequest old) => false;
}

/// A flat, lowercase message. Replaces every system alert in the app.
void notify(BuildContext context, String message, {Color fill = DZ.white}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message.toLowerCase()),
      backgroundColor: fill,
      duration: const Duration(seconds: 3),
    ),
  );
}
