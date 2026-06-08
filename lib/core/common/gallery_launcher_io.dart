import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

class GalleryLauncher {
  static const MethodChannel _channel = MethodChannel('simon_ledger/gallery');

  static Future<void> openGalleryApp() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openGalleryApp');
      return;
    }
    await Gal.open();
  }

  static Future<void> openImageByName(String imageName) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('openImageByName', {
        'imageName': imageName,
      });
      return;
    }
    await Gal.open();
  }
}
