/// Runs the core latency probe inside a temporary Android app session.
/// The probe only creates temp notes and never opens app state or provider keys.
library;

import 'package:flutter/widgets.dart';

// Reuse the workspace-only probe without adding it to the production library.
import '../../../packages/notelore_core/tool/latency_probe.dart' as probe;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Running latency probe; see Flutter logs.')),
    ),
  );

  await probe.main(['--large']);
  await probe.main([]);
  print('Latency probe complete.');
}
