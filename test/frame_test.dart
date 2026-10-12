import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watermark_pattern_maker/frame.dart';
import 'package:watermark_pattern_maker/frame_controls.dart';
import 'package:watermark_pattern_maker/main.dart';
import 'package:watermark_pattern_maker/pattern.dart';
import 'pattern_test.dart' show logoImage, FakePicker;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Default frame touches canvas edges and moving inset creates a real margin',
    () async {
      final s = FrameSettings()
        ..width = 320
        ..height = 400
        ..style = FrameStyle.minimal;
      expect(s.inset, 0);
      final edge = img.decodePng(await exportFrame(s))!;
      expect(edge.getPixel(160, 0).a, greaterThan(0));
      expect(edge.getPixel(0, 200).a, greaterThan(0));
      expect(edge.getPixel(160, 399).a, greaterThan(0));
      s.inset = 20;
      final moved = img.decodePng(await exportFrame(s))!;
      expect(moved.getPixel(160, 0).a, 0);
      expect(moved.getPixel(160, 22).a, greaterThan(0));
    },
  );
  test(
    'Logo gap fades smoothly into the frame without changing RGB or logo alpha',
    () async {
      final logo = await logoImage();
      final s = FrameSettings()
        ..width = 320
        ..height = 400
        ..style = FrameStyle.minimal
        ..inset = 24
        ..stroke = 6
        ..gap = 12
        ..gapFeather = 40
        ..color = Colors.white;
      final layout = FrameLayout.calculate(s, logo.width / logo.height);
      final output = img.decodePng(await exportFrame(s, logo: logo))!;
      final y = layout.border.bottom.floor();
      final x = layout.gapRect.right.ceil();
      final a = [
        for (final dx in [4, 16, 32, 48]) output.getPixel(x + dx, y).a,
      ];
      expect(a[0], greaterThan(0));
      expect(a[0], lessThan(a[1]));
      expect(a[1], lessThan(a[2]));
      expect(a[2], lessThan(a[3]));
      expect(a[3], 255);
      expect(output.getPixel(x + 16, y).r, 255);
      expect(output.getPixel(x - 2, y).a, 0);
      final p = output.getPixel(
        layout.logoRect.center.dx.round(),
        layout.logoRect.center.dy.round(),
      );
      expect([p.r, p.g, p.b, p.a], [20, 100, 210, 255]);
      expect(output.getPixel(160, 200).a, 0);
      s.gapFeather = 0;
      final hard = img.decodePng(await exportFrame(s, logo: logo))!;
      expect(hard.getPixel(x + 4, y).a, 255);
      Directory('output/qa').createSync(recursive: true);
      File(
        'output/qa/frame-soft-gap.png',
      ).writeAsBytesSync(img.encodePng(output));
      logo.dispose();
    },
  );
  test(
    'Painter revisions skip unchanged redraws and detect mutations',
    () async {
      final logo = await logoImage();
      final s = FrameSettings();
      final before = FramePainter(s, logo: logo);
      expect(FramePainter(s, logo: logo).shouldRepaint(before), isFalse);
      s.gapFeather += 10;
      expect(FramePainter(s, logo: logo).shouldRepaint(before), isTrue);
      final pattern = PatternSettings();
      final oldPattern = PatternPainter(logo, pattern);
      expect(PatternPainter(logo, pattern).shouldRepaint(oldPattern), isFalse);
      pattern.opacity = .2;
      expect(PatternPainter(logo, pattern).shouldRepaint(oldPattern), isTrue);
      logo.dispose();
    },
  );
  testWidgets(
    'Frame resolution stays separate from ratio and transparency updates live',
    (tester) async {
      final s = FrameSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => FrameControls(
                  settings: s,
                  hasLogo: false,
                  onChanged: () => update(() {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('4K'));
      await tester.pumpAndSettle();
      expect([s.width, s.height], [2160, 3840]);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '9:16'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('3:4'));
      await tester.pumpAndSettle();
      expect([s.width, s.height], [2880, 3840]);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '4K'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('قياسية'));
      await tester.pumpAndSettle();
      expect([s.width, s.height], [1440, 1920]);
      final input = find.byKey(const ValueKey('number-شفافية الفريم'));
      await tester.ensureVisible(input);
      await tester.enterText(input, '75');
      await tester.pump();
      expect(s.opacity, .25);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Frame transparency changes PNG alpha for drawn and repeated-logo borders',
    () async {
      final logo = await logoImage();
      for (final style in [FrameStyle.minimal, FrameStyle.logoRepeat]) {
        final s = FrameSettings()
          ..width = 320
          ..height = 400
          ..style = style
          ..showLogo = false
          ..opacity = .25;
        final faded = img.decodePng(await exportFrame(s, logo: logo))!;
        expect(faded.any((p) => p.a > 0), isTrue);
        expect(faded.every((p) => p.a <= 64), isTrue);
        expect(faded.getPixel(160, 200).a, 0);
        s.opacity = 0;
        final hidden = img.decodePng(await exportFrame(s, logo: logo))!;
        expect(hidden.every((p) => p.a == 0), isTrue);
      }
      logo.dispose();
    },
  );
  for (final style in FrameStyle.values.where(
    (s) => s != FrameStyle.logoRepeat,
  )) {
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
    'Logo border base points inward on every edge, preserves RGB and alpha',
    () async {
      final source = img.Image(width: 40, height: 20, numChannels: 4);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 40; x++) {
          source.setPixelRgba(
            x,
            y,
            y < 10 ? 230 : 20,
            50,
            y < 10 ? 20 : 230,
            255,
          );
        }
      }
      final codec = await ui.instantiateImageCodec(img.encodePng(source));
      final logo = (await codec.getNextFrame()).image;
      final s = FrameSettings()
        ..style = FrameStyle.logoRepeat
        ..width = 320
        ..height = 400
        ..inset = 24
        ..repeatScale = .125
        ..opacity = .5;
      final output = img.decodePng(await exportFrame(s, logo: logo))!;
      expect(output.numChannels, 4);
      expect(output.getPixel(160, 200).a, 0);
      expect(output.getPixel(0, 0).a, 0);
      // Blue is the base of the source logo and must face the canvas center.
      for (final point in [(64, 38), (64, 361), (38, 64), (281, 64)]) {
        final p = output.getPixel(point.$1, point.$2);
        expect(p.r, closeTo(20, 2));
        expect(p.b, closeTo(230, 2));
        expect(p.a, closeTo(128, 1));
      }
      for (final p in output) {
        expect(
          p.a,
          lessThanOrEqualTo(128),
          reason: 'Perpendicular runs do not overlap',
        );
      }
      int runs(img.Image image) {
        var count = 0, previous = false;
        for (var x = 0; x < image.width; x++) {
          final visible = image.getPixel(x, 34).a > 0;
          if (visible && !previous) count++;
          previous = visible;
        }
        return count;
      }

      s.repeatSpacing = .15;
      final spaced = img.decodePng(await exportFrame(s, logo: logo))!;
      expect(runs(spaced), lessThan(runs(output)));
      s.repeatScale = .25;
      s.inset = 76;
      final extreme = img.decodePng(await exportFrame(s, logo: logo))!;
      expect(extreme.any((p) => p.a > 0), isTrue);
      expect(extreme.getPixel(160, 200).a, 0);
      Directory('output/qa').createSync(recursive: true);
      File(
        'output/qa/logo-repeat-frame.png',
      ).writeAsBytesSync(img.encodePng(output));
      logo.dispose();
      codec.dispose();
    },
  );
  test(
    'Logo border without an imported logo stays completely transparent',
    () async {
      final s = FrameSettings()..style = FrameStyle.logoRepeat;
      final output = img.decodePng(await exportFrame(s))!;
      expect(output.every((p) => p.a == 0), isTrue);
    },
  );
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
        final r = FrameLayout.calculate(s, null).border;
        final left = r.left.round(), right = r.right.round();
        final top = r.top.round(), bottom = r.bottom.round();
        expect(output.getPixel(reverse ? right : left, top).a, greaterThan(0));
        expect(
          output.getPixel(reverse ? left : right, bottom).a,
          greaterThan(0),
        );
        expect(output.getPixel(reverse ? left : right, top).a, 0);
        expect(output.getPixel(reverse ? right : left, bottom).a, 0);
        expect(output.getPixel(160, top).a, 0);
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
