/*
 * Copyright (C) 2025 Iranians.vote
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class CertificateExporter {
  /// Convert certificate data to PEM format
  static String toPEM(List<int> certificateData) {
    final base64Data = base64Encode(certificateData);
    final pemLines = <String>[];

    pemLines.add('-----BEGIN CERTIFICATE-----');
    // Add base64 data in chunks of 64 characters
    for (int i = 0; i < base64Data.length; i += 64) {
      pemLines.add(base64Data.substring(
          i, i + 64 < base64Data.length ? i + 64 : base64Data.length));
    }
    pemLines.add('-----END CERTIFICATE-----');

    return pemLines.join('\n');
  }

  /// Convert certificate data to hex string format
  static String toHexString(List<int> certificateData) {
    return certificateData
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Convert hex string to binary data
  static List<int> fromHexString(String hexString) {
    final buffer = <int>[];
    for (int i = 0; i < hexString.length; i += 2) {
      buffer.add(int.parse(hexString.substring(i, i + 2), radix: 16));
    }
    return buffer;
  }

  /// Export certificate to a file and share in Documents folder instead of temp
  static Future<void> shareAsPEM(
      List<int> certificateData, String fileName) async {
    final pemString = toPEM(certificateData);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.pem');
    await file.writeAsString(pemString);
    await Share.shareXFiles([XFile(file.path)], text: 'Certificate Export');
  }

  /// Export certificate as DER (binary) file and share in Documents folder instead of temp
  static Future<void> shareAsDER(
      List<int> certificateData, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.der');
    await file.writeAsBytes(Uint8List.fromList(certificateData));
    await Share.shareXFiles([XFile(file.path)], text: 'Certificate Export');
  }

  /// Export certificate as hex text file in Documents folder instead of temp
  static Future<void> shareAsHex(
      List<int> certificateData, String fileName) async {
    final hexString = toHexString(certificateData);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName.txt');
    await file.writeAsString(hexString);
    await Share.shareXFiles([XFile(file.path)], text: 'Certificate Export');
  }

  /// Show export options dialog
  static Future<void> showExportDialog(BuildContext context,
      List<int> certificateData, String defaultFileName) async {
    if (certificateData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No certificate data available to export')));
      return;
    }

    // Replace direct request with our helper
    final granted = await _ensureStoragePermission();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Storage permission is required for export')));
      return;
    }

    final fileName = defaultFileName.isEmpty
        ? 'certificate_${DateTime.now().millisecondsSinceEpoch}'
        : defaultFileName;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Certificate'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              shareAsPEM(certificateData, fileName);
            },
            child: const Text('PEM Format (.pem)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              shareAsDER(certificateData, fileName);
            },
            child: const Text('DER Format (.der)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              shareAsHex(certificateData, fileName);
            },
            child: const Text('HEX Text (.txt)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  /// Helper method to ensure storage permission
  static Future<bool> _ensureStoragePermission() async {
    if (Platform.isAndroid) {
      final sdkInt = (await Process.run('getprop', ['ro.build.version.sdk']))
          .stdout
          .toString()
          .trim();
      final sdkVersion = int.tryParse(sdkInt) ?? 0;

      if (sdkVersion >= 30) {
        // For Android 11+ manage external storage
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      } else {
        // For older Android
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    // For iOS or other platforms, no extra steps
    return true;
  }
}
