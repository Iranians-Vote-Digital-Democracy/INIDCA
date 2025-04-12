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

// ignore_for_file: constant_identifier_names

import 'dart:developer' as developer; // Added for logging

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

// APDU constants - EXACTLY matching the MAV4_General_1::ReadSign_Certificate
const String APDU_1 =
    "00A4040008A000000018434D00"; // SELECT AID A000000018434D00
const String APDU_2 = "80CA9F7F2D"; // READ CPLC info
const String APDU_3 =
    "00A404000CA0000000180C000001634200"; // SELECT AID A0000000180C000001634200
const String APDU_4 = "00A40000023F00"; // SELECT MF
const String APDU_5 = "00A40000025100"; // SELECT DF 51
const String APDU_6 = "00A4020C025040"; // SELECT EF 5040
const String APDU_7 = "00A4000C023F00"; // A4 3F00 with P1=0C
const String APDU_8 = "00A4000C025100"; // A4 5100 with P1=0C
const String APDU_9 = "00A4020C025040"; // A4 5040 with P1=02, P2=0C

// Helper: convert hex string (e.g. "00A4040008...") to byte list
List<int> hexStringToBytes(String hexString) {
  List<int> result = [];
  for (int i = 0; i < hexString.length; i += 2) {
    result.add(int.parse(hexString.substring(i, i + 2), radix: 16));
  }
  return result;
}

// Enhanced APDU response parsing with comprehensive status word handling
Map<String, String> enhancedParseApduResponse(String response) {
  if (response.length < 4) {
    return {
      'sw': 'N/A',
      'data': response,
      'success': 'false',
      'warning': 'false',
      'swDescription': 'Invalid response length', // Added description
    };
  }

  String sw = response.substring(response.length - 4);
  String data =
      response.length > 4 ? response.substring(0, response.length - 4) : '';
  bool success = false;
  bool warning = false;

  // Detailed status word interpretation
  String swDescription = 'Unknown';

  // Success cases
  if (sw == '9000') {
    swDescription = 'Success - Normal processing';
    success = true;
  }
  // Warning cases
  else if (sw.startsWith('62')) {
    success = true; // Treat warnings as success in terms of data retrieval
    warning = true;
    if (sw == '6200') {
      swDescription = 'Warning - No information given';
    } else if (sw == '6281') {
      swDescription = 'Warning - Part of returned data may be corrupted';
    } else if (sw == '6282') {
      swDescription =
          'Warning - End of file/record reached before end of reading';
    } else if (sw == '6283') {
      swDescription = 'Warning - Selected file deactivated';
    } else if (sw == '6284') {
      swDescription =
          'Warning - File control information not correctly formatted';
    } else if (sw == '6285') {
      swDescription = 'Warning - Selected file in termination state';
    } else if (sw == '6286') {
      swDescription = 'Warning - No input data available from a sensor';
    } else {
      swDescription = 'Warning - State of non-volatile memory unchanged';
    }
  } else if (sw.startsWith('63')) {
    success = true; // Treat warnings as success
    warning = true;
    if (sw.startsWith('63C')) {
      int counter =
          int.tryParse(sw.substring(3, 4), radix: 16) ?? 0; // Fixed parsing
      swDescription = 'Warning - Counter value: $counter';
    } else {
      swDescription = 'Warning - State of non-volatile memory changed';
    }
  }
  // More data available
  else if (sw.startsWith('61')) {
    success = true; // Still a success, just need GET RESPONSE
    int bytesRemaining = int.tryParse(sw.substring(2, 4), radix: 16) ?? 0;
    swDescription = 'More data available: $bytesRemaining bytes';
  }
  // Incorrect parameters
  else if (sw.startsWith('6A')) {
    if (sw == '6A80') {
      swDescription = 'Error - Incorrect parameters in the data field';
    } else if (sw == '6A81') {
      swDescription = 'Error - Function not supported';
    } else if (sw == '6A82') {
      swDescription = 'Error - File or application not found';
    } else if (sw == '6A83') {
      swDescription = 'Error - Record not found';
    } else if (sw == '6A84') {
      swDescription = 'Error - Not enough memory space';
    } else if (sw == '6A85') {
      swDescription = 'Error - Nc inconsistent with TLV structure';
    } else if (sw == '6A86') {
      swDescription = 'Error - Incorrect parameters P1-P2';
    } else if (sw == '6A87') {
      swDescription = 'Error - Nc inconsistent with parameters P1-P2';
    } else if (sw == '6A88') {
      swDescription = 'Error - Referenced data or reference data not found';
    } else {
      swDescription = 'Error - Wrong parameter';
    }
  }
  // Incorrect length
  else if (sw.startsWith('6C')) {
    int expectedLength = int.tryParse(sw.substring(2, 4), radix: 16) ?? 0;
    swDescription = 'Wrong length (expected length: $expectedLength)';
  }
  // Command not supported
  else if (sw.startsWith('6D')) {
    swDescription = 'Instruction not supported';
  }
  // Class not supported
  else if (sw.startsWith('6E')) {
    swDescription = 'Class not supported';
  }
  // Security-related errors
  else if (sw.startsWith('69')) {
    if (sw == '6982') {
      swDescription = 'Error - Security status not satisfied';
    } else if (sw == '6983') {
      swDescription = 'Error - Authentication method blocked';
    } else if (sw == '6984') {
      swDescription = 'Error - Referenced data invalidated';
    } else if (sw == '6985') {
      swDescription = 'Error - Conditions of use not satisfied';
    } else if (sw == '6986') {
      swDescription = 'Error - Command not allowed';
    } else if (sw == '6987') {
      swDescription = 'Error - Expected secure messaging data objects missing';
    } else if (sw == '6988') {
      swDescription = 'Error - Incorrect secure messaging data objects';
    } else {
      swDescription = 'Error - Command not allowed - General';
    }
  }
  // Other common errors
  else if (sw == '6700') {
    swDescription = 'Wrong length';
  } else if (sw == '6B00') {
    swDescription = 'Wrong parameter(s) P1-P2';
  } else if (sw == '6F00') {
    swDescription = 'Unknown error';
  }

  return {
    'sw': sw,
    'swDescription': swDescription,
    'data': data,
    'success': success.toString(),
    'warning': warning.toString(),
  };
}

