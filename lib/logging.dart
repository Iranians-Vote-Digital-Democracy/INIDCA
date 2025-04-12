import 'dart:developer' as developer;

import 'package:flutter/material.dart';

class AppLogger {
  final void Function(String, {bool highlight}) addToLog;
  final ScrollController scrollController;
  String? lastCardId;

  AppLogger({
    required this.addToLog,
    required this.scrollController,
    this.lastCardId,
  });

  // Enhanced logging functionality
  void log(String message, {bool highlight = false}) {
    // Format message with timestamp for consistency
    String timestamp = DateTime.now().toString().substring(11, 23);
    String logMessage = "[$timestamp] $message";

    // Enhanced debug console logging
    if (highlight) {
      // Use developer.log for important messages with a custom name for filtering
      developer.log('🔔 $logMessage', name: 'NFC_CERTIFICATE');
      // Print with additional markers for visibility
      debugPrint('\n════════════════════════════════════');
      debugPrint('🔔 $logMessage');
      debugPrint('════════════════════════════════════\n');
    } else {
      // Regular logs
      debugPrint(logMessage);
    }

    // UI logging (unchanged)
    addToLog(logMessage);

    // Schedule scroll to bottom after the UI updates
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
