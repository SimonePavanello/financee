// Genera le immagini dell'icona di Financee (monogramma F) da un unico
// disegno, con bordi antialias:
//
//   dart run tool/generate_app_icon.dart
//
// Scrive:
// - assets/branding/: icona arrotondata (Android legacy), quadrata senza
//   trasparenza (iOS), sfondo, primo piano e versione monocromatica per le
//   icone adattive di Android 8+ e 13+;
// - web/: favicon e icone dell'app installabile (normali e "maskable").
//
// Poi `dart run flutter_launcher_icons` crea le icone Android (e, sul Mac
// con `ios: true` in pubspec.yaml, quelle iOS).
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Colori dell'app: sfumatura dell'intestazione (AppColors.heroGradient) e
/// verde delle entrate (AppColors.income).
const _gradient = [0xFF4338CA, 0xFF6D28D9, 0xFF9333EA];
const _white = 0xFFFFFFFF;
const _mint = 0xFF12B886;

/// Il disegno è su una griglia di 120 × 120 unità.
const _grid = 120.0;
const _cornerRadius = 28.0;

/// Una forma del monogramma: rettangolo arrotondato o cerchio.
typedef _Shape = ({
  double left,
  double top,
  double right,
  double bottom,
  double radius,
  int color,
});

/// La F (asta e barra in alto bianche, barra centrale verde) e la moneta.
const List<_Shape> _mark = [
  (left: 36, top: 26, right: 51, bottom: 94, radius: 7.5, color: _white),
  (left: 36, top: 26, right: 86, bottom: 41, radius: 7.5, color: _white),
  (left: 36, top: 53, right: 72, bottom: 68, radius: 7.5, color: _mint),
  (left: 75, top: 74, right: 93, bottom: 92, radius: 9, color: _mint),
];

/// Riquadro che contiene il monogramma.
const _markLeft = 36.0, _markTop = 26.0, _markRight = 93.0, _markBottom = 94.0;

/// Distanza con segno dal bordo di un rettangolo arrotondato (negativa
/// dentro), in unità del disegno.
double _roundedRectDistance(double x, double y, _Shape s) {
  final cx = (s.left + s.right) / 2, cy = (s.top + s.bottom) / 2;
  final hx = (s.right - s.left) / 2 - s.radius;
  final hy = (s.bottom - s.top) / 2 - s.radius;
  final qx = (x - cx).abs() - hx, qy = (y - cy).abs() - hy;
  final outside = math.sqrt(
    math.pow(math.max(qx, 0), 2) + math.pow(math.max(qy, 0), 2),
  );
  return outside + math.min(math.max(qx, qy), 0) - s.radius;
}

/// Copertura (0..1) di un pixel a distanza [d] dal bordo, con [unitsPerPx]
/// unità del disegno per pixel: un pixel di sfumatura sul bordo.
double _coverage(double d, double unitsPerPx) =>
    (0.5 - d / unitsPerPx).clamp(0.0, 1.0);

int _lerpColor(int a, int b, double t) {
  int ch(int c, int shift) => (c >> shift) & 0xFF;
  int mix(int shift) =>
      (ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t).round();
  return 0xFF000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0);
}

/// Colore della sfumatura in diagonale (alto a sinistra → basso a destra).
int _gradientAt(double x, double y) {
  final t = ((x + y) / (2 * _grid)).clamp(0.0, 1.0);
  return t < 0.5
      ? _lerpColor(_gradient[0], _gradient[1], t * 2)
      : _lerpColor(_gradient[1], _gradient[2], (t - 0.5) * 2);
}

/// Sovrappone un colore con opacità [alpha] a un pixel (r, g, b, a in 0..1).
List<double> _over(List<double> dst, int color, double alpha) {
  if (alpha <= 0) return dst;
  final r = ((color >> 16) & 0xFF) / 255;
  final g = ((color >> 8) & 0xFF) / 255;
  final b = (color & 0xFF) / 255;
  final outA = alpha + dst[3] * (1 - alpha);
  if (outA == 0) return [0, 0, 0, 0];
  double c(double src, double d) =>
      (src * alpha + d * dst[3] * (1 - alpha)) / outA;
  return [c(r, dst[0]), c(g, dst[1]), c(b, dst[2]), outA];
}

enum _Background {
  /// Nessuno sfondo (trasparente).
  none,

