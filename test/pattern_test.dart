import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_pattern_maker/pattern.dart';
import 'package:watermark_pattern_maker/image_processing.dart';
import 'package:watermark_pattern_maker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class FakePicker extends ImagePickerPlatform {
  @override
  Future<LostDataResponse> getLostData() async => LostDataResponse.empty();
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(
    fixture(),
    path: 'test-logo.png',
    name: 'test-logo.png',
    mimeType: 'image/png',
  );
}

Uint8List fixture() {
  final image = img.Image(width: 80, height: 60, numChannels: 4);
  img.fillRect(
    image,
    x1: 20,
    y1: 10,
    x2: 59,
    y2: 49,
    color: img.ColorRgba8(20, 100, 210, 255),
  );
  image.setPixelRgba(25, 25, 50, 60, 70, 128);
  return Uint8List.fromList(img.encodePng(image));
}

Future<ui.Image> logoImage() async {
  final codec = await ui.instantiateImageCodec(fixture());
  final result = (await codec.getNextFrame()).image;
  codec.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ImagePickerPlatform.instance = FakePicker();
  });
  testWidgets(
    'Import through picker, auto fit, save preset, export through platform channel',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uint8List? exported;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('watermark/files'),
        (call) async {
          expect(call.method, 'savePng');
          exported = (call.arguments as Map)['bytes'] as Uint8List;
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('watermark/files'),
          null,
        ),
      );
      await tester.pumpWidget(const WatermarkApp());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('استيراد صورة الشعار'));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('test-logo.png').evaluate().isNotEmpty) {
            break;
          }
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('test-logo.png'), findsOneWidget);
      final pattern = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<PatternPainter>()
          .first;
      expect(pattern.settings.scale, closeTo(245.45, .1));
      await tester.runAsync(() async {
        await tester.tap(find.textContaining('تصدير PNG شفاف'));
        for (var i = 0; i < 30 && exported == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(exported, isNotNull);
      expect(img.decodePng(exported!)!.any((p) => p.a == 0), true);
      await tester.tap(find.text('المحفوظات'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('حفظ إعدادات'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('حفظ إعدادات'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'اختبار الشعار');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('presets'), contains('اختبار الشعار'));
      expect(tester.takeException(), isNull);
    },
  );
  test('PNG import trims only empty margins and preserves exact RGBA', () {
    final result = img.decodePng(normalizeLogo(fixture()))!;
    expect(result.width, 40);
    expect(result.height, 40);
    final p = result.getPixel(5, 15);
    expect([p.r, p.g, p.b, p.a], [50, 60, 70, 128]);
  });
  test('Lossless WebP imports with original alpha and colors', () {
    final image = img.decodePng(
      normalizeLogo(File('test/fixtures/logo.webp').readAsBytesSync()),
    )!;
    expect([image.width, image.height], [16, 10]);
    final p = image.getPixel(0, 0);
    expect([p.r, p.g, p.b, p.a], [210, 80, 145, 180]);
  });
  test('JPEG import preserves opaque background rather than removing it', () {
    final source = img.Image(width: 30, height: 20);
    img.fill(source, color: img.ColorRgb8(230, 120, 60));
    final result = img.decodePng(
      normalizeLogo(Uint8List.fromList(img.encodeJpg(source))),
    )!;
    expect(result.width, 30);
    expect(result.height, 20);
    expect(result.getPixel(0, 0).a, 255);
  });
  test('Reject corrupt or fully empty images', () {
    expect(
      () => normalizeLogo(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => normalizeLogo(
        Uint8List.fromList(
          img.encodePng(img.Image(width: 4, height: 4, numChannels: 4)),
        ),
      ),
      throwsFormatException,
    );
  });
  test('Reject oversized image from header before pixel decoding', () {
    final source = img.Image(width: 9000, height: 1, numChannels: 4);
    expect(
      () => normalizeLogo(Uint8List.fromList(img.encodePng(source))),
      throwsFormatException,
    );
  });
  test('Preset roundtrip and safe validation', () {
    final s = PatternSettings()
      ..width = 3840
      ..height = 2160
      ..rotation = -44
      ..tone = LogoTone.custom
      ..offsetX = 80;
    expect(PatternSettings.fromJson(s.toJson()).toJson(), s.toJson());
    final values = s.toJson()
      ..['width'] = 99999
      ..['opacity'] = -8;
    final restored = PatternSettings.fromJson(values);
    expect(restored.width, 4096);
    expect(restored.opacity, 0);
  });
  test('Old pink presets migrate to gray; alternating rows persist', () {
    final values = PatternSettings().toJson()..remove('toneName');
    values['tone'] = 1;
    expect(PatternSettings.fromJson(values).tone, LogoTone.gray);
    final settings = PatternSettings()
      ..alternateRotation = 90
      ..alternateScale = .6
      ..spacingX = -40;
    expect(
      PatternSettings.fromJson(settings.toJson()).toJson(),
      settings.toJson(),
    );
  });
  testWidgets(
    'Numeric spacing and opacity update the actual painter independently',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const WatermarkApp());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('استيراد صورة الشعار'));
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (find.text('test-logo.png').evaluate().isNotEmpty) break;
        }
      });
      await tester.pumpAndSettle();
      PatternSettings current() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<PatternPainter>()
          .first
          .settings;
      final initialY = current().spacingY;
      await tester.enterText(
        find.byKey(const ValueKey('number-المسافة الأفقية · الأعمدة')),
        '250',
      );
      await tester.pump();
      expect(current().spacingX, closeTo(current().scale * 1.5, .01));
      expect(current().spacingY, initialY);
      await tester.enterText(
        find.byKey(const ValueKey('number-المسافة الرأسية · الصفوف')),
        '75',
      );
      await tester.pump();
      expect(current().spacingY, closeTo(-current().scale * .25, .01));
      await tester.enterText(
        find.byKey(const ValueKey('number-الشفافية')),
        '18',
      );
      await tester.pump();
      expect(current().opacity, .18);
      expect(current().tone, LogoTone.gray);
      expect(find.text('بمبي'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Column and row spacing change repetition along their own axes',
    () async {
      final logo = await logoImage();
      final settings = PatternSettings()
        ..width = 320
        ..height = 240
        ..scale = 40
        ..kind = PatternKind.grid
        ..rotation = 0
        ..tone = LogoTone.original
        ..opacity = 1
        ..spacingX = 20
        ..spacingY = 20;
      final first = img.decodePng(await exportPattern(logo, settings))!;
      settings.spacingX = 100;
      final second = img.decodePng(await exportPattern(logo, settings))!;
      int horizontal(img.Image image) => List.generate(
        320,
        (x) => image.getPixel(x, 0).a,
      ).where((a) => a > 0).length;
      int vertical(img.Image image) => List.generate(
        240,
        (y) => image.getPixel(0, y).a,
      ).where((a) => a > 0).length;
      expect(horizontal(second), lessThan(horizontal(first)));
      expect(vertical(second), vertical(first));
      settings.spacingY = 100;
      final third = img.decodePng(await exportPattern(logo, settings))!;
      expect(vertical(third), lessThan(vertical(second)));
      logo.dispose();
    },
  );
  for (final kind in PatternKind.values) {
    test(
      'Export ${kind.name} contains actual transparency and repeated pixels',
      () async {
        final logo = await logoImage();
        final s = PatternSettings()
          ..width = 320
          ..height = 240
          ..scale = 40
          ..spacingX = 50
          ..spacingY = 50
          ..kind = kind
          ..opacity = .5;
        final bytes = await exportPattern(logo, s);
        final image = img.decodePng(bytes)!;
        expect(image.width, 320);
        expect(image.height, 240);
        expect(image.numChannels, 4);
        expect(image.any((p) => p.a == 0), true);
        expect(image.where((p) => p.a > 0).length, greaterThan(100));
        expect(
          image.map((p) => p.a).reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(128),
        );
        logo.dispose();
      },
    );
  }
  for (final tone in LogoTone.values) {
    test('Color ${tone.name} keeps empty alpha transparent', () async {
      final logo = await logoImage();
      final s = PatternSettings()
        ..width = 160
        ..height = 160
        ..scale = 50
        ..spacingX = 100
        ..spacingY = 100
        ..rotation = 0
        ..tone = tone;
      final output = img.decodePng(await exportPattern(logo, s))!;
      expect(output.getPixel(80, 80).a, 0);
      expect(output.any((p) => p.a > 0), true);
      logo.dispose();
    });
  }
  test('Zero opacity exports completely transparent PNG', () async {
    final logo = await logoImage();
    final s = PatternSettings()
      ..width = 120
      ..height = 120
      ..opacity = 0;
    expect(
      img.decodePng(await exportPattern(logo, s))!.every((p) => p.a == 0),
      true,
    );
    logo.dispose();
  });
  test('Element count and offsets affect rendering', () async {
    final logo = await logoImage();
    final s = PatternSettings()
      ..width = 300
      ..height = 300
      ..limit = 3;
    final recorder = ui.PictureRecorder();
    expect(
      PatternPainter(logo, s).draw(Canvas(recorder), const Size(300, 300)),
      3,
    );
    recorder.endRecording().dispose();
    final before = await exportPattern(logo, s);
    s.offsetX = 40;
    expect(await exportPattern(logo, s), isNot(orderedEquals(before)));
    logo.dispose();
  });
  test('4K PNG export is RGBA and background stays empty', () async {
    final logo = await logoImage();
    final s = PatternSettings()
      ..width = 3840
      ..height = 2160
      ..scale = 220;
    final bytes = await exportPattern(logo, s);
    final decoded = img.decodePng(bytes)!;
    expect(
      [decoded.width, decoded.height, decoded.numChannels],
      [3840, 2160, 4],
    );
    expect(decoded.any((p) => p.a == 0), true);
    Directory('output/qa').createSync(recursive: true);
    File('output/qa/pattern-4k-alpha.png').writeAsBytesSync(bytes);
    File('output/qa/import-fixture.png').writeAsBytesSync(fixture());
    logo.dispose();
  });
  for (final width in [360.0, 390.0, 1200.0]) {
    testWidgets('Arabic editor fits ${width.toInt()}px in both themes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const WatermarkApp());
      await tester.pumpAndSettle();
      expect(find.text('استيراد صورة الشعار'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('تبديل المظهر'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('المحفوظات'));
      await tester.pumpAndSettle();
      final buttons = find.text('حفظ إعدادات');
      await tester.scrollUntilVisible(
        buttons,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Landscape phone remains scrollable without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(780, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const WatermarkApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await Scrollable.ensureVisible(
      tester.element(find.text('المحفوظات')),
      alignment: .4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('المحفوظات'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('حفظ إعدادات'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
