import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import 'catalog.dart';
import 'fake.dart';
import 'fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  final session = await fakeSession();
  runApp(Widgetbook.material(directories: catalogDirectories(session), addons: catalogAddons));
}
