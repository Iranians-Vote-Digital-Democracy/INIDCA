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
import 'dart:io'; // Required for File operations
import 'dart:math';
import 'dart:typed_data'; // Required for Uint8List

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart'; // Required for temp directory
import 'package:share_plus/share_plus.dart'; // Required for sharing

class CertificateUtils {
  // Create a secure storage instance
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Constants for storing certificates
  static const String _certListKey = 'certificate_list';
  static const String _certPrefix = 'cert_';

  /// Formats and outputs a certificate to the debug console in a hex dump format
  static void outputCertificateToDebugConsole(List<int> certificateData) {
    // Convert bytes to hex string
    String hexString = certificateData
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    debugPrint("\n==================================================");
    debugPrint("CERTIFICATE DATA - ${certificateData.length} bytes");
    debugPrint("==================================================");

    // Output as hex dump with offset indicators (16 bytes per line)
    for (int i = 0; i < certificateData.length; i += 16) {
      // Calculate the offset for this line
      StringBuffer line = StringBuffer();
      line.write("${i.toRadixString(16).padLeft(4, '0')}: ");

      // Add hex values
      StringBuffer hexPart = StringBuffer();
      StringBuffer asciiPart = StringBuffer();

      for (int j = i; j < i + 16 && j < certificateData.length; j++) {
        int byteValue = certificateData[j];
        // Add the hex representation
        hexPart.write("${byteValue.toRadixString(16).padLeft(2, '0')} ");

        // Add the ASCII representation
        if (byteValue >= 32 && byteValue <= 126) {
          asciiPart.write(String.fromCharCode(byteValue));
        } else {
          asciiPart.write(".");
        }
      }

      // Output the formatted line with both hex and ASCII
      debugPrint(
        "${line.toString()}${hexPart.toString().padRight(48)} | ${asciiPart.toString()}",
      );
    }

    // Also output as a single hex string for easy copying
    debugPrint("\n// RAW CERTIFICATE DATA (HEX STRING):");
    debugPrint(hexString);

    // Output in byte array format for easy copying to C/C++ code
    debugPrint("\n// CERTIFICATE DATA AS BYTE ARRAY:");
    StringBuffer byteArray = StringBuffer("byte[] certificateBytes = {");
    for (int i = 0; i < certificateData.length; i++) {
      if (i > 0) byteArray.write(", ");
      if (i % 16 == 0) byteArray.write("\n  ");
      byteArray.write(
        "0x${certificateData[i].toRadixString(16).padLeft(2, '0')}",
      );
    }
    byteArray.write("\n};");
    debugPrint(byteArray.toString());

    debugPrint("==================================================\n");
  }

  /// Saves certificate data to a temporary file for sharing.
  /// Returns the path to the temporary file.
  static Future<String> saveCertificateToTempFileForSharing(
      Uint8List certificateData, String fileName) async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/$fileName';
      final File file = File(filePath);

      // Write the byte data to the file
      await file.writeAsBytes(certificateData);

