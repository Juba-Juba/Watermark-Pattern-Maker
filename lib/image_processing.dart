import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Keeps every nontransparent pixel intact; trims only empty alpha margins.
Uint8List normalizeLogo(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null) {
    throw const FormatException('صورة غير مدعومة أو تالفة');
  }
  if (info.width > 8192 ||
      info.height > 8192 ||
      info.width * info.height > 20000000) {
    throw const FormatException(
      'اختر صورة أقل من 20 ميجابكسل وبأبعاد لا تتجاوز 8192',
    );
  }
  var image = decoder!.decodeFrame(0);
  if (image == null) {
    throw const FormatException('تعذر قراءة الصورة');
  }
  image = img.bakeOrientation(image).convert(numChannels: 4);
  var left = image.width, top = image.height, right = -1, bottom = -1;
  for (final p in image) {
    if (p.a == 0) {
      continue;
    }
    if (p.x < left) {
      left = p.x;
    }
    if (p.x > right) {
      right = p.x;
    }
    if (p.y < top) {
      top = p.y;
    }
    if (p.y > bottom) {
      bottom = p.y;
    }
  }
  if (right == -1) {
    throw const FormatException('الصورة شفافة بالكامل');
  }
  if (left > 0 ||
      top > 0 ||
      right < image.width - 1 ||
      bottom < image.height - 1) {
    image = img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}
