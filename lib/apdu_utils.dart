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

class ApduUtils {
  /// Parses an APDU response and returns a map containing the status word and data.
  static Map<String, String> parseApduResponse(String response) {
    if (response.length < 4) {
      return {'sw': 'N/A', 'data': response};
    }

    String sw = response.substring(response.length - 4);
    String data =
        response.length > 4 ? response.substring(0, response.length - 4) : '';

    String swDescription = 'Unknown';
    if (sw == '9000') {
      swDescription = 'Success';
    } else if (sw.startsWith('61')) {
      swDescription = 'More data available';
    } else if (sw.startsWith('6A')) {
      swDescription = 'Wrong parameter';
    } else if (sw.startsWith('6D')) {
      swDescription = 'Instruction not supported';
    } else if (sw.startsWith('6E')) {
      swDescription = 'Class not supported';
    } else if (sw == '6700') {
      swDescription = 'Wrong length';
    } else if (sw == '6F00') {
      swDescription = 'Unknown error';
    }

    return {'sw': '$sw ($swDescription)', 'data': data};
  }
}
