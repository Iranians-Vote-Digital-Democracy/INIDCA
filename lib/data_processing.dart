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

import 'dart:typed_data';

class CardDataProcessor {
  // Convert hex string to bytes (like the C++ hexStringToBytes function)
  static Uint8List hexStringToBytes(String hexString) {
    List<int> bytes = [];
    for (int i = 0; i < hexString.length; i += 2) {
      if (i + 2 <= hexString.length) {
        int byte = int.parse(hexString.substring(i, i + 2), radix: 16);
        bytes.add(byte);
      }
    }
    return Uint8List.fromList(bytes);
  }

  // Convert bytes to hex string (like the C++ bytesToHexString function)
  static String bytesToHexString(List<int> bytes) {
    StringBuffer sb = StringBuffer();
    for (int byte in bytes) {
      sb.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  // Extract CSN from CPLC data based on mav4_read_csn_crn.cpp
  static String extractCsnFromCplc(String cplcData) {
    if (cplcData.length < 42) {
      // 0x08 + 0x13 *2 (hex chars)
      return '';
    }
    return cplcData.substring(16, 58); // offset=0x08, length=0x13 in hex chars
  }

  // Extract CRN from Tag0101 data based on mav4_read_csn_crn.cpp
  static String extractCrnFromTag0101(String tag0101Data) {
    if (tag0101Data.length < 38) {
      // 0x10 + 0x03 *2 (hex chars)
      return '';
    }
    return tag0101Data.substring(
      32,
      38,
    ); // offset=0x10, length=0x03 in hex chars
  }

  // Parse date information from card data (based on mav4_ReadDates.cpp)
  static Map<String, String> extractDatesFromCardData(String cardData) {
    Map<String, String> dates = {'issueDate': '', 'expiryDate': ''};

    // Look for tag B2 (issue date)
    int posB2 = cardData.indexOf('b2');
    if (posB2 >= 0 && posB2 + 4 <= cardData.length) {
      String lenStr = cardData.substring(posB2 + 2, posB2 + 4);
      try {
        int lenVal = int.parse(lenStr, radix: 16);
        int dataPos = posB2 + 4;
        if (dataPos + (lenVal * 2) <= cardData.length) {
          dates['issueDate'] = cardData.substring(
            dataPos,
            dataPos + (lenVal * 2),
          );
        }
      } catch (e) {
        print('Error parsing issue date length: $e');
      }
    }

    // Look for tag B3 (expiry date)
    int posB3 = cardData.indexOf('b3', posB2 + 1);
    if (posB3 >= 0 && posB3 + 4 <= cardData.length) {
      String lenStr = cardData.substring(posB3 + 2, posB3 + 4);
      try {
        int lenVal = int.parse(lenStr, radix: 16);
        int dataPos = posB3 + 4;
        if (dataPos + (lenVal * 2) <= cardData.length) {
          dates['expiryDate'] = cardData.substring(
            dataPos,
            dataPos + (lenVal * 2),
          );
        }
      } catch (e) {
        print('Error parsing expiry date length: $e');
      }
    }

    return dates;
  }

  // Parse AFIS check data (based on mav4_afis_check.cpp)
  static String extractAfisCheckData(String metaInfo) {
    // Search for tag "ad" in the hex string
    int pos = 0;
    while (pos < metaInfo.length - 4) {
      if (metaInfo.substring(pos, pos + 2) == "ad") {
        // Get length (next byte)
        String lenHex = metaInfo.substring(pos + 2, pos + 4);
        try {
          int lenValue = int.parse(lenHex, radix: 16);
          // Make sure we have enough data
          if (pos + 4 + (lenValue * 2) <= metaInfo.length) {
            // Extract the data (starts after tag + length)
            return metaInfo.substring(pos + 4, pos + 4 + (lenValue * 2));
          }
        } catch (e) {
          print('Error parsing AFIS data length: $e');
        }
      }
      pos += 2;
    }
    return '';
  }
}
