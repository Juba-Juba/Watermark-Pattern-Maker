import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'image_processing.dart';
import 'pattern.dart';
import 'save_file.dart';

void main() {
  runApp(const WatermarkApp());
}

class WatermarkApp extends StatefulWidget {
  const WatermarkApp({super.key});
  @override
  State<WatermarkApp> createState() => _WatermarkAppState();
}

class _WatermarkAppState extends State<WatermarkApp> {
  ThemeMode mode = ThemeMode.dark;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Watermark Pattern Maker',
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeMode: mode,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xff7654cf),
      fontFamily: 'NotoSansArabic',
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff10121c),
      colorSchemeSeed: const Color(0xffb99afc),
      fontFamily: 'NotoSansArabic',
    ),
    home: Editor(
      onTheme: () => setState(
        () => mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
    ),
  );
}

class Editor extends StatefulWidget {
  final VoidCallback onTheme;
  const Editor({super.key, required this.onTheme});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  PatternSettings s = PatternSettings();
  ui.Image? logo, background;
  final picker = ImagePicker();
  bool busy = false;
  int backdrop = 0;
  String? filename;
  Map<String, dynamic> presets = {};
  String? selectedPreset;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      presets = Map<String, dynamic>.from(
        jsonDecode(prefs.getString('presets') ?? '{}') as Map,
      );
    } catch (_) {
      presets = {};
    }
    if (mounted) {
      setState(() {});
    }
    if (!kIsWeb) {
      try {
        final lost = await picker.retrieveLostData();
        if (lost.files?.isNotEmpty ?? false) {
          await importBytes(
            await lost.files!.first.readAsBytes(),
            lost.files!.first.name,
          );
        }
      } catch (e) {
        message('تعذر استعادة الصورة: $e');
      }
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> task(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      message('تعذر إتمام العملية: $e');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> importBytes(Uint8List bytes, String name) async {
    if (bytes.length > 40 * 1024 * 1024) {
      throw const FormatException('الحد الأقصى للصورة 40 MB');
    }
    final normalized = await compute(normalizeLogo, bytes);
    final codec = await ui.instantiateImageCodec(normalized);
    final next = (await codec.getNextFrame()).image;
    codec.dispose();
    if (!mounted) {
      next.dispose();
      return;
    }
    final old = logo;
    setState(() {
      logo = next;
      filename = name;
      autoFit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  void autoFit() {
    if (logo == null) {
      return;
    }
    final aspect = logo!.width / logo!.height;
    s.scale = math.min(s.width / 4.4, s.height / 6 * aspect).clamp(24, 800);
    s.spacingX = (s.scale * .7).clamp(0, 600);
    s.spacingY = (s.scale / aspect * .8).clamp(0, 600);
    s.limit = 1000;
  }

  Future<void> pick({bool isBackground = false}) => task(() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      return;
    }
    if (isBackground) {
      final bytes = await compute(normalizeLogo, await file.readAsBytes());
      final codec = await ui.instantiateImageCodec(bytes);
      final next = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        next.dispose();
        return;
      }
      final old = background;
      setState(() {
        background = next;
        backdrop = 3;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } else {
      await importBytes(await file.readAsBytes(), file.name);
    }
  });
  Future<void> export() => task(() async {
    if (logo == null) {
      return;
    }
    final bytes = await exportPattern(logo!, s);
    final saved = await savePng(
      bytes,
      'watermark_${s.width}x${s.height}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    if (saved) {
      message('تم تصدير PNG بخلفية شفافة');
    }
  });
  Future<void> savePreset() async {
    final controller = TextEditingController(
      text: 'إعداد ${presets.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حفظ إعدادات النمط'),
        content: TextField(
          controller: controller,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'اسم الإعداد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    // Dialog animations may still reference its controller.
    if (name == null) {
      return;
    }
    await task(() async {
      final next = {...presets, name: s.toJson()};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('presets', jsonEncode(next));
      setState(() {
        presets = next;
        selectedPreset = name;
      });
      message('تم حفظ الإعداد على هذا الجهاز');
    });
  }

  Future<void> customSize() async {
    final w = TextEditingController(text: '${s.width}'),
        h = TextEditingController(text: '${s.height}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('مقاس مخصص'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: w,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العرض بالبكسل'),
              ),
              TextField(
                controller: h,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الارتفاع بالبكسل',
                ),
              ),
              const Text('من 64 إلى 4096 بكسل لكل بُعد'),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final width = int.tryParse(w.text),
                    height = int.tryParse(h.text);
                if (width == null ||
                    height == null ||
                    width < 64 ||
                    height < 64 ||
                    width > 4096 ||
                    height > 4096) {
                  update(() => error = 'أدخل أبعادًا صحيحة ضمن المدى');
                  return;
                }
                setState(() {
                  s.width = width;
                  s.height = height;
                  autoFit();
                });
                Navigator.pop(c);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change, {
    String suffix = '',
  }) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '${value.round()}$suffix',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: (v) => setState(() => change(v)),
      ),
    ],
  );
  Widget section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget preview({
    bool full = false,
    double height = 350,
    VoidCallback? refresh,
  }) => Column(
    children: [
      Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'معاينة مباشرة',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${s.width} × ${s.height}', textDirection: TextDirection.ltr),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: full ? MediaQuery.sizeOf(context).height * .65 : height,
        child: Center(
          child: AspectRatio(
            aspectRatio: s.width / s.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop == 0)
                    CustomPaint(painter: CheckerPainter())
                  else
                    ColoredBox(
                      color: backdrop == 1 ? Colors.black : Colors.white,
                    ),
                  if (backdrop == 3 && background != null)
                    RawImage(image: background, fit: BoxFit.cover),
                  if (logo != null)
                    CustomPaint(painter: PatternPainter(logo!, s))
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: 160,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.texture_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'شعارك، بنمط متكرر',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xff3b3256),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'استورد PNG شفاف للبدء',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xff3b3256)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 5,
        children: [
          for (final item in [(0, 'شفافة'), (1, 'سوداء'), (2, 'بيضاء')])
            ChoiceChip(
              label: Text(item.$2),
              selected: backdrop == item.$1,
              onSelected: (_) {
                setState(() => backdrop = item.$1);
                refresh?.call();
              },
            ),
          ActionChip(
            label: const Text('صورة'),
            avatar: const Icon(Icons.photo_outlined, size: 16),
            onPressed: busy ? null : () => pick(isBackground: true),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'خلفية المعاينة لا تدخل في التصدير',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
  Widget controls() => Column(
    children: [
      section('01  •  الشعار', [
        FilledButton.icon(
          onPressed: busy ? null : () => pick(),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('استيراد صورة الشعار'),
        ),
        const SizedBox(height: 8),
        Text(
          filename ?? 'PNG • JPG • WebP',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        const Text(
          'نحافظ على الصورة كما هي. استخدم PNG شفاف لنتيجة Overlay جاهزة.',
          style: TextStyle(fontSize: 12),
        ),
        OutlinedButton.icon(
          onPressed: logo == null || busy ? null : () => setState(autoFit),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('ضبط الحجم والمسافات تلقائيًا'),
        ),
      ]),
      section('02  •  مساحة التصميم', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in [
              (1080, 1920, '9:16'),
              (1440, 1920, '3:4'),
              (1920, 1920, '1:1'),
              (1920, 1080, '16:9'),
            ])
              ChoiceChip(
                label: Text(p.$3),
                selected: s.width * p.$2 == s.height * p.$1,
                onSelected: (_) => setState(() {
                  s.width = p.$1;
                  s.height = p.$2;
                  autoFit();
                }),
              ),
            ActionChip(label: const Text('مخصص'), onPressed: customSize),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() {
            final factor = 3840 / math.max(s.width, s.height);
            s.width = (s.width * factor).round();
            s.height = (s.height * factor).round();
            autoFit();
          }),
          child: const Text('رفع الدقة إلى 4K'),
        ),
      ]),
      section('03  •  توزيع النمط', [
        SegmentedButton<PatternKind>(
          segments: const [
            ButtonSegment(value: PatternKind.grid, label: Text('شبكة')),
            ButtonSegment(value: PatternKind.staggered, label: Text('متبادل')),
            ButtonSegment(value: PatternKind.diagonal, label: Text('قطري')),
          ],
          selected: {s.kind},
          onSelectionChanged: (v) => setState(() => s.kind = v.first),
        ),
        const SizedBox(height: 16),
        slider(
          'حجم الشعار',
          s.scale,
          24,
          800,
          (v) => s.scale = v,
          suffix: ' px',
        ),
        slider('المسافة الأفقية', s.spacingX, 0, 600, (v) => s.spacingX = v),
        slider('المسافة الرأسية', s.spacingY, 0, 600, (v) => s.spacingY = v),
        slider(
          'زاوية الميل',
          s.rotation,
          -180,
          180,
          (v) => s.rotation = v,
          suffix: '°',
        ),
        slider(
          'الشفافية',
          s.opacity * 100,
          0,
          100,
          (v) => s.opacity = v / 100,
          suffix: '%',
        ),
        ExpansionTile(
          title: const Text('العدد والإزاحة'),
          tilePadding: EdgeInsets.zero,
          children: [
            slider(
              'الحد الأقصى للعناصر',
              s.limit.toDouble(),
              1,
              2000,
              (v) => s.limit = v.round(),
            ),
            slider('إزاحة أفقية', s.offsetX, -600, 600, (v) => s.offsetX = v),
            slider('إزاحة رأسية', s.offsetY, -600, 600, (v) => s.offsetY = v),
          ],
        ),
      ]),
      section('04  •  اللون', [
        Wrap(
          spacing: 8,
          children: [
            for (final t in [
              (LogoTone.original, 'الأصلي'),
              (LogoTone.pink, 'بمبي'),
              (LogoTone.gray, 'رصاصي متدرج'),
              (LogoTone.custom, 'مخصص'),
            ])
              ChoiceChip(
                label: Text(t.$2),
                selected: s.tone == t.$1,
                onSelected: (_) => setState(() => s.tone = t.$1),
              ),
          ],
        ),
        if (s.tone == LogoTone.custom) ...[
          const SizedBox(height: 12),
          slider(
            'أحمر',
            s.color.r * 255,
            0,
            255,
            (v) => s.color = Color.fromARGB(
              255,
              v.round(),
              (s.color.g * 255).round(),
              (s.color.b * 255).round(),
            ),
          ),
          slider(
            'أخضر',
            s.color.g * 255,
            0,
            255,
            (v) => s.color = Color.fromARGB(
              255,
              (s.color.r * 255).round(),
              v.round(),
              (s.color.b * 255).round(),
            ),
          ),
          slider(
            'أزرق',
            s.color.b * 255,
            0,
            255,
            (v) => s.color = Color.fromARGB(
              255,
              (s.color.r * 255).round(),
              (s.color.g * 255).round(),
              v.round(),
            ),
          ),
          Container(
            height: 24,
            decoration: BoxDecoration(
              color: s.color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ]),
      section('05  •  إعداداتك المحفوظة', [
        if (presets.isNotEmpty)
          DropdownButton<String>(
            isExpanded: true,
            value: selectedPreset,
            hint: const Text('اختر إعدادًا محفوظًا'),
            items: presets.keys
                .map(
                  (k) => DropdownMenuItem(
                    value: k,
                    child: Text(k, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (key) {
                    if (key != null) {
                      try {
                        setState(() {
                          s = PatternSettings.fromJson(
                            Map<String, dynamic>.from(presets[key] as Map),
                          );
                          selectedPreset = key;
                        });
                      } catch (_) {
                        message('الإعداد المحفوظ غير صالح');
                      }
                    }
                  },
          ),
        OutlinedButton.icon(
          onPressed: busy ? null : savePreset,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('حفظ إعدادات'),
        ),
        if (selectedPreset != null)
          TextButton(
            onPressed: busy
                ? null
                : () => task(() async {
                    presets.remove(selectedPreset);
                    selectedPreset = null;
                    await (await SharedPreferences.getInstance()).setString(
                      'presets',
                      jsonEncode(presets),
                    );
                  }),
            child: const Text('حذف الإعداد المحدد'),
          ),
      ]),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Watermark',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(
            'PATTERN MAKER',
            style: TextStyle(fontSize: 10, letterSpacing: 2),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'تبديل المظهر',
          onPressed: widget.onTheme,
          icon: const Icon(Icons.brightness_6_outlined),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: FilledButton.icon(
          onPressed: logo == null || busy ? null : export,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined),
          label: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              busy
                  ? 'جاري المعالجة…'
                  : 'تصدير PNG شفاف  •  ${s.width} × ${s.height}',
            ),
          ),
        ),
      ),
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 850;
          final previewCard = Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  preview(
                    height: wide
                        ? 350
                        : (constraints.maxHeight * .27).clamp(110, 240),
                  ),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => StatefulBuilder(
                        builder: (c, update) => Dialog.fullscreen(
                          child: Scaffold(
                            appBar: AppBar(title: const Text('معاينة النمط')),
                            body: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: preview(
                                  full: true,
                                  refresh: () => update(() {}),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('معاينة'),
                  ),
                ],
              ),
            ),
          );
          if (wide) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1300),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: controls(),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: previewCard,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Column(
              children: [
                previewCard,
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 10, bottom: 16),
                    child: controls(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
  @override
  void dispose() {
    logo?.dispose();
    background?.dispose();
    super.dispose();
  }
}

class CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff1eff6),
    );
    final paint = Paint()..color = const Color(0xffd9d5e3);
    for (var y = 0; y < size.height / 14; y++) {
      for (var x = 0; x < size.width / 14; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(Rect.fromLTWH(x * 14, y * 14, 14, 14), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