// Transmit an APDU command and return the parsed result map
Future<Map<String, String>> transmitAPDU(String apduHex) async {
  try {
    // Validate APDU format before sending
    if (apduHex.isEmpty ||
        apduHex.length % 2 != 0 ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(apduHex)) {
      developer.log("Invalid APDU format: $apduHex", name: 'APDU_ERROR');
      return {
        'sw': '0000',
        'data': '',
        'success': 'false',
        'warning': 'false',
        'swDescription': 'Invalid APDU format provided',
      };
    }

    String responseHex;
    try {
      responseHex = await FlutterNfcKit.transceive(apduHex);
    } catch (e) {
      // Handle TagLostException and other communication errors
      if (e.toString().contains("TagLostException") ||
          e.toString().contains("Communication error")) {
        developer.log("Tag Lost or Communication Error during transceive",
            name: 'APDU_ERROR');
        // For communication errors, allow the caller to handle the reconnection
        throw Exception("TagLost"); // Rethrow specific exception
      }
      developer.log("Transceive error: $e", name: 'APDU_ERROR');
      return {
        'sw': '0000',
        'data': '',
        'success': 'false',
        'warning': 'false',
        'swDescription': 'Transceive failed: $e',
      };
    }

    // Handle empty response
    if (responseHex.isEmpty) {
      developer.log("Empty response received for APDU: $apduHex",
          name: 'APDU_WARN');
      return {
        'sw': '0000',
        'data': '',
        'success': 'false',
        'warning': 'true',
        'swDescription': 'Empty response received',
      };
    }

    // Parse the response using the enhanced parser
    return enhancedParseApduResponse(responseHex);
  } catch (e) {
    if (e.toString().contains("TagLost")) {
      rethrow; // Let the caller handle this specific error
    }
    developer.log("Unexpected error in transmitAPDU: $e", name: 'APDU_ERROR');
    return {
      'sw': '0000',
      'data': '',
      'success': 'false',
      'warning': 'false',
      'swDescription': 'Unexpected error: $e',
    };
  }
}

// Build a READ BINARY command given offset and length - ensuring proper hex format
String formatReadBinaryCommand(int offset, int length) {
  // Format each part of the APDU command with proper hex representation
  String p1 = ((offset >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
  String p2 = (offset & 0xFF).toRadixString(16).padLeft(2, '0');

  // Ensure length is properly formatted with 2 hex digits
  // For compatibility with flutter_nfc_kit, use Le=0 to request all available bytes
  // instead of a specific length when reading binary data
  String le = "00"; // Request maximum available data

  return "00B0$p1$p2$le";
}

// Read a binary chunk using the refactored transmitAPDU
Future<Map<String, String>> readBinaryChunk(int offset, int length) async {
  try {
    // Use a fixed chunkSize that's compatible with your card and the NFC plugin
    const int safeChunkSize = 0xF8; // Adjusted chunk size
    int adjustedLength = length > safeChunkSize ? safeChunkSize : length;
    if (adjustedLength == 0) {
      adjustedLength = safeChunkSize; // Default to safe chunk size if 0
    }

    // Construct a properly formatted READ BINARY command
    String cmd = formatReadBinaryCommand(offset, adjustedLength);

    // Check the APDU command format to ensure it's valid
    if (cmd.length % 2 != 0 || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(cmd)) {
      developer.log("Invalid READ BINARY command format: $cmd",
          name: 'APDU_ERROR');
      return {
        'sw': '0000',
        'data': '',
        'success': 'false',
        'warning': 'false',
        'swDescription': 'Invalid command format',
      };
    }

    Map<String, String> result = await transmitAPDU(cmd);

    // Check status words like C++ implementation
    if (result['success'] == 'true') {
      return result; // Return the full map
    } else if (result['sw']?.startsWith('6C') ?? false) {
      // Wrong length - the card is telling us the correct length
      int correctLength =
          int.tryParse(result['sw']!.substring(2, 4), radix: 16) ?? 0;
      if (correctLength > 0) {
        // Try again with the correct length
        String p1 = ((offset >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
        String p2 = (offset & 0xFF).toRadixString(16).padLeft(2, '0');
        String retryCmd =
            "00B0$p1$p2${correctLength.toRadixString(16).padLeft(2, '0')}";
        developer.log("Retrying READ BINARY with length $correctLength",
            name: 'APDU_INFO');
        Map<String, String> retryResult = await transmitAPDU(retryCmd);
        return retryResult; // Return the result of the retry
      }
    }

    // Any other status is an error, return the original result map
    return result;
  } catch (e) {
    developer.log("Error in readBinaryChunk: $e", name: 'APDU_ERROR');
    if (e.toString().contains("TagLost")) {
      rethrow; // Rethrow TagLost for session handling
    }
    return {
      'sw': '0000',
      'data': '',
      'success': 'false',
      'warning': 'false',
      'swDescription': 'Exception: $e',
    };
  }
}
