import 'package:flutter/services.dart';

Future<bool> savePng(Uint8List bytes, String name) async =>
    await const MethodChannel(
      'watermark/files',
    ).invokeMethod<bool>('savePng', {'bytes': bytes, 'name': name}) ??
    false;
