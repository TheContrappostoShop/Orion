/*
* Orion - Error Details
* Copyright (C) 2024 TheContrappostoShop
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

class ErrorDetails {
  final String title;
  final String message;

  ErrorDetails(this.title, this.message);
}

final Map<String, ErrorDetails> errorLookupTable = {
  'default': ErrorDetails(
    'Unknown Error',
    'An unknown error has occurred. Please contact support.',
  ),
  'PINK-CARROT': ErrorDetails(
    'Odyssey API Error',
    'An Error has occurred while fetching files!\n'
        'Please ensure that Odyssey is running and accessible.\n\n'
        'If the issue persists, please contact support.\n'
        'Error Code: PINK-CARROT',
  ),
  'BLUE-BANANA': ErrorDetails(
    'Network Error',
    'A network error has occurred. Please check your internet connection and try again.\n\n'
        'Error Code: BLUE-BANANA',
  ),
  'RED-APPLE': ErrorDetails(
    'Resin Level Low',
    'The resin level is too low. Please refill the resin tank.\n\n'
        'Error Code: RED-APPLE',
  ),
  'GREEN-GRAPE': ErrorDetails(
    'Print Failure',
    'The print has failed. Please check the model and try again.\n\n'
        'Error Code: GREEN-GRAPE',
  ),
  'YELLOW-LEMON': ErrorDetails(
    'Temperature Error',
    'The temperature is outside the acceptable range. Please check the printer environment.\n\n'
        'Error Code: YELLOW-LEMON',
  ),
  'ORANGE-ORANGE': ErrorDetails(
    'UV Light Error',
    'The UV light is not functioning correctly. Please check the light source.\n\n'
        'Error Code: ORANGE-ORANGE',
  ),
  'PURPLE-PLUM': ErrorDetails(
    'Build Plate Error',
    'The build plate is not correctly calibrated. Please recalibrate the build plate.\n\n'
        'Error Code: PURPLE-PLUM',
  ),
  'BROWN-BEAR': ErrorDetails(
    'Firmware Update Error',
    'There was an error during the firmware update. Please try again.\n\n'
        'Error Code: BROWN-BEAR',
  ),
  'BLACK-BERRY': ErrorDetails(
    'File Error',
    'The selected file cannot be read. Please check the file and try again.\n\n'
        'Error Code: BLACK-BERRY',
  ),
  'WHITE-WOLF': ErrorDetails(
    'Sensor Error',
    'A sensor is not working correctly. Please check the printer sensors.\n\n'
        'Error Code: WHITE-WOLF',
  ),
};
