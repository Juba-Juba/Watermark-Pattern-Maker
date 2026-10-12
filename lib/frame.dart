import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum FrameStyle {
  minimal,
  doubleLine,
  gallery,
  corners,
  ornamental,
  artDeco,
  brushRounded,
  brushDry,
  brushTorn,
  brushStrokes,
  brushInk,
  brushGrain,
  oppositeCorners,
  oppositeCornersReverse,
  logoRepeat,
}

enum FramePosition {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

const frameStyleNames = [
  'ناعم',
  'مزدوج',
  'جاليري',
  'أركان',
  'كلاسيك',
  'آرت ديكو',
  'فرشاة ناعمة',
  'فرشاة جافة',
  'حواف ممزقة',
  'ضربات فرشاة',
  'حبر متناثر',
  'حواف محببة',
  'زاويتان ↘',
  'زاويتان ↙',
  'فريم من اللوجو',
];
const framePositionNames = [
  'أعلى يسار',
  'أعلى الوسط',
  'أعلى يمين',
  'يسار الوسط',
  'يمين الوسط',
  'أسفل يسار',
  'أسفل الوسط',
  'أسفل يمين',
];

class FrameSettings {
  int width = 1080, height = 1920;
  FrameStyle style = FrameStyle.doubleLine;
  FramePosition position = FramePosition.bottom;
  Color color = const Color(0xffc8ccd2);
  double stroke = 5,
      inset = 64,
      radius = 32,
      gap = 18,
      logoWidth = .28,
      opacity = 1,
      logoOpacity = 1;
  double cornerLength = .32;
  double repeatScale = .12, repeatSpacing = .03;
  bool showLogo = true;
}

class FrameLayout {
  final Rect border, logoRect, gapRect;
  final double stroke, radius;
  FrameLayout(
    this.border,
    this.logoRect,
    this.gapRect,
    this.stroke,
    this.radius,
  );
  factory FrameLayout.calculate(FrameSettings s, double? aspect) {
    final shortest = math.min(s.width, s.height).toDouble();
    final inset = s.inset.clamp(8.0, shortest * .24);
    final stroke = s.stroke.clamp(1.0, inset / 2);
    final border = Rect.fromLTRB(
      inset,
      inset,
      s.width - inset,
      s.height - inset,
    );
    final w = math.min(s.width * s.logoWidth, border.width * .72);
    final h = math.min(w / (aspect ?? 2), border.height * .24);
    final actualW = math.min(w, h * (aspect ?? 2));
    final cornerOffset = math.min(
      border.width * .25,
      math.max(actualW / 2 + s.gap, s.radius),
    );
    final center = switch (s.position) {
      FramePosition.topLeft => Offset(border.left + cornerOffset, border.top),
      FramePosition.top => border.topCenter,
      FramePosition.topRight => Offset(border.right - cornerOffset, border.top),
      FramePosition.left => border.centerLeft,
      FramePosition.right => border.centerRight,
      FramePosition.bottomLeft => Offset(
        border.left + cornerOffset,
        border.bottom,
      ),
      FramePosition.bottom => border.bottomCenter,
      FramePosition.bottomRight => Offset(
        border.right - cornerOffset,
        border.bottom,
      ),
    };
    // Fit into the canvas without stretching or cropping any logo pixels.
    final maxW = 2 * math.min(center.dx, s.width - center.dx);
    final maxH = 2 * math.min(center.dy, s.height - center.dy);
    final fit = math.min(1.0, math.min(maxW / actualW, maxH / h));
    final logo = Rect.fromCenter(
      center: center,
      width: actualW * fit,
      height: h * fit,
    );
    return FrameLayout(
      border,
      logo,
      logo.inflate(s.gap),
      stroke,
      s.radius.clamp(0.0, border.shortestSide / 3),
    );
  }
}

class FramePainter extends CustomPainter {
  final FrameSettings settings;
  final ui.Image? logo;
  FramePainter(this.settings, {this.logo});
  @override
  void paint(Canvas canvas, Size size) {
    final s = settings;
    final layout = FrameLayout.calculate(
      s,
      logo == null ? null : logo!.width / logo!.height,
    );
    final r = layout.border;
    final paint = Paint()
      ..color = s.color.withValues(alpha: s.opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = layout.stroke
      ..isAntiAlias = true;
    canvas.save();
    canvas.scale(size.width / s.width, size.height / s.height);
    canvas.clipRect(
      Rect.fromLTWH(0, 0, s.width.toDouble(), s.height.toDouble()),
    );
    if (s.style == FrameStyle.logoRepeat) {
      _paintLogoRepeat(canvas);
      canvas.restore();
      return;
    }
    canvas.save();
    if (logo != null && s.showLogo) {
      final allowed = Path.combine(
        PathOperation.difference,
        Path()..addRect(
          Rect.fromLTWH(0, 0, s.width.toDouble(), s.height.toDouble()),
        ),
        Path()..addRRect(
          RRect.fromRectAndRadius(layout.gapRect, const Radius.circular(8)),
        ),
      );
      canvas.clipPath(allowed);
    }
    void outline(Rect rect, double radius) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
    final separation = math.max(
      layout.stroke * 3,
      math.min(r.width, r.height) * .012,
    );
    switch (s.style) {
      case FrameStyle.minimal:
        outline(r, layout.radius);
      case FrameStyle.doubleLine:
        outline(r, layout.radius);
        paint.strokeWidth = math.max(1, layout.stroke * .45);
        outline(r.deflate(separation), math.max(0, layout.radius - separation));
      case FrameStyle.gallery:
        paint.strokeWidth = layout.stroke * 2;
        outline(r, 0);
        paint.strokeWidth = math.max(1, layout.stroke * .35);
        outline(r.deflate(separation * 1.6), 0);
      case FrameStyle.corners:
        outline(r, layout.radius);
        paint.strokeWidth = layout.stroke * 2;
        final length = r.shortestSide * .14;
        for (final corner in [
          r.topLeft,
          r.topRight,
          r.bottomLeft,
          r.bottomRight,
        ]) {
          final sx = corner.dx == r.left ? 1.0 : -1.0,
              sy = corner.dy == r.top ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx + sx * length, corner.dy + sy * separation)
              ..lineTo(corner.dx + sx * separation, corner.dy + sy * separation)
              ..lineTo(corner.dx + sx * separation, corner.dy + sy * length),
            paint,
          );
        }
      case FrameStyle.ornamental:
        outline(r, layout.radius);
        paint.strokeWidth = math.max(1, layout.stroke * .45);
        outline(r.deflate(separation), math.max(0, layout.radius - separation));
        for (final corner in [
          r.topLeft,
          r.topRight,
          r.bottomLeft,
          r.bottomRight,
        ]) {
          final sx = corner.dx == r.left ? 1.0 : -1.0,
              sy = corner.dy == r.top ? 1.0 : -1.0;
          final length = r.shortestSide * .09;
          final c = corner + Offset(sx * length, sy * length);
          canvas.drawOval(
            Rect.fromCenter(center: c, width: length, height: length),
            paint,
          );
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - sx * length * .8, c.dy)
              ..quadraticBezierTo(
                c.dx,
                c.dy - sy * length * .8,
                c.dx + sx * length * .8,
                c.dy,
              )
              ..quadraticBezierTo(
                c.dx,
                c.dy + sy * length * .8,
                c.dx,
                c.dy + sy * length * .8,
              ),
            paint,
          );
        }
      case FrameStyle.artDeco:
        outline(r, 0);
        paint.strokeWidth = math.max(1, layout.stroke * .5);
        outline(r.deflate(separation * 2), 0);
        for (final corner in [
          r.topLeft,
          r.topRight,
          r.bottomLeft,
          r.bottomRight,
        ]) {
          final sx = corner.dx == r.left ? 1.0 : -1.0,
              sy = corner.dy == r.top ? 1.0 : -1.0;
          final length = r.shortestSide * .12;
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx + sx * length, corner.dy)
              ..lineTo(corner.dx + sx * length, corner.dy + sy * separation)
              ..lineTo(corner.dx + sx * separation, corner.dy + sy * separation)
              ..lineTo(corner.dx + sx * separation, corner.dy + sy * length)
              ..lineTo(corner.dx, corner.dy + sy * length),
            paint,
          );
        }
      case FrameStyle.brushRounded:
      case FrameStyle.brushDry:
      case FrameStyle.brushTorn:
      case FrameStyle.brushStrokes:
      case FrameStyle.brushInk:
      case FrameStyle.brushGrain:
        _paintBrush(canvas, layout, paint);
      case FrameStyle.oppositeCorners:
      case FrameStyle.oppositeCornersReverse:
        final length = r.shortestSide * s.cornerLength;
        paint.strokeWidth = layout.stroke * 2;
        paint.strokeCap = StrokeCap.square;
        final corners = s.style == FrameStyle.oppositeCorners
            ? [r.topLeft, r.bottomRight]
            : [r.topRight, r.bottomLeft];
        for (final corner in corners) {
          final sx = corner.dx == r.left ? 1.0 : -1.0;
          final sy = corner.dy == r.top ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx + sx * length, corner.dy)
              ..lineTo(corner.dx, corner.dy)
              ..lineTo(corner.dx, corner.dy + sy * length),
            paint,
          );
        }
      case FrameStyle.logoRepeat:
        break; // Painted separately without a border or a single-logo cutout.
    }
    canvas.restore();
    if (logo != null && s.showLogo) {
      canvas.drawImageRect(
        logo!,
        Rect.fromLTWH(0, 0, logo!.width.toDouble(), logo!.height.toDouble()),
        layout.logoRect,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true
          ..color = Color.fromRGBO(255, 255, 255, s.logoOpacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) => true;

  void _paintLogoRepeat(Canvas canvas) {
    final image = logo;
    if (image == null) return;
    final s = settings;
    final shortest = math.min(s.width, s.height).toDouble();
    final inset = s.inset.clamp(8.0, shortest * .24);
    final aspect = image.width / image.height;
    var width = shortest * s.repeatScale.clamp(.04, .25);
    var height = width / aspect;
    if (height > shortest * .18) {
      height = shortest * .18;
      width = height * aspect;
    }
    width = math.min(width, (shortest - 2 * inset) / (1 + 2 / aspect) * .95);
    height = width / aspect;
    final gap = shortest * s.repeatSpacing.clamp(0.0, .15);
    // Reserve corner squares so the perpendicular runs never overlap.
    final clearance = height;
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final destination = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, s.opacity);
    void side(double length, Offset origin, Offset direction, double rotation) {
      final available = length - 2 * (inset + clearance);
      if (available < width) return;
      final count = ((available + gap) / (width + gap)).floor().clamp(1, 200);
      final step = count == 1 ? 0.0 : (available - width) / (count - 1);
      final start = count == 1 ? length / 2 : inset + clearance + width / 2;
      for (var i = 0; i < count; i++) {
        final center = origin + direction * (start + i * step);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(rotation);
        canvas.drawImageRect(image, source, destination, paint);
        canvas.restore();
      }
    }

    final depth = inset + height / 2;
    side(s.width.toDouble(), Offset(0, depth), const Offset(1, 0), 0);
    side(
      s.width.toDouble(),
      Offset(0, s.height - depth),
      const Offset(1, 0),
      math.pi,
    );
    side(
      s.height.toDouble(),
      Offset(depth, 0),
      const Offset(0, 1),
      -math.pi / 2,
    );
    side(
      s.height.toDouble(),
      Offset(s.width - depth, 0),
      const Offset(0, 1),
      math.pi / 2,
    );
  }

  void _paintBrush(Canvas canvas, FrameLayout layout, Paint paint) {
    final s = settings, r = layout.border;
    final variant = s.style.index - FrameStyle.brushRounded.index;
    final random = math.Random(407 + variant * 97);
    final thickness = math.min(
      layout.stroke * 4 + r.shortestSide * .015,
      math.min(s.inset * 1.5, r.shortestSide * .16),
    );
    final outer = r.inflate(thickness * .45);
    final inner = r.deflate(thickness * .55);
    final roughness = [.22, .65, .9, .75, .8, .4][variant] * thickness;
    final cornerRadius = variant == 0 || variant == 3
        ? math.max(layout.radius, thickness * 1.3)
        : math.min(layout.radius, thickness * .5);
    final guide = Path()
      ..addRRect(RRect.fromRectAndRadius(inner, Radius.circular(cornerRadius)));
    final metric = guide.computeMetrics().first;
    final samples = (metric.length / (r.shortestSide * .004)).round().clamp(
      200,
      1800,
    );
    final cutout = Path();
    for (var i = 0; i < samples; i++) {
      final tangent = metric.getTangentForOffset(metric.length * i / samples)!;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final jitter =
          (math.sin(i * .13 + variant) * .24 +
              math.sin(i * .41 + variant * 2) * .12 +
              (random.nextDouble() - .5) * .32) *
          roughness;
      final point = tangent.position + normal * jitter;
      if (i == 0) {
        cutout.moveTo(point.dx, point.dy);
      } else {
        cutout.lineTo(point.dx, point.dy);
      }
    }
    cutout.close();
    // Explicit even-odd holes avoid CanvasKit path-boolean winding differences.
    final band = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(
        RRect.fromRectAndRadius(
          outer,
          Radius.circular(variant == 0 ? layout.radius * .3 : 0),
        ),
      )
      ..addPath(cutout, Offset.zero);
    final flecks = Path();
    for (var i = 0; i < samples; i += 3) {
      final tangent = metric.getTangentForOffset(metric.length * i / samples)!;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final point =
          tangent.position - normal * (random.nextDouble() * roughness * .5);
      final radius = thickness * (.012 + random.nextDouble() * .045);
      flecks.addOval(Rect.fromCircle(center: point, radius: radius));
    }
    band.addPath(flecks, Offset.zero);
    paint.style = PaintingStyle.fill;
    canvas.drawPath(band, paint);
    // Short bristles and grains extend inward from the rough edge. All geometry
    // is deterministic, so resizing a preview never regenerates the texture.
    paint.strokeWidth = math.max(.7, thickness * .025);
    for (var i = 0; i < samples; i++) {
      if (random.nextDouble() > .28) continue;
      final tangent = metric.getTangentForOffset(metric.length * i / samples)!;
      final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
      final point =
          tangent.position + normal * (random.nextDouble() * roughness * .75);
      if (variant == 3 || variant == 1) {
        canvas.drawLine(
          point - normal * (thickness * .12),
          point + normal * (random.nextDouble() * roughness * .22),
          paint,
        );
      } else {
        canvas.drawCircle(
          point,
          thickness *
              (.008 + random.nextDouble() * (variant == 4 ? .065 : .025)),
          paint,
        );
      }
    }
  }
}

Future<Uint8List> exportFrame(FrameSettings settings, {ui.Image? logo}) async {
  final recorder = ui.PictureRecorder();
  FramePainter(settings, logo: logo).paint(
    Canvas(recorder),
    Size(settings.width.toDouble(), settings.height.toDouble()),
  );
  final picture = recorder.endRecording();
  final output = await picture.toImage(settings.width, settings.height);
  try {
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('تعذر تصدير الفريم');
    return data.buffer.asUint8List();
  } finally {
    output.dispose();
    picture.dispose();
  }
}
