/*
* Orion - NanoDLP Form Controls Test
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_form_controls.dart';

/// Representative slice of NanoDLP's `#setup` profile form: an entity-escaped
/// title, selects (one with a preselected option, one empty), a multi-line
/// code textarea, hidden fields, a checkbox pair, and controls a browser
/// would not submit.
const _cloneFormHtml = '''
<html><body>
<form action="" method="post" class="edit-page" id="setup">
  <input class="form-control" type="text" value="Locked Resin &amp; Co" name="Title">
  <select name="AntiAlias" id="AntiAlias">
    <option value="0"  translate>Enable</option>
    <option value="1" selected translate>Disable</option>
  </select>
  <select name="EmptySelect" id="EmptySelect"></select>
  <textarea name="ShieldBeforeLayer" rows="3">G90 &lt;start&gt;
M105 &amp; wait</textarea>
  <input type="hidden" name="UpdateCustomInput" value="true">
  <input type="hidden" value="0.000000" name="JumpHeight">
  <input class="form-control checkbox-profile" value="0" name="FssEnablePeeldetection" id="PdEnableSimple" type="checkbox">
  <input class="form-control checkbox-profile" value="0" name="FssEnableCrashdetection" id="CdEnableSimple" type="checkbox" checked>
  <input class="form-control" type="text" value="skip-me" name="DisabledField" disabled>
  <input class="form-control" type="text" value="ignored">
  <button type="submit" class="btn btn-success">Save</button>
  <input type="submit" value="Save">
</form>
<form action="" method="post" class="edit-page hidden" id="setup2">
  <input type="text" value="easy-mode" name="Title">
  <input type="text" value="99" name="SimpleLiftSpeed">
</form>
</body></html>
''';

void main() {
  group('NanoFormControls', () {
    test('serializes the requested form the way a browser submits it', () {
      final controls = NanoFormControls.parse(_cloneFormHtml);

      expect(controls['Title'], 'Locked Resin & Co');
      expect(controls['AntiAlias'], '1');
      expect(controls['EmptySelect'], '');
      expect(controls['ShieldBeforeLayer'], 'G90 <start>\nM105 & wait');
      expect(controls['UpdateCustomInput'], 'true');
      expect(controls['JumpHeight'], '0.000000');
      // Checked checkbox is submitted, unchecked and disabled ones are not.
      expect(controls['FssEnableCrashdetection'], '0');
      expect(controls.containsKey('FssEnablePeeldetection'), isFalse);
      expect(controls.containsKey('DisabledField'), isFalse);
      // Submit buttons and unnamed inputs never reach the server.
      expect(controls.values, isNot(contains('Save')));
      expect(controls.values, isNot(contains('ignored')));
      // Only #setup is serialized; #setup2's easy-mode fields stay out.
      expect(controls.containsKey('SimpleLiftSpeed'), isFalse);
      expect(controls.length, 7);
    });

    test('keeps the first value for duplicate names', () {
      final controls = NanoFormControls.parse('''
<form id="setup">
  <input type="text" name="CureTime" value="1.5">
  <input type="text" name="CureTime" value="9.9">
</form>
''');

      expect(controls['CureTime'], '1.5');
    });

    test('falls back to the first form when the id is absent', () {
      final controls = NanoFormControls.parse('''
<form action="" method="post">
  <input type="text" name="Title" value="Only Form">
</form>
''');

      expect(controls['Title'], 'Only Form');
    });

    test('returns nothing when the page has no form', () {
      expect(NanoFormControls.parse('<html><body>none</body></html>'), isEmpty);
    });
  });
}
