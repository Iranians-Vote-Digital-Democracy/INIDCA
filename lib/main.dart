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
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:inid_assistant/certificate_export.dart';
import 'package:inid_assistant/certificate_utils.dart';
import 'package:inid_assistant/logging.dart'; 
import 'package:inid_assistant/smart_card_operations.dart';
import 'package:x509/x509.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MaterialApp(
      home: BasicNfcApp(), debugShowCheckedModeBanner: false));
}

class BasicNfcApp extends StatefulWidget {
  const BasicNfcApp({super.key});

  @override
  BasicNfcAppState createState() => BasicNfcAppState();
}

class BasicNfcAppState extends State<BasicNfcApp> {
  String _log = "Press the button to send an APDU command.";
  bool _certSuccessfullyRead = false; // New state to track if cert was read
  NFCAvailability _nfcStatus = NFCAvailability.not_supported;
  final ScrollController _scrollController = ScrollController();

  // Instantiate AppLogger WITH required parameters
  late final AppLogger _logger;

  late SmartCardOperations
      _smartCardOps; // Declare SmartCardOperations instance

  String? _lastCardId;
  Uint8List _lastCertificateData = Uint8List(0); // Use Uint8List

  @override
  void initState() {
    super.initState();

    // Initialize logger here, passing the required parameters
    _logger = AppLogger(
      addToLog: _addToLog, // Pass the _addToLog method
      scrollController: _scrollController, // Pass the ScrollController instance
    );

    // Instantiate SmartCardOperations
    _smartCardOps = SmartCardOperations(
      logger: _logger, // Pass the initialized logger
      updateLastCardId: (id) {
        if (mounted) {
          setState(() {
            _lastCardId = id;
          });
        }
      },
      setProcessing: (isProcessing) {
        // Optional: Add UI indicator for processing state
      },
    );

    _checkNfcAvailability();
    // Start automatic polling and certificate extraction
    _startAutomaticExtraction();
  }

  // Modified automatic extraction method to use SmartCardOperations
  Future<void> _startAutomaticExtraction() async {
    // Skip if we already have a certificate or if widget is disposed
    if (_certSuccessfullyRead || !mounted) return;

    _logger.log("Attempting automatic certificate extraction...");

    // Use the refactored method from SmartCardOperations
    Map<String, dynamic>? certResult =
        await _smartCardOps.readSigningCertificate();

    if (!mounted) return;

    if (certResult != null && certResult['success'] == true) {
      String certHex = certResult['certificateData'];
      Uint8List certBytes = CertificateUtils.hexStringToBytes(certHex);

      if (certBytes.isNotEmpty) {
        _logger.log(
          "Certificate extracted successfully (${certResult['size']} bytes).",
          highlight: true,
        );
        _processCertificateData(certBytes, "SigningCert");

        setState(() {
          _certSuccessfullyRead = true;
        });
        return;
      } else {
        _logger.log(
          "Extraction successful but certificate data is empty.",
          highlight: true,
        );
      }
    } else {
      _logger.log(
        "Automatic certificate extraction failed or was cancelled.",
        highlight: true,
      );
    }

    await Future.delayed(const Duration(seconds: 5));
    if (mounted && !_certSuccessfullyRead) {
      _startAutomaticExtraction();
    }
  }

