// The developer's command line; see lib/src/dev.dart. Run from the repository
// root: NOTELORE_HOME=.dev-home dart run notelore_core:notelore_dev chat "hi"
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:notelore_core/src/dev.dart';

Future<void> main(List<String> args) async {
  exitCode = await runDev(
    args,
    environment: Platform.environment,
    currentDirectory: Directory.current,
    out: stdout,
    client: http.Client(),
    openBrowser: (url) async {
      stdout.writeln('Opening $url');
      // rundll32, not `start`: cmd would split the URL at every &.
      final (command, prefix) = Platform.isWindows
          ? ('rundll32', ['url.dll,FileProtocolHandler'])
          : (Platform.isMacOS ? 'open' : 'xdg-open', <String>[]);
      await Process.run(command, [...prefix, '$url']);
    },
  );
}
