// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

abstract final class ImageSaver {
  static bool get canOpenSavedImage => false;

  static Future<bool> ensureAccess() async => true;

  static Future<void> saveImageBytes(
    Uint8List bytes, {
    required String name,
  }) async {
    final blob = html.Blob([bytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = '$name.png'
      ..style.display = 'none';

    try {
      html.document.body?.append(anchor);
      anchor.click();
    } finally {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    }
  }
}
