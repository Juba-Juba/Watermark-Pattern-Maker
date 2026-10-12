import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watermark_pattern_maker/frame.dart';
import 'package:watermark_pattern_maker/main.dart';
import 'package:watermark_pattern_maker/pattern.dart';
import 'pattern_test.dart' show logoImage, FakePicker;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in FrameStyle.values) {
    test(
      'Frame ${style.name}: real alpha gap and original logo colors',
      () async {
        final logo = await logoImage();
        final reverse = style == FrameStyle.oppositeCornersReverse;
        final cornerStyle = reverse || style == FrameStyle.oppositeCorners;
        final settings = FrameSettings()
          ..width = 320
          ..height = 400
          ..inset = 40
          ..stroke = 4
          ..gap = 12
          ..style = style
          ..position = cornerStyle
              ? (reverse ? FramePosition.topRight : FramePosition.topLeft)
              : FramePosition.bottom;
        final layout = FrameLayout.calculate(
          settings,
          logo.width / logo.height,
        );
        final before = img.decodePng(await exportFrame(settings))!;
        final after = img.decodePng(await exportFrame(settings, logo: logo))!;
        final x =
                (reverse ? layout.logoRect.right + 6 : layout.logoRect.left - 6)
                    .round(),
            y = (cornerStyle ? layout.border.top : layout.border.bottom)
                .round();
        expect(before.getPixel(x, y).a, greaterThan(0));
        expect(
          after.getPixel(x, y).a,
          0,
          reason: 'Frame is cut beside logo, without opaque fill',
        );
        expect(
          after.getPixel(160, 200).a,
          0,
          reason: 'The center remains transparent',
        );
        final p = after.getPixel(
          layout.logoRect.center.dx.round(),
          layout.logoRect.center.dy.round(),
        );
        expect([p.r, p.g, p.b, p.a], [20, 100, 210, 255]);
        expect(after.numChannels, 4);
        logo.dispose();
      },
    );
  }
  test(
    'Opposite corner frames leave the other two corners and middle empty',
    () async {
      for (final style in [
        FrameStyle.oppositeCorners,
        FrameStyle.oppositeCornersReverse,
      ]) {
        final s = FrameSettings()
          ..width = 320
          ..height = 400
          ..inset = 40
          ..style = style;
        final output = img.decodePng(await exportFrame(s))!;
        final reverse = style == FrameStyle.oppositeCornersReverse;
        expect(output.getPixel(reverse ? 280 : 40, 40).a, greaterThan(0));
        expect(output.getPixel(reverse ? 40 : 280, 360).a, greaterThan(0));
        expect(output.getPixel(reverse ? 40 : 280, 40).a, 0);
        expect(output.getPixel(reverse ? 280 : 40, 360).a, 0);
        expect(output.getPixel(160, 40).a, 0);
        expect(output.getPixel(160, 200).a, 0);
      }
    },
  );
  test(
    'Six brush frames are distinct, deterministic RGBA with empty centers',
    () async {
      final seen = <String>{};
      for (final style in FrameStyle.values.where(
        (v) => v.index >= 6 && v.index <= 11,
      )) {
        final s = FrameSettings()
          ..width = 320
          ..height = 480
          ..inset = 32
          ..stroke = 6
          ..style = style
          ..color = Colors.white;
        final bytes = await exportFrame(s);
        expect(await exportFrame(s), orderedEquals(bytes));
        final output = img.decodePng(bytes)!;
        expect(output.getPixel(160, 240).a, 0);
        expect(output.getPixel(0, 0).a, 0);
        expect(output.getPixel(160, 32).a, greaterThan(0));
        expect(output.numChannels, 4);
        seen.add(bytes.toString());
        Directory('output/qa/brush-frames').createSync(recursive: true);
        File(
          'output/qa/brush-frames/${style.name}.png',
        ).writeAsBytesSync(bytes);
      }
      expect(seen.length, 6);
    },
  );
  test('All logo positions fit extreme aspect ratios without stretching', () {
    for (final position in FramePosition.values) {
      for (final aspect in [.1, 1.0, 10.0]) {
        final s = FrameSettings()
          ..width = 360
          ..height = 640
          ..position = position
          ..logoWidth = .6;
        final rect = FrameLayout.calculate(s, aspect).logoRect;
        expect(rect.left, greaterThanOrEqualTo(-.001));
        expect(rect.top, greaterThanOrEqualTo(-.001));
        expect(rect.right, lessThanOrEqualTo(s.width + .001));
        expect(rect.bottom, lessThanOrEqualTo(s.height + .001));
        expect(rect.width / rect.height, closeTo(aspect, .001));
      }
    }
  });
  test('Frame logo can be hidden without leaving an unwanted cutout', () async {
    final logo = await logoImage();
    final s = FrameSettings()
      ..width = 320
      ..height = 400
      ..showLogo = false;
    expect(
      await exportFrame(s, logo: logo),
      orderedEquals(await exportFrame(s)),
    );
    logo.dispose();
  });
  test('4K frame export keeps center transparent', () async {
    final s = FrameSettings()
      ..width = 2160
      ..height = 3840
      ..style = FrameStyle.artDeco;
    final bytes = await exportFrame(s);
    final decoded = img.decodePng(bytes)!;
    expect(
      [decoded.width, decoded.height, decoded.numChannels],
      [2160, 3840, 4],
    );
    expect(decoded.getPixel(1080, 1920).a, 0);
    Directory('output/qa').createSync(recursive: true);
    File('output/qa/frame-4k-alpha.png').writeAsBytesSync(bytes);
  });
  for (final kind in PatternKind.values) {
    test('Rotated wide logos never overlap in ${kind.name}', () async {
      final source = img.Image(width: 120, height: 20, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(20, 100, 210, 255));
      final codec = await ui.instantiateImageCodec(img.encodePng(source));
      final logo = (await codec.getNextFrame()).image;
      codec.dispose();
      final s = PatternSettings()
        ..width = 360
        ..height = 360
        ..scale = 120
        ..rotation = 45
        ..alternateRotation = 90
        ..alternateScale = 1.5
        ..spacingX = 0
        ..spacingY = 0
        ..opacity = .5
        ..kind = kind;
      final output = img.decodePng(await exportPattern(logo, s))!;
      expect(output.any((p) => p.a > 0), true);
      expect(
        output.map((p) => p.a).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(128),
        reason:
            'Overlapping half-opacity marks would accumulate alpha above 128',
      );
      logo.dispose();
    });
  }
  test(
    'Original export retains internal color detail at native resolution',
    () async {
      final source = img.Image(width: 40, height: 20, numChannels: 4);
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 19,
        y2: 19,
        color: img.ColorRgba8(210, 40, 20, 255),
      );
      img.fillRect(
        source,
        x1: 20,
        y1: 0,
        x2: 39,
        y2: 19,
        color: img.ColorRgba8(20, 100, 210, 255),
      );
      final codec = await ui.instantiateImageCodec(img.encodePng(source));
      final logo = (await codec.getNextFrame()).image;
      codec.dispose();
      final s = PatternSettings()
        ..width = 200
        ..height = 100
        ..scale = 40
        ..rotation = 0
        ..opacity = 1
        ..offsetX = 40
        ..offsetY = 30
        ..spacingX = 200
        ..spacingY = 200;
      expect(s.tone, LogoTone.original);
      final output = img.decodePng(await exportPattern(logo, s))!;
      final red = output.getPixel(30, 30), blue = output.getPixel(50, 30);
      expect([red.r, red.g, red.b, red.a], [210, 40, 20, 255]);
      expect([blue.r, blue.g, blue.b, blue.a], [20, 100, 210, 255]);
      s.tone = LogoTone.gray;
      final gray = img.decodePng(await exportPattern(logo, s))!;
      final dark = gray.getPixel(30, 30), light = gray.getPixel(50, 30);
      expect(dark.r, dark.g);
      expect(light.r, light.g);
      expect(
        dark.r,
        isNot(light.r),
        reason: 'Grayscale must preserve internal luminance detail',
      );
      logo.dispose();
    },
  );
  for (final size in [
    const Size(360, 844),
    const Size(1200, 900),
    const Size(780, 390),
  ]) {
    testWidgets('Two main tabs and responsive frame controls at $size', (
      tester,
    ) async {
      ImagePickerPlatform.instance = FakePicker();
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const WatermarkApp());
      await tester.pumpAndSettle();
      expect(find.text('العلامة المائية'), findsOneWidget);
      await tester.tap(find.text('الفريم'));
      await tester.pumpAndSettle();
      if (size.height < 500) {
        await tester.scrollUntilVisible(
          find.text('مقاس الفريم'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('مقاس الفريم'), findsOneWidget);
      expect(find.text('اختر تصميم الفريم'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('تبديل المظهر'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
