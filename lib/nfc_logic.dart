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

import 'package:flutter/foundation.dart';
import 'package:inid_assistant/apdu_commands.dart' as apdu;

// APDU commands for X509 certificate retrieval - fixed formats based on error logs
const Map<String, String> x509Commands = {
  // Commands formatted to exactly match the C++ byte arrays with proper hex format
  'SELECT_IAS_APP': '00A404000CA000000018C0000001634200',
  'SELECT_CARD_MANAGER': '00A4040008A000000018434D00',
  'READ_CPLC': '80CA9F7F2D',
  'SELECT_MASTER_FILE': '00A40000023F00',
  'SELECT_DF_50': '00A40000025000', // Corrected
  'SELECT_EF_5040': '00A4020C025040',
  'SELECT_MASTER_FILE_P2': '00A4000C023F00',
  'SELECT_DF_50_P2': '00A4000C025000',
  'SELECT_EF_0303': '00A4020C020303',
};

// Additional file selection commands to try
const List<Map<String, String>> additionalFileSelections = [
  {'name': 'SELECT_EF_DIR', 'command': '00A4020C022F00'}, // Try EF.DIR
  {'name': 'SELECT_EF_DDF', 'command': '00A4040C00'}, // Try default DDF
  {
    'name': 'SELECT_CERTIFICATE_FILE',
    'command': '00A4020C020100',
  }, // Common certificate file
  {
    'name': 'SELECT_BY_AID',
    'command': '00A40400',
  }, // Will build AID dynamically
  {'name': 'READ_BINARY_1', 'command': '00B0000004'}, // Try reading binary
  {'name': 'GET_DATA', 'command': '00CA010000'}, // Try to get data
  {'name': 'GET_CERTIFICATE', 'command': '00CB3FFF04'}, // Try tag 3F FF
];

// Commands for reading Card Serial Number (CSN) and Card Reference Number (CRN)
const Map<String, String> csnCrnCommands = {
  'SELECT_CARD_MANAGER': '00A4040008A000000018434D00',
  'GET_CPLC': '80CA9F7F2D',
  'GET_TAG_0101': '80CA010115',
  'SELECT_APP': '00A4040008A00000000300000000', // APDU_SELECT from pardis
  'GET_CPLC_1': '80CA9F7F00', // From pardis_read_csn_crn
  'GET_CPLC_2': '00C000002D', // From pardis_read_csn_crn
  'GET_CSN': '9038000C', // From pardis_read_csn_crn
  // OMID style commands
  'SELECT_CARD_MANAGER_OMID': '00A4040008A00000000018434D00',
  'GET_NONCE': '00840000010',
  'CID_CMD_1': '0088010000',
  'CID_CMD_2': '00C0000020',
};

// SOD1 commands from mav4_sod1.cpp for reading SOD
const Map<String, String> sod1Commands = {
  'SELECT_APPLET': '00A404001000A0000000183003010000000000000000',
  'SELECT_MF': '00A40000023F00',
  'SELECT_DF': '00A40100020200',
  'SELECT_EF': '00A40200020205',
  'READ_BINARY': '00B0000000', // P1P2=0000, Le=0 (will be updated)
  'SELECT_CARD_MANAGER': '00A4040008A000000018434D00',
  'GET_CPLC': '80CA9F7F2D',
  'GET_TAG0101': '80CA010115',
  // Alternative commands to try
  'SELECT_CARD_MANAGER_ALT': '00A4040008A000000018434D00',
  'GET_CPLC_COMMAND': '80CA9F7F2D',
  'GET_TAG0101_COMMAND': '80CA010115',
};

// Additional signing certificate commands - including alternatives
const Map<String, String> signingCertCommands = {
  // MAV4 commands from mav4_sign_cert.cpp
  'SELECT_CARD_MANAGER': '00A4040008A000000018434D00',
  'GET_CPLC': '80CA9F7F2D',
  'SELECT_AID': '00A404000CA0000000180C000001634200',
  'SELECT_MF': '00A40000023F00',
  'SELECT_DF_51': '00A40000025100',
  'SELECT_EF_5040': '00A4020C025040',
  'SELECT_MF_P2': '00A4000C023F00',
  'SELECT_DF_51_P2': '00A4000C025100',
  'SELECT_EF_5040_P2': '00A4020C025040',
};

// Commands for reading signing certificate from Pardis cards
const Map<String, String> pardisSigningCertCommands = {
  'SELECT_APP':
      '00A404000F5041524449532C4D41544952414E20', // Updated to match C++ reference
  'SELECT_MF': '00A40000023F00', // SELECT MF
  'SELECT_DF': '00A40000025100', // SELECT DF 5100
  'SELECT_EF': '00A40200025040', // SELECT EF 5040 (P1=02, P2=00)
};

// Commands for reading card dates from MAV4_ReadDates
const Map<String, String> dateCommands = {
  'SELECT_AID': '00A404000A', // AID will be added separately
  'SELECT_MF': '00A40000023F00',
  'SELECT_DF': '00A40100020300',
  'SELECT_EF': '00A40200020303',
};

// Commands for AFIS check
const Map<String, String> afisCheckCommands = {
  'SELECT_ISO7816': '00A40400080A00000018300301',
  'SELECT_MF': '00A40000023F00',
  'SELECT_EF_DIR': '00A40100020300',
  'SELECT_EF_CSN': '00A40200020302',
};

// --- New Command Map for MAV4 Authentication Certificate ---
const Map<String, String> mavAuthCertCommands = {
  'SELECT_IAS_APP_1': apdu.MAV_AUTH_SELECT_IAS_APP,
  'SELECT_CARD_MANAGER': apdu.MAV_AUTH_SELECT_CM,
  'READ_CPLC': apdu.MAV_AUTH_READ_CPLC,
  'SELECT_IAS_APP_2': apdu.MAV_AUTH_SELECT_IAS_APP, // Select again
  'SELECT_MF': apdu.MAV_AUTH_SELECT_MF,
  'SELECT_DF_5000': apdu.MAV_AUTH_SELECT_DF_5000,
  'SELECT_EF_5040': apdu.MAV_AUTH_SELECT_EF_5040,
  'SELECT_MF_P2': apdu.MAV_AUTH_SELECT_MF_P2,
  'SELECT_DF_5000_P2': apdu.MAV_AUTH_SELECT_DF_5000_P2,
  'SELECT_EF_5040_P2': apdu.MAV_AUTH_SELECT_EF_5040_P2,
  'SELECT_EF_0303': apdu.MAV_AUTH_SELECT_EF_0303,
};

// Helper class to format READ BINARY commands with offset
String formatReadBinaryCommand(int offset, int length) {
  String p1Hex = ((offset >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
  String p2Hex = (offset & 0xFF).toRadixString(16).padLeft(2, '0');
  String lengthHex = length.toRadixString(16).padLeft(2, '0');
  return '00B0$p1Hex$p2Hex$lengthHex';
}

// This is just an example, the actual implementation will be in your NFC reading logic

void logCertificateData(
  String cardId,
  int size,
  String format,
  String rawData,
) {
  // Format the log message
  String logMessage = """
[NFC_CERTIFICATE_DATA] =================================================
                       DATA EXTRACTION REPORT - CARD MANAGER DATA
                       =================================================
                       ⏱️ Time: ${DateTime.now()}
                       🆔 Card ID: $cardId
                       📊 Size: $size bytes
                       📝 Format: $format
                       📋 Raw Hex Data:
                       $rawData
                       =================================================""";

  // Log the message to the console
  print(logMessage);

  // Print the raw data to the debug console
  debugPrint('Raw Certificate Data (Hex): $rawData');
}
