import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android backs nothing up: Drive is the backup, and keys cannot move (#314)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
    for (final kind in ['cloud-backup', 'device-transfer']) {
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(
          RegExp('<$kind>[^]*<exclude domain="$domain" path="[.]"[^]*</$kind>').hasMatch(rules),
          isTrue,
          reason: '$kind keeps $domain',
        );
      }
    }
  });

  test('the Windows setup refreshes the icon cache and wears the mark itself (#403)', () {
    final setup = File('windows/installer/notelore.iss').readAsStringSync();
    // An update in the same folder: without a refresh the taskbar keeps the old icon.
    expect(setup, contains('ChangesAssociations=yes'));
    expect(setup, contains(r'SetupIconFile=..\runner\resources\app_icon.ico'));
  });
}
