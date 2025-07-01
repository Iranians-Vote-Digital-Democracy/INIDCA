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

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:inid_assistant/apdu_commands.dart' as apdu;
import 'package:inid_assistant/data_processing.dart';
import 'package:inid_assistant/logging.dart';
import 'package:inid_assistant/nfc_logic.dart'; // Ensure this import includes mavAuthCertCommands
import 'package:inid_assistant/nfc_utils.dart';

class SmartCardOperations {
  final AppLogger logger;
  final Function(String) updateLastCardId;
  final Function(bool) setProcessing;

  SmartCardOperations({
    required this.logger,
    required this.updateLastCardId,
    required this.setProcessing,
  });

  Future<T?> _executeNfcOperation<T>(
    String operationName,
    Future<T> Function() operation, {
    String iosAlertMessage = "Hold your iPhone near the card",
    String successMessage = "Operation successful",
    String failureMessage = "Operation failed",
  }) async {
    setProcessing(true);
    logger.log("Starting NFC operation: $operationName...", highlight: true);

    NFCTag? tag;
    try {
      logger.log("Polling for NFC tag...");
      tag = await NfcUtils.pollForTag(
        iosAlertMessage: iosAlertMessage,
      );

      updateLastCardId(tag.id);
      logger.log("✅ Tag detected: ${tag.id}");
      logger.log("Standard: ${tag.standard}");
      logger.log("Type: ${tag.type}");

      T result = await operation();

      await FlutterNfcKit.finish(iosAlertMessage: successMessage);
      logger.log("✅ NFC session completed for $operationName");
      return result;
    } on Exception catch (e) {
      if (e.toString().contains("TagLost")) {
        logger.log("❌ Tag Lost during $operationName", highlight: true);
      } else {
        logger.log("❌ Error during $operationName: $e", highlight: true);
        try {
          await FlutterNfcKit.finish(iosErrorMessage: "$failureMessage: $e");
        } catch (finishError) {
          logger.log("Error finishing NFC session after error: $finishError");
        }
      }
      return null;
    } finally {
      setProcessing(false);
    }
  }

  Future<String> _readDataWithContinuation(
    int initialOffset,
    int initialChunkSize, {
    int maxAttempts = 20,
  }) async {
    String fullData = "";
    int currentOffset = initialOffset;
    int attempts = 0;
    bool firstRead = true;

    while (attempts < maxAttempts) {
      attempts++;
      int chunkSize = initialChunkSize;

      logger.log(
        "Reading chunk at offset 0x${currentOffset.toRadixString(16)} (Attempt $attempts)...",
      );

      Map<String, String> result =
          await apdu.readBinaryChunk(currentOffset, chunkSize);
      String sw = result['sw'] ?? '0000';
      String data = result['data'] ?? '';
      String swDesc = result['swDescription'] ?? 'N/A';
      bool success = result['success'] == 'true';

      logger
          .log("Read Response: SW=$sw ($swDesc), Data Len=${data.length ~/ 2}");

      if (success) {
        if (data.isNotEmpty) {
          fullData += data;
          currentOffset += data.length ~/ 2;
          firstRead = false;

          if (data.length / 2 < chunkSize && !sw.startsWith('61')) {
            logger.log(
                "Received less data than requested, assuming end of file.");
            break;
          }
        } else if (firstRead) {
          logger.log("Read successful but returned no data on first attempt.");
          break;
        } else {
          logger.log(
              "Read successful but returned no data, assuming end of file.");
          break;
        }

        if (sw.startsWith('61')) {
          int bytesRemaining = int.tryParse(sw.substring(2, 4), radix: 16) ?? 0;
          if (bytesRemaining > 0) {
            String getResponseCmd =
                '00C00000${bytesRemaining.toRadixString(16).padLeft(2, '0')}';
            logger.log("Sending GET RESPONSE: $getResponseCmd");
            Map<String, String> getRespResult =
                await apdu.transmitAPDU(getResponseCmd);
            String getRespSw = getRespResult['sw'] ?? '0000';
            String getRespData = getRespResult['data'] ?? '';
            logger.log(
                "GET RESPONSE Result: SW=$getRespSw, Data Len=${getRespData.length ~/ 2}");

            if (getRespResult['success'] == 'true' && getRespData.isNotEmpty) {
              fullData += getRespData;
              currentOffset += getRespData.length ~/ 2;
            } else {
              logger.log(
                  "GET RESPONSE failed or returned no data (SW=$getRespSw). Stopping read.");
              break;
            }
          } else {
            logger.log("SW=6100 received, stopping read.");
            break;
          }
        }
      } else if (sw == '6B00') {
        logger.log("Reached end of file (6B00).");
        break;
      } else if (sw == '6A82' || sw == '6A83') {
        logger.log("File or record not found ($sw). Stopping read.");
        break;
      } else if (sw.startsWith('6C')) {
        logger.log(
            "Wrong length ($sw) encountered, readBinaryChunk should have retried. Stopping.");
        break;
      } else {
        logger.log("❌ Error reading chunk: SW=$sw ($swDesc). Stopping read.");
        break;
      }
    }

    if (attempts >= maxAttempts) {
      logger.log("⚠️ Reached maximum read attempts ($maxAttempts).");
    }

    logger.log("Total data read: ${fullData.length ~/ 2} bytes");
    return fullData;
  }

