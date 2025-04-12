import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

class NfcUtils {
  /// Polls for an NFC tag with specified parameters.
  static Future<NFCTag> pollForTag(
      {String iosAlertMessage = "Hold your iPhone near the card"}) async {
    return await FlutterNfcKit.poll(
      iosAlertMessage: iosAlertMessage,
      readIso14443A: true,
      readIso14443B: true,
      readIso18092: false,
      readIso15693: false,
    );
  }
}
