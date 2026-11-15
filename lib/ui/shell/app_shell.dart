import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device.dart';
import '../../core/tokens.dart';
import '../../data/downloads.dart';
import '../nav.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import 'header.dart';

/// The app's frame.
///
/// One shell, three sets of hands. A phone puts navigation in a bottom bar
/// where a thumb reaches it; a television and a desktop get the header band,
/// whose structure — brand, source switch, text navigation, inline search —
/// carries over from the reference prototype as a brand commitment.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Dest _dest = Dest.home;
  Source _source = Source.catalog;
  LibraryTab _libraryTab = LibraryTab.continueWatching;

  final _searchController = TextEditingController();
  final _libraryKey = GlobalKey<LibraryScreenState>();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showLibrary(LibraryTab tab) {
    setState(() {
      _libraryTab = tab;
      _dest = Dest.library;
    });
    _libraryKey.currentState?.showTab(tab);
  }

  void _go(Dest d) {
    if (d == _dest) return;
    setState(() => _dest = d);
  }

  @override
  Widget build(BuildContext context) {
    final l = Layout.of(context);
    final downloads = ref.watch(downloadsProvider).asData?.value ?? Downloads.i.items;
    final activeDownloads = downloads.where((d) => d.active).length;

    // The source switch swaps what "home" means: the live catalog, or only
    // what is already on this device.
    final homePane = _source == Source.device
        ? const LibraryScreen(initialTab: LibraryTab.downloads)
        : const HomeScreen();

    return LibraryRequest(
      show: _showLibrary,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              _go(Dest.search),
          const SingleActivator(LogicalKeyboardKey.slash): () => _go(Dest.search),
          const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () =>
              _go(Dest.home),
          const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () =>
              _go(Dest.search),
          const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () =>
              _go(Dest.library),
          const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () =>
              _go(Dest.settings),
        },
        child: Scaffold(
          backgroundColor: DZ.black,
          body: Column(
            children: [
              if (l.railNav)
                HeaderBand(
                  dest: _dest,
                  onDest: _go,
                  source: _source,
                  onSource: (s) => setState(() => _source = s),
                  searchController: _searchController,
                  downloadCount: activeDownloads,
                  onSearch: (q) {
                    if (q.trim().isEmpty) return;
                    Nav.openSearch(context, query: q.trim());
                    _searchController.clear();
                  },
                )
              else
                SizedBox(height: l.safe.top),
              Expanded(
                // IndexedStack keeps every destination alive, so moving between
                // them never costs a reload or a lost scroll position.
                child: IndexedStack(
                  index: Dest.values.indexOf(_dest),
                  children: [
                    homePane,
                    const SearchScreen(),
                    LibraryScreen(key: _libraryKey, initialTab: _libraryTab),
                    const SettingsScreen(),
                  ],
                ),
              ),
              if (!l.railNav)
                BottomBar(
                  dest: _dest,
                  onDest: _go,
                  downloadCount: activeDownloads,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