  Future<bool> _selectFiles(Map<String, String> commands) async {
    logger.log("Selecting files...");
    for (var entry in commands.entries) {
      String commandName = entry.key;
      String commandHex = entry.value;

      logger.log("Sending $commandName: $commandHex");
      Map<String, String> result = await apdu.transmitAPDU(commandHex);
      logger.log(
        "$commandName response: SW=${result['sw']} (${result['swDescription']})",
      );

      if (result['success'] != 'true' && !result['sw']!.startsWith('61')) {
        if (!result['sw']!.startsWith('62') &&
            !result['sw']!.startsWith('63')) {
          logger.log(
              "❌ Critical error selecting file $commandName. Aborting selection.");
          return false;
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    logger.log("File selection complete.");
    return true;
  }

  Future<Map<String, String>?> executeCustomApdu(String command) async {
    return _executeNfcOperation<Map<String, String>>(
      "Execute Custom APDU",
      () async {
        logger.log("Sending custom command: $command");
        Map<String, String> result = await apdu.transmitAPDU(command);
        logger.log("Response received:");
        logger.log("  Status: ${result['sw']} (${result['swDescription']})");
        logger.log("  Data: ${result['data']}");
        return result;
      },
      successMessage: "Custom APDU executed",
      failureMessage: "Custom APDU failed",
    );
  }

  Future<Map<String, String>?> readCardManagerCertificate() async {
    return _executeNfcOperation<Map<String, String>>(
      "Read Card Manager Certificate",
      () async {
        logger.log("Selecting Card Manager application...");
        String selectCM = '00A4040008A000000018434D00';
        Map<String, String> selectResult = await apdu.transmitAPDU(selectCM);

        if (selectResult['success'] != 'true') {
          logger.log(
            "❌ Failed to select Card Manager: ${selectResult['sw']} (${selectResult['swDescription']})",
            highlight: true,
          );
          throw Exception(
            "Failed to select Card Manager: ${selectResult['swDescription']}",
          );
        }
        logger.log("✅ Card Manager selected successfully!");

        logger.log("Retrieving certificate with GET DATA command...");
        String certCmd = '00CA010100';
        Map<String, String> certResult = await apdu.transmitAPDU(certCmd);

        if (certResult['success'] != 'true' ||
            certResult['data'] == null ||
            certResult['data']!.isEmpty) {
          logger.log(
            "❌ Failed to retrieve certificate: ${certResult['sw']} (${certResult['swDescription']})",
            highlight: true,
          );
          throw Exception(
            "Failed to retrieve certificate: ${certResult['swDescription']}",
          );
        }

        logger.log("✅ Certificate retrieved successfully!", highlight: true);
        return certResult;
      },
      successMessage: "Certificate read successfully!",
      failureMessage: "Failed to read certificate",
    );
  }

  Future<Map<String, String>?> readCsnAndCrn() async {
    return _executeNfcOperation<Map<String, String>>(
      "Read CSN and CRN",
      () async {
        Map<String, String> result = {'csn': '', 'crn': ''};

        logger.log("Selecting Card Manager...");
        Map<String, String> selectResult =
            await apdu.transmitAPDU(csnCrnCommands['SELECT_CARD_MANAGER']!);
        if (selectResult['success'] != 'true') {
          throw Exception(
            "Failed to select Card Manager: ${selectResult['swDescription']}",
          );
        }

        logger.log("Reading CPLC data...");
        Map<String, String> cplcResult =
            await apdu.transmitAPDU(csnCrnCommands['GET_CPLC']!);
        if (cplcResult['success'] == 'true' && cplcResult['data']!.isNotEmpty) {
          result['csn'] =
              CardDataProcessor.extractCsnFromCplc(cplcResult['data']!);
          logger.log("CSN extracted from CPLC: ${result['csn']}");
        } else {
          logger.log(
            "⚠️ Failed to read CPLC data or data empty: ${cplcResult['sw']} (${cplcResult['swDescription']})",
          );
        }

        logger.log("Reading Tag 0101 data...");
        Map<String, String> tagResult =
            await apdu.transmitAPDU(csnCrnCommands['GET_TAG_0101']!);
        if (tagResult['success'] == 'true' && tagResult['data']!.isNotEmpty) {
          result['crn'] =
              CardDataProcessor.extractCrnFromTag0101(tagResult['data']!);
          logger.log("CRN extracted from Tag 0101: ${result['crn']}");
        } else {
          logger.log(
            "⚠️ Failed to read Tag 0101 data or data empty: ${tagResult['sw']} (${tagResult['swDescription']})",
          );
        }

        result['status'] =
            (result['csn']!.isNotEmpty || result['crn']!.isNotEmpty)
                ? 'Success'
                : 'Failed';
        return result;
      },
      successMessage: "CSN/CRN reading completed",
      failureMessage: "Error reading CSN/CRN",
    );
  }

  Future<Map<String, String>?> readCardDates() async {
    return _executeNfcOperation<Map<String, String>>(
      "Read Card Dates",
      () async {
        Map<String, String> dates = {
          'issueDate': '',
          'expiryDate': '',
          'returnCode': 'ff',
        };

        String aidString = "a0000000183003010000000000000000";
        String selectCmdBase = dateCommands['SELECT_AID']!;
        String selectCmd = selectCmdBase +
            (aidString.length ~/ 2).toRadixString(16).padLeft(2, '0') +
            aidString;

        logger.log("Selecting application with AID...");
        Map<String, String> res = await apdu.transmitAPDU(selectCmd);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT AID: ${res['swDescription']}");
        }

        logger.log("Selecting Master File (MF)...");
        res = await apdu.transmitAPDU(dateCommands['SELECT_MF']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT MF: ${res['swDescription']}");
        }

        logger.log("Selecting DF (0300)...");
        res = await apdu.transmitAPDU(dateCommands['SELECT_DF']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT DF: ${res['swDescription']}");
        }

        logger.log("Selecting EF (0303)...");
        res = await apdu.transmitAPDU(dateCommands['SELECT_EF']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT EF: ${res['swDescription']}");
        }

        logger.log("Reading date file data...");
        String cardData = await _readDataWithContinuation(0, 0xF8);

        if (cardData.isNotEmpty) {
          logger.log("Card data collected: ${cardData.length ~/ 2} bytes");
          Map<String, String> extractedDates =
              CardDataProcessor.extractDatesFromCardData(cardData);
          dates['issueDate'] = extractedDates['issueDate'] ?? '';
          dates['expiryDate'] = extractedDates['expiryDate'] ?? '';
          dates['returnCode'] = '00';
        } else {
          logger.log("⚠️ No data collected from date file.");
          dates['returnCode'] = '01';
        }

        return dates;
      },
      successMessage: "Date reading completed",
      failureMessage: "Error reading card dates",
    );
  }

  Future<String?> performAfisCheck() async {
    return _executeNfcOperation<String>(
      "Perform AFIS Check",
      () async {
        String afisCheckResult = "ERROR_UNKNOWN";

        logger.log("Selecting ISO7816 application...");
        Map<String, String> res =
            await apdu.transmitAPDU(afisCheckCommands['SELECT_ISO7816']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT ISO7816: ${res['swDescription']}");
        }

        logger.log("Selecting MF...");
        res = await apdu.transmitAPDU(afisCheckCommands['SELECT_MF']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT MF: ${res['swDescription']}");
        }

        logger.log("Selecting EF_DIR...");
        res = await apdu.transmitAPDU(afisCheckCommands['SELECT_EF_DIR']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT EF_DIR: ${res['swDescription']}");
        }

        logger.log("Selecting EF_CSN...");
        res = await apdu.transmitAPDU(afisCheckCommands['SELECT_EF_CSN']!);
        if (res['success'] != 'true') {
          throw Exception("Failed SELECT EF_CSN: ${res['swDescription']}");
        }

        logger.log("Reading AFIS check file data...");
        String cardData = await _readDataWithContinuation(0, 0xF8);

        if (cardData.isNotEmpty) {
          logger.log("Card data collected: ${cardData.length ~/ 2} bytes");
          afisCheckResult = CardDataProcessor.extractAfisCheckData(cardData);
          if (afisCheckResult.isEmpty) {
            afisCheckResult = "TAG_NOT_FOUND";
            logger.log("AFIS tag 'ad' not found in metadata");
          } else {
            logger.log("AFIS check data: $afisCheckResult");
          }
        } else {
          afisCheckResult = "NO_DATA_COLLECTED";
          logger.log("No data collected, cannot process metadata");
        }
        return afisCheckResult;
      },
      successMessage: "AFIS check completed",
      failureMessage: "Error performing AFIS check",
    );
  }

  Future<Map<String, dynamic>?> readSigningCertificate() async {
    return _executeNfcOperation<Map<String, dynamic>>(
      "Read Signing Certificate",
      () async {
        Map<String, dynamic> result = {
          'success': false,
          'certificateData': '',
          'size': 0,
        };

        logger.log("Pardis selection failed. Attempting file selection using MAV4/Generic commands...");
          // Ensure we re-select the MF in case the previous attempt left us elsewhere
        await _selectFiles({'SELECT_MF': signingCertCommands['SELECT_MF']!});
        bool selectionSuccess = await _selectFiles(signingCertCommands);

        // --- Proceed with Read if any selection succeeded ---
        if (!selectionSuccess) {
          logger.log(
              "⚠️ Both Pardis and MAV4/Generic file selections failed or encountered errors. Attempting read anyway...");
        } else {
          logger.log("✅ File selection successful.");
        }

        logger.log("Reading signing certificate data...");
        // Use a common, potentially larger chunk size for reading the certificate itself
        String fullData = await _readDataWithContinuation(
            0, 0xFF); // Increased chunk size for cert read

        if (fullData.isNotEmpty) {
          logger
              .log("Certificate data collected: ${fullData.length ~/ 2} bytes");
          result = {
            'success': true,
            'certificateData': fullData,
            'size': fullData.length ~/ 2,
          };

          // Log certificate details to debug console
          logger.log("Raw Certificate Hex: $fullData", highlight: true);
          // Consider adding CertificateUtils.outputCertificateToDebugConsole here if needed
          // CertificateUtils.outputCertificateToDebugConsole(CertificateUtils.hexStringToBytes(fullData));
        } else {
          logger.log(
            "❌ Failed to read signing certificate - no data returned after selection attempts.",
            highlight: true,
          );
        }
        return result;
      },
      successMessage: "Signing certificate reading completed",
      failureMessage: "Error reading signing certificate",
    );
  }

  Future<Map<String, dynamic>?> readPardisSigningCertificate() async {
    return _executeNfcOperation<Map<String, dynamic>>(
      "Read Signing Certificate",
          () async {
        Map<String, dynamic> result = {
          'success': false,
          'certificateData': '',
          'size': 0,
        };

        logger.log("Attempting file selection using Pardis commands...");

        bool selectionSuccess = await _selectFiles(pardisSigningCertCommands);

        // --- Proceed with Read if any selection succeeded ---
        if (!selectionSuccess) {
          logger.log(
              "⚠️ Both Pardis and MAV4/Generic file selections failed or encountered errors. Attempting read anyway...");
        } else {
          logger.log("✅ File selection successful.");
        }

        logger.log("Reading signing certificate data...");
        // Use a common, potentially larger chunk size for reading the certificate itself
        String fullData = await _readDataWithContinuation(
            0, 0xFF); // Increased chunk size for cert read

        if (fullData.isNotEmpty) {
          logger
              .log("Certificate data collected: ${fullData.length ~/ 2} bytes");
          result = {
            'success': true,
            'certificateData': fullData,
            'size': fullData.length ~/ 2,
          };

          // Log certificate details to debug console
          logger.log("Raw Certificate Hex: $fullData", highlight: true);
          // Consider adding CertificateUtils.outputCertificateToDebugConsole here if needed
          // CertificateUtils.outputCertificateToDebugConsole(CertificateUtils.hexStringToBytes(fullData));
        } else {
          logger.log(
            "❌ Failed to read signing certificate - no data returned after selection attempts.",
            highlight: true,
          );
        }
        return result;
      },
      successMessage: "Signing certificate reading completed",
      failureMessage: "Error reading signing certificate",
    );
  }

  Future<Map<String, dynamic>?> readAuthenticationCertificate() async {
    return _executeNfcOperation<Map<String, dynamic>>(
      "Read MAV4 Authentication Certificate",
      () async {
        Map<String, dynamic> result = {
          'success': false,
          'certificateData': '',
          'size': 0,
        };

        logger.log("Selecting files using MAV4 Auth sequence...");
        bool selectionSuccess = await _selectFiles(mavAuthCertCommands);

        if (!selectionSuccess) {
          logger.log("❌ MAV4 Auth file selection failed. Aborting read.",
              highlight: true);
          // Optionally throw an exception or return the failure result directly
          return result; // Indicate failure
        } else {
          logger.log("✅ MAV4 Auth file selection successful.");
        }

        logger.log("Reading MAV4 authentication certificate data...");
        // Use a suitable chunk size, 0xFF is often safe for certificates
        String fullData = await _readDataWithContinuation(0, 0xFF);

        if (fullData.isNotEmpty) {
          logger.log(
              "MAV4 Auth certificate data collected: ${fullData.length ~/ 2} bytes");
          result = {
            'success': true,
            'certificateData': fullData,
            'size': fullData.length ~/ 2,
          };
          logger.log("Raw MAV4 Auth Certificate Hex: $fullData",
              highlight: true);
        } else {
          logger.log(
            "❌ Failed to read MAV4 Auth certificate - no data returned after selection.",
            highlight: true,
          );
        }
        return result;
      },
      successMessage: "MAV4 Auth certificate reading completed",
      failureMessage: "Error reading MAV4 Auth certificate",
    );
  }

  Future<Map<String, dynamic>?> readSOD1() async {
    return _executeNfcOperation<Map<String, dynamic>>(
      "Read SOD1 Data",
      () async {
        Map<String, dynamic> result = {
          'success': false,
          'sodData': '',
          'size': 0
        };

        logger.log("Selecting files for SOD1...");
        try {
          logger.log("Selecting applet...");
          Map<String, String> res =
              await apdu.transmitAPDU(sod1Commands['SELECT_APPLET']!);
          logger.log("SELECT_APPLET: ${res['swDescription']}");

          if (res['success'] != 'true') {
            logger.log("Failed to select applet, trying Card Manager...");
            res = await apdu.transmitAPDU(sod1Commands['SELECT_CARD_MANAGER']!);
            logger.log("SELECT_CARD_MANAGER: ${res['swDescription']}");
            if (res['success'] != 'true') {
              throw Exception(
                  "Failed to select required application (Applet or CM)");
            }
          }

          logger.log("Selecting MF...");
          res = await apdu.transmitAPDU(sod1Commands['SELECT_MF']!);
          logger.log("SELECT_MF: ${res['swDescription']}");
          if (res['success'] != 'true') {
            throw Exception("Failed SELECT MF: ${res['swDescription']}");
          }

          logger.log("Selecting DF...");
          res = await apdu.transmitAPDU(sod1Commands['SELECT_DF']!);
          logger.log("SELECT_DF: ${res['swDescription']}");
          if (res['success'] != 'true') {
            throw Exception("Failed SELECT DF: ${res['swDescription']}");
          }

          logger.log("Selecting EF...");
          res = await apdu.transmitAPDU(sod1Commands['SELECT_EF']!);
          logger.log("SELECT_EF: ${res['swDescription']}");
          if (res['success'] != 'true') {
            throw Exception("Failed SELECT EF: ${res['swDescription']}");
          }
        } catch (e) {
          logger.log("Error during file selection: $e");
          throw Exception("File selection failed: $e");
        }

        logger.log("Reading SOD binary data...");
        String sodData = await _readDataWithContinuation(0, 0xEC);

        if (sodData.isNotEmpty) {
          logger.log("SOD data collected: ${sodData.length ~/ 2} bytes");
          result = {
            'success': true,
            'sodData': sodData,
            'size': sodData.length ~/ 2,
          };
        } else {
          logger.log("❌ No SOD data could be read", highlight: true);
        }
        return result;
      },
      successMessage: "SOD reading completed",
      failureMessage: "Error reading SOD",
    );
  }
}
