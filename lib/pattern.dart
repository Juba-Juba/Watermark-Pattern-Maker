import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum PatternKind { grid, staggered, diagonal }

enum LogoTone { original, gray, custom }

class PatternSettings {
  int width = 1080, height = 1920, limit = 1000;
  double scale = 160,
      spacingX = 100,
      spacingY = 100,
      rotation = 30,
      opacity = .35,
      offsetX = 0,
      offsetY = 0,
      alternateRotation = 0,
      alternateScale = 1;
  PatternKind kind = PatternKind.staggered;
  LogoTone tone = LogoTone.original;
  Color color = const Color(0xff91979e);
  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'limit': limit,
    'scale': scale,
    'spacingX': spacingX,
    'spacingY': spacingY,
    'rotation': rotation,
    'opacity': opacity,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'kind': kind.index,
    'toneName': tone.name,
    'alternateRotation': alternateRotation,
    'alternateScale': alternateScale,
    'color': color.toARGB32(),
  };
  static PatternSettings fromJson(Map<String, dynamic> j) {
    final s = PatternSettings();
    s.width = (j['width'] as num).toInt().clamp(64, 4096);
    s.height = (j['height'] as num).toInt().clamp(64, 4096);
    s.limit = (j['limit'] as num).toInt().clamp(1, 2000);
    s.scale = (j['scale'] as num).toDouble().clamp(24, 800);
    s.spacingX = (j['spacingX'] as num).toDouble().clamp(0, 100000);
    s.spacingY = (j['spacingY'] as num).toDouble().clamp(0, 100000);
    s.rotation = (j['rotation'] as num).toDouble().clamp(-180, 180);
    s.opacity = (j['opacity'] as num).toDouble().clamp(0, 1);
    s.offsetX = (j['offsetX'] as num).toDouble().clamp(-600, 600);
    s.offsetY = (j['offsetY'] as num).toDouble().clamp(-600, 600);
    s.kind = PatternKind.values[(j['kind'] as int).clamp(0, 2)];
    // Migrate old pink presets to gray without shifting the original enum IDs.
    s.tone = j['toneName'] != null
        ? LogoTone.values.firstWhere(
            (v) => v.name == j['toneName'],
            orElse: () => LogoTone.gray,
          )
        : switch (j['tone']) {
            0 => LogoTone.original,
            3 => LogoTone.custom,
            _ => LogoTone.gray,
          };
    s.alternateRotation = (j['alternateRotation'] as num? ?? 0)
        .toDouble()
        .clamp(-180, 180);
    s.alternateScale = (j['alternateScale'] as num? ?? 1).toDouble().clamp(
      .25,
      1.5,
    );
    s.color = Color(j['color'] as int);
    return s;
  }
}

/// Axis-aligned envelope of both normal and alternate rows after rotation.
Size patternFootprint(PatternSettings s, double aspect) {
  Size envelope(double angle, double scale) {
    final radians = angle * math.pi / 180;
    final w = s.scale * scale, h = w / aspect;
    return Size(
      w * math.cos(radians).abs() + h * math.sin(radians).abs(),
      w * math.sin(radians).abs() + h * math.cos(radians).abs(),
    );
  }

  final normal = envelope(s.rotation, 1);
  final alternate = envelope(
    s.rotation + s.alternateRotation,
    s.alternateScale,
  );
  return Size(
    math.max(normal.width, alternate.width),
    math.max(normal.height, alternate.height),
  );
}

class PatternPainter extends CustomPainter {
  final ui.Image logo;
  final PatternSettings settings;
  PatternPainter(this.logo, this.settings);
  int draw(Canvas canvas, Size size) {
    final s = settings;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / s.width, size.height / s.height);
    final w = s.scale, h = w * logo.height / logo.width;
    final footprint = patternFootprint(s, logo.width / logo.height);
    final dx = footprint.width + math.max(0, s.spacingX),
        dy = footprint.height + math.max(0, s.spacingY);
    final radius = math.sqrt(w * w + h * h) / 2 * math.max(1, s.alternateScale);
    final source = Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );
    final target = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true
      ..color = Color.fromRGBO(255, 255, 255, s.opacity);
    if (s.tone == LogoTone.custom) {
      paint.colorFilter = ColorFilter.mode(s.color, BlendMode.srcIn);
    } else if (s.tone == LogoTone.gray) {
      // Preserve light/dark detail instead of flattening the image into a silhouette.
      paint.colorFilter = const ColorFilter.matrix([
        .2126,
        .7152,
        .0722,
        0,
        0,
        .2126,
        .7152,
        .0722,
        0,
        0,
        .2126,
        .7152,
        .0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }
    var count = 0;
    // Start outside the frame so rotated edge elements remain visible.
    for (var row = -2; row < (s.height + radius) / dy + 2; row++) {
      for (var col = -2; col < (s.width + radius) / dx + 2; col++) {
        final shift = switch (s.kind) {
          PatternKind.grid => 0.0,
          PatternKind.staggered => row.isOdd ? dx / 2 : 0.0,
          PatternKind.diagonal => (row * dx * .28) % dx,
        };
        final x = col * dx + shift + s.offsetX % dx;
        final y = row * dy + s.offsetY % dy;
        if (x + radius < 0 ||
            y + radius < 0 ||
            x - radius > s.width ||
            y - radius > s.height) {
          continue;
        }
        if (count >= s.limit) {
          break;
        }
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(
          (s.rotation + (row.isOdd ? s.alternateRotation : 0)) * math.pi / 180,
        );
        if (row.isOdd) canvas.scale(s.alternateScale);
        canvas.drawImageRect(logo, source, target, paint);
        canvas.restore();
        count++;
      }
      if (count >= s.limit) {
        break;
      }
    }
    canvas.restore();
    return count;
  }

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);
  @override
  bool shouldRepaint(covariant PatternPainter oldDelegate) => true;
}

Future<Uint8List> exportPattern(ui.Image logo, PatternSettings s) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PatternPainter(
    logo,
    s,
  ).draw(canvas, Size(s.width.toDouble(), s.height.toDouble()));
  final picture = recorder.endRecording();
  final output = await picture.toImage(s.width, s.height);
  try {
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('تعذر ترميز PNG');
    }
    return bytes.buffer.asUint8List();
  } finally {
    output.dispose();
    picture.dispose();
  }
}