  // Method to refresh certificate (triggered by the refresh button)
  void _refreshCertificate() {
    if (!mounted) return;
    setState(() {
      _certSuccessfullyRead = false;
      _log = "Starting certificate refresh...";
      _lastCertificateData = Uint8List(0);
    });
    _logger.log("Certificate refresh requested", highlight: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _log = "Starting certificate refresh...";
        });
      }
      _startAutomaticExtraction();
    });
  }

  // Check NFC availability when app starts
  Future<void> _checkNfcAvailability() async {
    try {
      NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
      if (!mounted) return;
      setState(() {
        _nfcStatus = availability;
      });
      _logger.log("NFC Status: $availability");
    } catch (e) {
      _logger.log("Error checking NFC: $e");
    }
  }

  // Enhanced logging functionality
  void _addToLog(String message, {bool highlight = false}) {
    // Check if the widget is still mounted before calling setState
    if (!mounted) return;

    setState(() {
      String timestamp = DateTime.now().toString().substring(11, 23);
      String logMessage = "[$timestamp] $message";
      // Log to console via developer.log and debugPrint
      developer.log(highlight ? '🔔 $logMessage' : logMessage, name: 'NFC_LOG');
      debugPrint(
        highlight ? '\n==== HIGHLIGHTED: $logMessage ====\n' : logMessage,
      );
      // Update the UI state variable
      _log += "\n$logMessage";
    });

    // Scroll to bottom after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Fixed _processCertificateData to accept Uint8List
  Future<void> _processCertificateData(
      Uint8List certificateData, String approach) async {
    if (!mounted) return;

    if (certificateData.isEmpty) {
      _logger.log(
        "$approach certificate extraction completed but no data returned",
        highlight: true,
      );
      return;
    }

    try {
      setState(() {
        _lastCertificateData = certificateData;
      });

      String hexData = CertificateUtils.toHexString(certificateData);

      _logger.log(
        "$approach certificate processed: ${certificateData.length} bytes",
        highlight: true,
      );

      _logger.log("\n=== FULL $approach CERTIFICATE DATA ===", highlight: true);
      CertificateUtils.addFullCertificateToLog(
        hexData,
        // This is the function being passed as the parameter:
        addToLog: (msg, {highlight = false}) =>
            _logger.log(msg, highlight: highlight),
      );
      _logger.log("=== END $approach CERTIFICATE DATA ===", highlight: true);

      final certId = await CertificateUtils.saveCertificateAsBinary(
        certificateData,
      );
      _logger.log("Certificate securely stored: $certId", highlight: true);

      final pemData = CertificateExporter.toPEM(certificateData);
      _logger.log("\n=== $approach CERTIFICATE DATA (PEM) ===",
          highlight: true);
      _logger.log(pemData);
      _logger.log("=== END $approach CERTIFICATE DATA (PEM) ===",
          highlight: true);

      _parseAndLogX509Certificate(certificateData, approach);
    } catch (e) {
      _logger.log("Error processing certificate data: $e", highlight: true);
    }
  }

  // New method to parse and log X.509 certificate details
  void _parseAndLogX509Certificate(
    Uint8List certificateData,
    String approach,
  ) {
    try {
      String base64Cert = base64Encode(certificateData);
      String pemCert =
          '-----BEGIN CERTIFICATE-----\n$base64Cert\n-----END CERTIFICATE-----';

      var certificate = parsePem(pemCert).first as X509Certificate;

      _logger.log("\n=== $approach CERTIFICATE DETAILS (x509) ===",
          highlight: true);
      _logger.log("• Subject: ${certificate.tbsCertificate.subject}");
      _logger.log("• Issuer: ${certificate.tbsCertificate.issuer}");
      _logger
          .log("• Serial Number: ${certificate.tbsCertificate.serialNumber}");
      _logger.log(
          "• Valid From: ${certificate.tbsCertificate.validity?.notBefore}");
      _logger
          .log("• Valid To: ${certificate.tbsCertificate.validity?.notAfter}");
      _logger.log("• Version: ${certificate.tbsCertificate}");
      _logger.log("• Signature Algorithm: ${certificate.signatureAlgorithm}");
      _logger.log("=== END $approach CERTIFICATE DETAILS (x509) ===",
          highlight: true);
    } catch (e) {
      _logger.log("Error parsing X.509 certificate: $e", highlight: true);
    }
  }

  // Method to handle certificate export
  void _exportCertificate() async {
    if (!mounted) return;

    if (_lastCertificateData.isEmpty) {
      _logger.log("No certificate available to export", highlight: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No certificate data to export.")),
      );
      return;
    }

    String fileName = _lastCardId != null
        ? 'certificate_${_lastCardId!}.cer'
        : 'certificate_${DateTime.now().millisecondsSinceEpoch}.cer';

    try {
      String filePath =
          await CertificateUtils.saveCertificateToTempFileForSharing(
        _lastCertificateData,
        fileName,
      );

      _logger.log("Certificate prepared for sharing at: $filePath",
          highlight: true);

      await CertificateUtils.shareCertificateFile(filePath, context: context);
    } catch (e) {
      _logger.log("Error preparing/sharing certificate: $e", highlight: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error exporting certificate: $e")),
        );
      }
    }
  }

  Color _getNfcStatusColor() {
    return switch (_nfcStatus) {
      NFCAvailability.available => Colors.green.shade100,
      NFCAvailability.disabled => Colors.orange.shade100,
      NFCAvailability.not_supported => Colors.red.shade100,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text(
        "Iranian National ID Card Reader",
        textAlign: TextAlign.center,
      )),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: _getNfcStatusColor(),
              child: Text(
                "NFC Status: $_nfcStatus",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue.shade50,
              child: Text(
                "Last Card ID: ${_lastCardId ?? 'None'}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _log,
                    style:
                        const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_certSuccessfullyRead)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _refreshCertificate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text(
                          "Refresh Certificate",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _exportCertificate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text(
                          "Export Certificate",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
