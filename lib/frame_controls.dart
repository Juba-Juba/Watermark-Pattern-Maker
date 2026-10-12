import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'frame.dart';
import 'number_slider.dart';

class FrameControls extends StatelessWidget {
  final FrameSettings settings;
  final VoidCallback onChanged;
  final bool hasLogo;
  final ui.Image? logo;
  const FrameControls({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.hasLogo,
    this.logo,
  });

  void update(VoidCallback change) {
    change();
    onChanged();
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change, {
    String suffix = 'px',
  }) => NumberSlider(
    key: ValueKey('frame-$label'),
    label: label,
    value: value,
    min: min,
    max: max,
    suffix: suffix,
    onChanged: (v) => update(() => change(v)),
  );
  Future<void> customSize(BuildContext context) async {
    final width = TextEditingController(text: '${settings.width}');
    final height = TextEditingController(text: '${settings.height}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('مقاس الفريم بالبكسل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: width,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العرض'),
              ),
              TextField(
                controller: height,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الارتفاع'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(c).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final w = int.tryParse(width.text),
                    h = int.tryParse(height.text);
                if (w == null ||
                    h == null ||
                    w < 64 ||
                    h < 64 ||
                    w > 4096 ||
                    h > 4096) {
                  setLocal(() => error = 'اختر أبعادًا من 64 إلى 4096');
                  return;
                }
                update(() {
                  settings.width = w;
                  settings.height = h;
                });
                Navigator.pop(c);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    // Retain dialog controllers through its closing animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    width.dispose();
    height.dispose();
  }

  Future<void> customColor(BuildContext context) async {
    final controller = TextEditingController(
      text: settings.color
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase(),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('لون الفريم'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 7,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'HEX',
                  hintText: '#C8CCD2',
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final hex = controller.text.trim().replaceFirst('#', '');
                final value = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
                    ? int.tryParse(hex, radix: 16)
                    : null;
                if (value == null) {
                  setLocal(() => error = 'اكتب ست خانات للون');
                  return;
                }
                update(() => settings.color = Color(0xff000000 | value));
                Navigator.pop(c);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    Widget card(String title, List<Widget> children) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
    return Column(
      children: [
        card('مقاس الفريم', [
          Wrap(
            spacing: 6,
            runSpacing: 6,
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
                  onSelected: (_) => update(() {
                    final factor = math.max(s.width, s.height) == 3840 ? 2 : 1;
                    s.width = p.$1 * factor;
                    s.height = p.$2 * factor;
                  }),
                ),
              ActionChip(
                label: const Text('مقاس مخصص'),
                onPressed: () => customSize(context),
              ),
            ],
          ),
        ]),
        card('دقة تصدير الفريم', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final resolution in [(1920, 'قياسية'), (3840, '4K')])
                ChoiceChip(
                  label: Text(resolution.$2),
                  selected: math.max(s.width, s.height) == resolution.$1,
                  onSelected: (_) => update(() {
                    final factor = resolution.$1 / math.max(s.width, s.height);
                    s.width = (s.width * factor).round();
                    s.height = (s.height * factor).round();
                    s.stroke *= factor;
                    s.inset *= factor;
                    s.radius *= factor;
                    s.gap *= factor;
                    s.gapFeather *= factor;
                    s.logoInset *= factor;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${s.width} × ${s.height} بكسل — الدقة تحافظ على نسبة المقاس'),
        ]),
        card('شفافية الفريم', [
          slider(
            'شفافية الفريم',
            (1 - s.opacity) * 100,
            0,
            100,
            (v) => s.opacity = 1 - v / 100,
            suffix: '%',
          ),
          const Text(
            '0% ظاهر بالكامل · 100% شفاف بالكامل',
            style: TextStyle(fontSize: 12),
          ),
        ]),
        card('اختر تصميم الفريم', [
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in FrameStyle.values)
                  SizedBox(
                    width: (constraints.maxWidth - 16) / 3,
                    child: Semantics(
                      button: true,
                      selected: s.style == style,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => update(() {
                          s.style = style;
                          if (style == FrameStyle.oppositeCorners) {
                            s.position = FramePosition.topLeft;
                          } else if (style ==
                              FrameStyle.oppositeCornersReverse) {
                            s.position = FramePosition.topRight;
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: s.style == style
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).dividerColor,
                              width: s.style == style ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 78,
                                child: RepaintBoundary(
                                  child:
                                      style == FrameStyle.logoRepeat &&
                                          logo == null
                                      ? const Icon(Icons.border_outer, size: 42)
                                      : CustomPaint(
                                          size: const Size(110, 78),
                                          painter: FramePainter(
                                            FrameSettings()
                                              ..width = 240
                                              ..height = 300
                                              ..style = style
                                              ..inset = 24
                                              ..stroke = 3
                                              ..radius = 12
                                              ..color = s.color,
                                            logo: style == FrameStyle.logoRepeat
                                                ? logo
                                                : null,
                                          ),
                                        ),
                                ),
                              ),
                              Text(
                                frameStyleNames[style.index],
                                style: const TextStyle(fontSize: 12),
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
          if (s.style == FrameStyle.oppositeCorners ||
              s.style == FrameStyle.oppositeCornersReverse)
            slider(
              'طول أذرع الزوايا',
              s.cornerLength * 100,
              10,
              48,
              (v) => s.cornerLength = v / 100,
              suffix: '%',
            ),
          const SizedBox(height: 12),
          if (s.style == FrameStyle.logoRepeat) ...[
            const Text(
              'اللوجو يتكرر بألوانه الأصلية؛ قاعدة الصف السفلي لأسفل للخارج، وباقي الأطراف للداخل.',
            ),
            if (!hasLogo) const Text('استورد اللوجو أولًا لتكوين الفريم.'),
            slider(
              'حجم اللوجو المتكرر',
              s.repeatScale * 100,
              4,
              25,
              (v) => s.repeatScale = v / 100,
              suffix: '%',
            ),
            slider(
              'المسافة بين اللوجوهات',
              s.repeatSpacing * 100,
              0,
              15,
              (v) => s.repeatSpacing = v / 100,
              suffix: '%',
            ),
          ],
          if (s.style != FrameStyle.logoRepeat)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final color in [
                  (const Color(0xffc8ccd2), 'فضي'),
                  (const Color(0xffc5a35b), 'ذهبي'),
                  (Colors.white, 'أبيض'),
                  (const Color(0xff3d444c), 'رصاصي'),
                  (Colors.black, 'أسود'),
                ])
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: color.$1, radius: 7),
                    label: Text(color.$2),
                    selected: s.color == color.$1,
                    onSelected: (_) => update(() => s.color = color.$1),
                  ),
                ActionChip(
                  label: const Text('لون مخصص'),
                  onPressed: () => customColor(context),
                ),
              ],
            ),
        ]),
        if (s.style != FrameStyle.logoRepeat)
          card('اللوجو داخل الفريم', [
            if (!hasLogo)
              const Text(
                'استورد لوجو PNG من الزر أعلى الإعدادات. يظهر بألوانه الأصلية في فتحة شفافة من الفريم.',
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار اللوجو وفتح الفريم'),
              value: s.showLogo,
              onChanged: hasLogo ? (v) => update(() => s.showLogo = v) : null,
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final position in FramePosition.values)
                  ChoiceChip(
                    label: Text(
                      framePositionNames[position.index],
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: s.position == position,
                    onSelected: (_) => update(() => s.position = position),
                  ),
              ],
            ),
            if (s.position == FramePosition.sideMarks)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'شمال أعلى المنتصف قليلًا + يمين أسفل المنتصف قليلًا',
                ),
              )
            else ...[
              SwitchListTile(
                key: const ValueKey('duplicate-logo'),
                contentPadding: EdgeInsets.zero,
                title: const Text('تكرار اللوجو'),
                subtitle: const Text(
                  'نسخة إضافية بنفس الحجم والشفافية والإعدادات',
                ),
                value: s.duplicateLogo,
                onChanged: (v) => update(() => s.duplicateLogo = v),
              ),
              if (s.duplicateLogo) ...[
                const Text('موقع النسخة الثانية'),
                Wrap(
                  key: const ValueKey('duplicate-logo-positions'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final position in FramePosition.values.where(
                      (p) => p != FramePosition.sideMarks,
                    ))
                      ChoiceChip(
                        key: ValueKey('duplicate-position-${position.name}'),
                        label: Text(framePositionNames[position.index]),
                        selected: s.duplicatePosition == position,
                        onSelected: (_) =>
                            update(() => s.duplicatePosition = position),
                      ),
                  ],
                ),
              ],
            ],
            slider(
              'حجم اللوجو في الفريم',
              s.logoWidth * 100,
              8,
              60,
              (v) => s.logoWidth = v / 100,
              suffix: '%',
            ),
            slider('فراغ حول اللوجو', s.gap, 0, 120, (v) => s.gap = v),
            slider(
              'تدرج الفراغ نحو الفريم',
              s.gapFeather,
              0,
              240,
              (v) => s.gapFeather = v,
            ),
            const Text(
              'يتلاشى الفريم بجوار اللوجو ثم يظهر تدريجيًا باتجاه الأطراف.',
              style: TextStyle(fontSize: 12),
            ),
            slider(
              'ظهور اللوجو',
              s.logoOpacity * 100,
              0,
              100,
              (v) => s.logoOpacity = v / 100,
              suffix: '%',
            ),
          ]),
        card('بعد اللوجو عن الحافة', [
          slider(
            'بعد اللوجو عن الحافة',
            s.logoInset,
            0,
            math.min(s.width, s.height) * .24,
            (v) => s.logoInset = v,
          ),
          const Text(
            'يتحرك كل لوجو للداخل حسب موقعه، ويشمل النسخ والعلامات الجانبية وفريم اللوجو.',
          ),
        ]),
        card('ضبط الفريم', [
          if (s.style != FrameStyle.logoRepeat)
            slider(
              'سمك الفريم',
              s.stroke,
              1,
              math.min(s.width, s.height) * .08,
              (v) => s.stroke = v,
            ),
          slider(
            'بعد الفريم عن الحافة',
            s.inset,
            0,
            math.min(s.width, s.height) * .24,
            (v) => s.inset = v,
          ),
          if (s.style != FrameStyle.logoRepeat)
            slider('استدارة الأركان', s.radius, 0, 200, (v) => s.radius = v),
          Text(
            s.style == FrameStyle.logoRepeat
                ? 'المنتصف شفاف تمامًا، بدون خط أو خلفية خلف اللوجوهات.'
                : 'المنتصف ومساحة اللوجو شفافان في PNG. يمكنك تصدير الفريم وحده أيضًا.',
            style: TextStyle(fontSize: 12),
          ),
        ]),
      ],
    );
  }
}
