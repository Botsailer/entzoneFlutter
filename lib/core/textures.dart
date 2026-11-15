import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The world's three textures, drawn as 1px marks in an accent on black:
/// dot matrix, pinstripe, slash. They are the only ornament this system has,
/// and they exist to fill a tile's empty quarter rather than to decorate it —
/// so each one is clipped to its tile and never crosses a gutter.
enum Texture { dots, pinstripe, slash }

class TexturePatch extends StatelessWidget {
  const TexturePatch({
    super.key,
    this.texture = Texture.dots,
    this.color = DZ.white,
    this.opacity = 0.55,
    this.cell = 7.0,
  });

  final Texture texture;
  final Color color;
  final double opacity;

  /// Spacing of the repeat. Larger on a TV, where the viewer is ten feet away.
  final double cell;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TexturePainter(texture, color, opacity, cell),
    isComplex: false,
  );
}

class _TexturePainter extends CustomPainter {
  _TexturePainter(this.texture, this.color, this.opacity, this.cell);

  final Texture texture;
  final Color color;
  final double opacity;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.fill
      ..isAntiAlias = false; // Metro's marks are hard-edged, never soft

    switch (texture) {
      case Texture.dots:
        final r = cell <= 6 ? 1.0 : 1.4;
        for (double y = cell / 2; y < size.height; y += cell) {
          for (double x = cell / 2; x < size.width; x += cell) {
            canvas.drawRect(Rect.fromLTWH(x, y, r * 2, r * 2), paint);
          }
        }
      case Texture.pinstripe:
        paint.style = PaintingStyle.stroke;
        for (double x = 0; x < size.width; x += cell) {
          canvas.drawLine(
            Offset(x + .5, 0),
            Offset(x + .5, size.height),
            paint,
          );
        }
      case Texture.slash:
        paint.style = PaintingStyle.stroke;
        final step = cell * 1.6;
        for (double x = -size.height; x < size.width; x += step) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_TexturePainter old) =>
      old.texture != texture ||
      old.color != color ||
      old.opacity != opacity ||
      old.cell != cell;
}

/// The dot-matrix patch Metro parks in a tile's top-right quarter. Sized in
/// cells so it reads at the same scale whatever the tile's span.
class CornerDots extends StatelessWidget {
  const CornerDots({
    super.key,
    this.color = DZ.white,
    this.opacity = 0.5,
    this.cols = 6,
    this.rows = 5,
    this.cell = 7,
  });

  final Color color;
  final double opacity;
  final int cols;
  final int rows;
  final double cell;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      width: cols * cell,
      height: rows * cell,
      child: TexturePatch(
        texture: Texture.dots,
        color: color,
        opacity: opacity,
        cell: cell,
      ),
    ),
  );
}

/// A flat scrim over artwork so a tile's own name stays legible. Not a gradient:
/// this world has none. Two fixed steps, and nothing between them.
class FlatScrim extends StatelessWidget {
  const FlatScrim({super.key, this.heavy = false, this.height});

  final bool heavy;
  final double? height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(height: height, color: heavy ? DZ.scrim : DZ.scrimLight),
  );
}
