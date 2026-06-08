import 'dart:typed_data';

import 'package:gal/gal.dart';

abstract final class ImageSaver {
  static bool get canOpenSavedImage => true;

  static Future<bool> ensureAccess() async {
    final hasAccess = await Gal.hasAccess();
    if (hasAccess) {
      return true;
    }
    return Gal.requestAccess();
  }

  static Future<void> saveImageBytes(Uint8List bytes, {required String name}) {
    return Gal.putImageBytes(bytes, name: name);
  }
}