  /// Sfumatura su tutto il quadrato.
  full,

  /// Sfumatura in un quadrato con gli angoli arrotondati.
  rounded,
}

/// Disegna l'icona di [size] pixel. Il monogramma è disegnato a [markScale]
/// della sua dimensione e centrato se [centerMark], altrimenti nella
/// posizione del disegno originale. Con [monochrome] tutto è bianco.
img.Image _render(
  int size, {
  _Background background = _Background.rounded,
  bool mark = true,
  double markScale = 1,
  bool centerMark = false,
  bool monochrome = false,
  bool opaque = false,
}) {
  final image = img.Image(width: size, height: size, numChannels: opaque ? 3 : 4);
  final unitsPerPx = _grid / size;
  // Spostamento del monogramma per centrarlo, in unità del disegno.
  final dx = centerMark ? _grid / 2 - (_markLeft + _markRight) / 2 : 0.0;
  final dy = centerMark ? _grid / 2 - (_markTop + _markBottom) / 2 : 0.0;
  const bgShape = (
    left: 0.0,
    top: 0.0,
    right: _grid,
    bottom: _grid,
    radius: _cornerRadius,
    color: 0,
  );

  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      final x = (px + 0.5) * unitsPerPx;
      final y = (py + 0.5) * unitsPerPx;
      var pixel = <double>[0, 0, 0, 0];
      switch (background) {
        case _Background.none:
          break;
        case _Background.full:
          pixel = _over(pixel, _gradientAt(x, y), 1);
        case _Background.rounded:
          pixel = _over(
            pixel,
            _gradientAt(x, y),
            _coverage(_roundedRectDistance(x, y, bgShape), unitsPerPx),
          );
      }
      if (mark) {
        // Coordinate nel sistema del monogramma (scalato attorno al centro).
        final mx = (x - _grid / 2) / markScale + _grid / 2 - dx;
        final my = (y - _grid / 2) / markScale + _grid / 2 - dy;
        for (final s in _mark) {
          final d = _roundedRectDistance(mx, my, s) * markScale;
          pixel = _over(
            pixel,
            monochrome ? _white : s.color,
            _coverage(d, unitsPerPx),
          );
        }
      }
      // Colori non premoltiplicati. Le immagini senza trasparenza hanno
      // sempre lo sfondo pieno, quindi ogni pixel è già opaco.
      image.setPixelRgba(
        px,
        py,
        (pixel[0] * 255).round(),
        (pixel[1] * 255).round(),
        (pixel[2] * 255).round(),
        opaque ? 255 : (pixel[3] * 255).round(),
      );
    }
  }
  return image;
}

void _save(String path, img.Image image) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
  stdout.writeln('  $path (${image.width}×${image.height})');
}

void main() {
  stdout.writeln('Icona di Financee:');
  // Android 8+: il primo piano è un quadrato di 108 dp di cui il sistema
  // mostra al sicuro solo il cerchio centrale di 66 dp: il monogramma va
  // centrato e rimpicciolito perché ci stia tutto.
  const adaptiveScale = 0.70;

  _save('assets/branding/app_icon.png', _render(1024));
  _save(
    'assets/branding/app_icon_ios.png',
    _render(1024, background: _Background.full, opaque: true),
  );
  _save(
    'assets/branding/app_icon_background.png',
    _render(1024, background: _Background.full, mark: false, opaque: true),
  );
  _save(
    'assets/branding/app_icon_foreground.png',
    _render(
      1024,
      background: _Background.none,
      markScale: adaptiveScale,
      centerMark: true,
    ),
  );
  _save(
    'assets/branding/app_icon_monochrome.png',
    _render(
      1024,
      background: _Background.none,
      markScale: adaptiveScale,
      centerMark: true,
      monochrome: true,
    ),
  );

  // Web: favicon e icone dell'app installabile. Le "maskable" possono essere
  // ritagliate a cerchio: sfondo pieno e monogramma un po' più piccolo.
  _save('web/favicon.png', _render(64));
  _save('web/icons/Icon-192.png', _render(192));
  _save('web/icons/Icon-512.png', _render(512));
  for (final size in [192, 512]) {
    _save(
      'web/icons/Icon-maskable-$size.png',
      _render(
        size,
        background: _Background.full,
        markScale: 0.82,
        centerMark: true,
      ),
    );
  }
}
