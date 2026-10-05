/// Opt-in checks against the real services: `dart test -t live`.
///
/// Each test needs its key in the environment (`NOTELORE_<PROVIDER>_API_KEY`) or,
/// for Ollama, a running daemon plus `NOTELORE_LIVE_OLLAMA`; otherwise it is
/// skipped, so the default run never touches the network.
@Tags(['live'])
library;

import 'dart:io';

import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/providers.dart';
import 'package:notelore_core/src/providers/validator.dart';
import 'package:test/test.dart';

void main() {
  for (final spec in providerSpecs) {
    final variable = 'NOTELORE_${spec.name.toUpperCase()}_API_KEY';
    final key = Platform.environment[variable] ?? '';
    final skip = spec.requiresApiKey
        ? (key.isEmpty ? '$variable not set' : null)
        : (Platform.environment['NOTELORE_LIVE_OLLAMA'] == null
              ? 'NOTELORE_LIVE_OLLAMA not set'
              : null);
    test('${spec.name}: the key validates and one turn answers', skip: skip, () async {
      await validateKey(spec, key);
      final response = await createProvider(spec, key).turn('Answer with one word.', [
        {'role': 'user', 'content': 'Say: pong'},
      ], []);
      expect(response.stopReason, 'end_turn');
      expect(response.content.any((b) => b['type'] == 'text' && '${b['text']}'.isNotEmpty), isTrue);
    });
  }
}
