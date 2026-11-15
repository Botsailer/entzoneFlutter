import 'package:flutter/widgets.dart';

/// The depressedzone design system — "Metro Typographic Tiles".
///
/// The world lends four things and only these: type, palette, density, and one
/// signature move (the season pivot panorama). Navigation and controls stay the
/// platform's own; they are only dressed in this vocabulary.
///
/// Three absolute rules, carried in from the roll's declined challengers:
///   1. A quantised ladder is the only tonal vocabulary. Every fill in this app
///      is black, white, one of four named accents, or one of four greys.
///      No computed tints, no gradients, no opacity ramps standing in for value.
///   2. Magnitude is physical extent before it is text.
///   3. The next complete state is already loaded.
///
/// And the world's own absolutes: zero corner radius, zero shadow, zero bevel,
/// zero gradient. A surface is either a saturated fill or a 1px outline on black.
class DZ {
  const DZ._();

  // ───────────────────────── palette ─────────────────────────
  // The full ladder. Nothing outside this list may be painted.

  /// The ground. Pure black, never a dark grey — the tiles supply every value.
  static const black = Color(0xFF000000);

  /// The only ink.
  static const white = Color(0xFFFFFFFF);

  /// The one live-state colour: focus, selection, progress, the active anything.
  static const cyan = Color(0xFF00BDE3);

  /// On this device — downloads, offline, stored.
  static const magenta = Color(0xFFE6007E);

  /// Finished — watched to the end, download complete.
  static const lime = Color(0xFFA4E600);

  /// Destructive and failed. Metro's own red, used sparingly and never for chrome.
  static const red = Color(0xFFE51400);

  /// Warning / limited availability. The fourth accent, rationed hardest.
  static const amber = Color(0xFFFA6800);

  // Exactly four greys. Secondary and disabled text, hairlines, inert fills.
  /// Secondary text on black. 7.2:1 on #000 — clears AA for body.
  static const grey1 = Color(0xFFB4B4B4);

  /// Tertiary text and inactive pivot words. 4.6:1 on #000.
  static const grey2 = Color(0xFF8A8A8A);

  /// Disabled text and empty-state marks. Never used for text that must be read.
  static const grey3 = Color(0xFF545454);

  /// Inert fills and hairlines where white would shout.
  static const grey4 = Color(0xFF242424);

  /// The only scrim: a flat black field at a fixed opacity over artwork.
  /// Not a gradient — Metro has no gradients. Two fixed steps, nothing between.
  static const scrim = Color(0xCC000000);
  static const scrimLight = Color(0x80000000);

  /// The one press step. A pressed fill lightens by exactly this much and no
  /// other amount — declared here so no call site invents its own tint.
  static const pressWash = Color(0x33FFFFFF);

  /// Accent for a given semantic role, so state colour is never hand-picked
  /// at a call site.
  static const accents = <Color>[cyan, magenta, lime, amber, red];

  // ───────────────────────── type ─────────────────────────
  // One family, a fixed seven-step ramp. Display is always lowercase and light.
  // Sizes are the board's own: 96/96, 60/60, 34/34, 24/28, 16/24, 12/20, 10/16.

  static const family = 'Mulish';

  static const _w200 = <FontVariation>[FontVariation('wght', 200)];
  static const _w300 = <FontVariation>[FontVariation('wght', 300)];
  static const _w400 = <FontVariation>[FontVariation('wght', 400)];
  static const _w600 = <FontVariation>[FontVariation('wght', 600)];
  static const _w700 = <FontVariation>[FontVariation('wght', 700)];

  /// 96/96 — the section word, set enormous and cropped off the right edge.
  static const poster = TextStyle(
    fontFamily: family,
    fontSize: 96,
    height: 1.0,
    fontWeight: FontWeight.w200,
    fontVariations: _w200,
    letterSpacing: -3.4, // -0.035em
    color: white,
  );

  /// 60/60 — a screen's own title where poster scale would not fit.
  static const hero = TextStyle(
    fontFamily: family,
    fontSize: 60,
    height: 1.0,
    fontWeight: FontWeight.w200,
    fontVariations: _w200,
    letterSpacing: -1.9,
    color: white,
  );

