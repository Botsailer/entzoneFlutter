import 'package:material_ui/material_ui.dart';

import '../../core/tokens.dart';

/// The supplied TV banner bridges native launch and the catalog's first frame.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.error, this.onRetry});

  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DZ.black,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.86).clamp(0.0, 560.0);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/img/depressedzone-tv-banner.png',
                width: width,
                fit: BoxFit.contain,
                semanticLabel: 'depressedzone',
              ),
              const SizedBox(height: 32),
              if (error == null)
                const Text(
                  'loading',
                  style: TextStyle(color: DZ.grey1, fontSize: 12),
                )
              else ...[
                Text(
                  error!,
                  style: const TextStyle(color: DZ.white, fontSize: 14),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: DZ.cyan,
                    foregroundColor: DZ.black,
                    minimumSize: const Size(120, 48),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text('retry'),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