      debugPrint('Certificate saved temporarily for sharing at: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error saving certificate to temporary file: $e');
      throw Exception('Error saving certificate for sharing: $e'); // Re-throw
    }
  }

  /// Shares a certificate file using the share_plus package.
  static Future<void> shareCertificateFile(String filePath,
      {BuildContext? context}) async {
    try {
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Certificate File',
        subject: 'Certificate Export', // Optional: Email subject
      );

      if (context != null && context.mounted) {
        // Check context and mounted state
        if (result.status == ShareResultStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Certificate shared successfully.")),
          );
        } else if (result.status == ShareResultStatus.dismissed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Sharing dismissed.")),
          );
        }
      }
      debugPrint('Share result: ${result.status}');
    } catch (e) {
      debugPrint('Error sharing certificate file: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sharing file: $e")),
        );
      }
    }
  }

  // DEPRECATED: Use saveCertificateToTempFileForSharing and shareCertificateFile instead
  @Deprecated(
      'Use saveCertificateToTempFileForSharing and shareCertificateFile instead')
  static Future<String> saveCertificateToFile(
      Uint8List certificateData, String fileName, // Changed to Uint8List
      {BuildContext? context}) async {
    try {
      // Securely store the certificate
      String certId = await securelySaveCertificate(certificateData);

      // Return the secure storage ID (no file path involved here anymore)
      return "Certificate stored securely with ID: $certId";
    } catch (e) {
      debugPrint('Error saving certificate securely: $e');
      return 'Error saving certificate securely: $e';
    }
  }

  /// Secure storage without creating a file copy
  static Future<String> securelySaveCertificate(
      Uint8List certificateData) async {
    // Changed to Uint8List
    try {
      // Generate a unique ID for this certificate
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      // Ensure certId is unique and valid for storage key
      String randomSuffix = Random().nextInt(9999).toString().padLeft(4, '0');
      String certId = '$_certPrefix${timestamp}_$randomSuffix';

      // Convert the binary data to a Base64 string for storage
      String base64Data = base64Encode(certificateData);

      // Store certificate in secure storage
      await _secureStorage.write(key: certId, value: base64Data);

      // Keep track of all certificates by ID
      String? existingList = await _secureStorage.read(key: _certListKey);
      List<String> certIds = [];

      // Handle null or empty existingList safely
      if (existingList != null && existingList.isNotEmpty) {
        certIds = existingList.split(',');
      }

      if (!certIds.contains(certId)) {
        certIds.add(certId);
      }

      // Update the list of certificates
      await _secureStorage.write(key: _certListKey, value: certIds.join(','));

      debugPrint('Certificate securely saved with ID: $certId');
      return certId;
    } catch (e) {
      debugPrint('Error in secure certificate storage: $e');
      // Rethrow or return a specific error indicator
      throw Exception('Secure storage failed: $e');
    }
  }

  /// Converts certificate data (Uint8List) to a hex string.
  static String toHexString(Uint8List certificateData) {
    // Changed to Uint8List
    return certificateData
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Adds the complete certificate to the log in a formatted way.
  static void addFullCertificateToLog(
    String hexData, {
    required void Function(String message, {bool highlight})
        addToLog, // Changed to required named parameter
  }) {
    // Format certificate data in lines of 32 hex digits (16 bytes) with offset
    for (int i = 0; i < hexData.length; i += 32) {
      int offset = i ~/ 2; // byte offset
      StringBuffer line = StringBuffer();
      line.write("${offset.toRadixString(16).padLeft(4, '0')}: ");

      // Add hex values
      int end = min(i + 32, hexData.length);
      for (int j = i; j < end; j += 2) {
        // Ensure we don't go out of bounds if hexData length is odd (shouldn't happen)
        if (j + 1 < hexData.length) {
          line.write("${hexData.substring(j, j + 2)} ");
        } else {
          line.write(
              "${hexData.substring(j, j + 1)} "); // Handle potential odd length
        }
      }

      addToLog(line.toString(),
          highlight: false); // Call with highlight parameter
    }
  }

  /// Saves certificate data securely. Replaces the old method.
  static Future<String> saveCertificateAsBinary(
    Uint8List certificateData, // Changed to Uint8List
  ) async {
    try {
      // Use only secure storage
      return await securelySaveCertificate(certificateData);
    } catch (e) {
      debugPrint('Error in secure certificate storage: $e');
      // Propagate the error message
      return 'Error saving certificate: $e';
    }
  }

  /// Retrieve a certificate from secure storage by ID
  static Future<Uint8List?> retrieveCertificateById(String certId) async {
    // Return Uint8List
    try {
      String? base64Data = await _secureStorage.read(key: certId);
      if (base64Data == null || base64Data.isEmpty) {
        debugPrint('No certificate found for ID: $certId');
        return null;
      }
      return base64Decode(base64Data); // Returns Uint8List
    } catch (e) {
      debugPrint('Error retrieving certificate $certId: $e');
      return null;
    }
  }

  /// Get a list of all stored certificate IDs
  static Future<List<String>> getStoredCertificateIds() async {
    try {
      String? list = await _secureStorage.read(key: _certListKey);
      // Handle null or empty list safely
      if (list == null || list.isEmpty) return [];
      return list.split(',');
    } catch (e) {
      debugPrint('Error getting certificate list: $e');
      return [];
    }
  }

  /// Delete a certificate from secure storage
  static Future<bool> deleteCertificate(String certId) async {
    try {
      await _secureStorage.delete(key: certId);

      // Update the list
      String? existingList = await _secureStorage.read(key: _certListKey);
      // Handle null or empty list safely
      if (existingList != null && existingList.isNotEmpty) {
        List<String> certIds = existingList.split(',');
        certIds.remove(certId);
        await _secureStorage.write(key: _certListKey, value: certIds.join(','));
      }

      debugPrint('Deleted certificate with ID: $certId');
      return true;
    } catch (e) {
      debugPrint('Error deleting certificate $certId: $e');
      return false;
    }
  }

  // Moved from apdu_commands.dart - accepts Uint8List
  static Map<String, dynamic> parseCertUtilsStyle(Uint8List certificateData) {
    // Changed to Uint8List
    if (certificateData.length < 2 || certificateData.isEmpty) {
      return {
        'valid': false,
        'parsed': false,
        'error': 'Invalid certificate data - insufficient length',
      };
    }

    try {
      // Check for DER SEQUENCE tag (0x30) at start
      if (certificateData[0] != 0x30) {
        return {
          'valid': false,
          'parsed': false,
          'error':
              'Invalid certificate data: Does not start with DER SEQUENCE tag',
        };
      }

      // Return only validation status - no dummy data
      return {
        'valid': true,
        'parsed': false, // Indicate parsing wasn't fully done here
        'certificate': certificateData, // Keep raw data if needed
      };
    } catch (e) {
      return {
        'valid': false,
        'parsed': false,
        'error': 'Exception during parsing: $e',
      };
    }
  }

  // Helper to convert hex string to Uint8List
  static Uint8List hexStringToBytes(String hex) {
    hex = hex.replaceAll(" ", ""); // Remove spaces
    if (hex.length % 2 != 0) {
      hex = '0$hex'; // Pad if odd length
    }
    List<int> list = [];
    for (int i = 0; i < hex.length; i += 2) {
      list.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(list);
  }
}