  /// 34/34 — tile headline type and sheet titles.
  static const title = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 1.0,
    fontWeight: FontWeight.w300,
    fontVariations: _w300,
    letterSpacing: -0.9,
    color: white,
  );

  /// 24/28 — a tile's own name, section headings.
  static const subtitle = TextStyle(
    fontFamily: family,
    fontSize: 24,
    height: 28 / 24,
    fontWeight: FontWeight.w300,
    fontVariations: _w300,
    letterSpacing: -0.4,
    color: white,
  );

  /// 16/24 — body. Synopsis, descriptions, settings rows.
  static const body = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    fontVariations: _w400,
    color: white,
  );

  /// 12/20 — captions, metadata, counts.
  static const caption = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 20 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: _w400,
    color: grey1,
  );

  /// 10/16 — labels. Always lowercase, always tracked out.
  static const label = TextStyle(
    fontFamily: family,
    fontSize: 10,
    height: 16 / 10,
    fontWeight: FontWeight.w600,
    fontVariations: _w600,
    letterSpacing: 1.0,
    color: grey1,
  );

  /// Semibold body, for a tile's own name and any control that must be pressed.
  static const bodyStrong = TextStyle(
    fontFamily: family,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    fontVariations: _w600,
    color: white,
  );

  /// A giant numeral on a flat tile — a count, a remaining time, a season number.
  /// Magnitude read as extent: this is deliberately the loudest thing on a tile.
  static const numeral = TextStyle(
    fontFamily: family,
    fontSize: 46,
    height: 1.0,
    fontWeight: FontWeight.w200,
    fontVariations: _w200,
    letterSpacing: -2.0,
    color: white,
  );

  static const strongWeight = _w700;
  static const semiboldWeight = _w600;

  // ───────────────────────── density ─────────────────────────
  // A strict grid. Metro's gutter is tight and its outer margin generous;
  // the black between tiles is the only separation there is.

  /// The gutter between tiles. Never varied.
  static const gap = 6.0;

  /// Screen side margin on phone.
  static const margin = 16.0;

  /// Screen side margin on desktop / TV, where the field is wider.
  static const marginWide = 48.0;

  /// Vertical separation between sections. More space above a heading than below.
  static const sectionTop = 44.0;
  static const sectionBottom = 16.0;

  /// Control height. 48 clears the phone touch floor; TV scales it up.
  static const control = 48.0;

  /// The hairline. Metro outlines are 1px at any density — they are drawn marks.
  static const hairline = 1.0;

  /// There is no corner radius anywhere in this world.
  static const BorderRadius radius = BorderRadius.zero;

  // ───────────────────────── motion ─────────────────────────
  // One authored grammar: tiles tilt toward the press and release; panes slide
  // with type leading the artwork; entrances stagger from the leading edge.

  static const tiltPress = Duration(milliseconds: 120);
  static const tiltRelease = Duration(milliseconds: 260);
  static const paneSlide = Duration(milliseconds: 420);
  static const stateChange = Duration(milliseconds: 180);
  static const stagger = Duration(milliseconds: 45);

  /// Exponential ease-out, from an already-visible default.
  static const ease = Cubic(0.16, 1.0, 0.3, 1.0);
  static const easeIn = Cubic(0.4, 0.0, 1.0, 1.0);

  /// How far a tile tilts toward the press point, in radians at the corner.
  static const tiltMax = 0.045;
}

/// Semantic state colours, so no call site invents one.
enum DZState { idle, live, stored, done, warn, failed }

extension DZStateColor on DZState {
  Color get color => switch (this) {
    DZState.idle => DZ.grey2,
    DZState.live => DZ.cyan,
    DZState.stored => DZ.magenta,
    DZState.done => DZ.lime,
    DZState.warn => DZ.amber,
    DZState.failed => DZ.red,
  };

  /// Ink that reads on this state's own fill.
  Color get ink => switch (this) {
    DZState.live || DZState.done || DZState.warn => DZ.black,
    _ => DZ.white,
  };
}

/// Ink that reads on an arbitrary accent fill.
///
/// Measured, not guessed. Relative luminance of each fill against white and
/// black ink, as WCAG computes it:
///
///   cyan #00BDE3  L .419 — white 2.24:1 ✗   black 9.4:1 ✓
///   lime #A4E600  L .645 — white 1.49:1 ✗   black 13.9:1 ✓
///   amber #FA6800 L .302 — white 2.98:1 ✗   black 7.0:1 ✓
///   magenta #E6007E L .183 — white 4.50:1 ✓ black 4.7:1 ✓
///   red #E51400   L .172 — white 4.74:1 ✓   black 4.4:1
///
/// Cyan sits *above* amber on that ladder, so the original rule — lime and
/// amber take black, everything else white — put white ink on the app's
/// primary accent at 2.24:1, failing AA on every primary button, every active
/// nav item and every selected row. The three light fills take black.
Color inkOn(Color fill) =>
    (fill == DZ.cyan || fill == DZ.lime || fill == DZ.amber)
    ? DZ.black
    : DZ.white;
