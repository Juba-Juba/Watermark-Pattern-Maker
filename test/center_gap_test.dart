import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_pattern_maker/pattern.dart';
import 'package:watermark_pattern_maker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watermark_pattern_maker/number_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image logo;
  setUp(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 40),
      Paint()..color = const Color(0xff1464d2),
    );
    final picture = recorder.endRecording();
    logo = await picture.toImage(40, 40);
    picture.dispose();
  });
  tearDown(() => logo.dispose());
  for (final size in [const Size(390, 844), const Size(780, 390)]) {
    testWidgets('Phone preview scrolls with controls at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const WatermarkApp());
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('scrolling-preview'));
      final before = tester.getRect(preview);
      final scroller = find.byType(SingleChildScrollView).first;
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroller, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      await tester.drag(scroller, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(scroll.pixels, greaterThan(0));
      expect(tester.getRect(preview).top, lessThan(before.top));
      await tester.tap(find.text('الفريم'));
      await tester.pumpAndSettle();
      expect(tester.getRect(preview), before);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Center gap toggle and both controls update live', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const WatermarkApp());
    await tester.pumpAndSettle();
    expect(find.text('حجم الفجوة'), findsOneWidget);
    expect(find.text('شفافية الفجوة'), findsOneWidget);
    final toggle = find.widgetWithText(SwitchListTile, 'فجوة في المنتصف');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    Finder control(String label) =>
        find.byWidgetPredicate((w) => w is NumberSlider && w.label == label);
    expect(control('حجم الفجوة'), findsOneWidget);
    expect(control('شفافية الفجوة'), findsOneWidget);
    tester.widget<NumberSlider>(control('حجم الفجوة')).onChanged(120);
    await tester.pump();
    expect(tester.widget<NumberSlider>(control('حجم الفجوة')).value, 120);
    tester.widget<NumberSlider>(control('شفافية الفجوة')).onChanged(35);
    await tester.pump();
    expect(tester.widget<NumberSlider>(control('شفافية الفجوة')).value, 35);
    expect(tester.takeException(), isNull);
  });
  PatternSettings settings() => PatternSettings()
    ..width = 400
    ..height = 600
    ..scale = 40
    ..rotation = 0
    ..spacingX = 0
    ..spacingY = 0
    ..kind = PatternKind.grid
    ..opacity = 1
    ..centerGap = true
    ..gapSize = .8;

  test(
    'Soft center gap changes alpha only and preserves edge colors',
    () async {
      final output = img.decodePng(await exportPattern(logo, settings()))!;
      expect(output.numChannels, 4);
      expect(output.getPixel(200, 300).a, 0);
      final edge = output.getPixel(10, 10);
      expect([edge.r, edge.g, edge.b, edge.a], [20, 100, 210, 255]);
      final feather = output.getPixel(320, 300);
      expect(feather.a, inExclusiveRange(0, 255));
      // Premultiplied alpha encoding can round RGB by one at feather pixels.
      expect(feather.r, closeTo(20, 1));
      expect(feather.g, closeTo(100, 1));
      expect(feather.b, closeTo(210, 1));
    },
  );
  test('Gap size and transparency independently control mask', () async {
    final s = settings()..gapSize = .4;
    final small = img.decodePng(await exportPattern(logo, s))!;
    s.gapSize = 1.2;
    final large = img.decodePng(await exportPattern(logo, s))!;
    expect(small.getPixel(300, 300).a, 255);
    expect(large.getPixel(300, 300).a, 0);
    s.gapTransparency = .5;
    final half = img.decodePng(await exportPattern(logo, s))!;
    expect(half.getPixel(200, 300).a, closeTo(128, 1));
    s.gapTransparency = 0;
    final zero = await exportPattern(logo, s);
    s.centerGap = false;
    expect(await exportPattern(logo, s), orderedEquals(zero));
  });
  test('Presets persist gap and old presets keep it disabled', () {
    final s = settings()..gapTransparency = .65;
    final restored = PatternSettings.fromJson(s.toJson());
    expect(restored.centerGap, true);
    expect(restored.gapSize, .8);
    expect(restored.gapTransparency, .65);
    final old = s.toJson()
      ..remove('centerGap')
      ..remove('gapSize')
      ..remove('gapTransparency');
    expect(PatternSettings.fromJson(old).centerGap, false);
  });
  test('4K gap export keeps real transparent center', () async {
    final s = settings()
      ..width = 2160
      ..height = 3840
      ..scale = 200;
    final bytes = await exportPattern(logo, s);
    final output = img.decodePng(bytes)!;
    expect([output.width, output.height, output.numChannels], [2160, 3840, 4]);
    expect(output.getPixel(1080, 1920).a, 0);
    expect(output.getPixel(10, 10).a, 255);
    final directory = Directory('output/qa')..createSync(recursive: true);
    File('${directory.path}/center-gap-4k-alpha.png').writeAsBytesSync(bytes);
  });
}
