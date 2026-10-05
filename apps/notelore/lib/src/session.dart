/// Everything the screens share: the chosen provider and its key, the agent,
/// the conversation, and the notes folder.
///
/// The API key lives in the platform keystore (Android Keystore, Keychain,
/// Windows Credential Manager); the provider and model in `settings.json` in the
/// state folder, which is derived, device-local state like the index.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

typedef Validate = Future<void> Function(ProviderSpec spec, String key);
typedef MakeProvider = LlmProvider Function(ProviderSpec spec, String? key, {String? model});

enum ChatRole { user, assistant, error }

typedef ChatLine = ({ChatRole role, String text});

class Session extends ChangeNotifier {
  Session(
    this.paths, {
    this.validate = validateKey,
    this.makeProvider = createProvider,
    this.today,
    this.keys = const FlutterSecureStorage(
      // The login keychain: the data-protection one needs a signed app with a
      // keychain-access-groups entitlement, which debug builds do not have.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : index = NoteIndex(p.join(paths.state.path, 'index.sqlite'), paths.notes.path);

  final NotelorePaths paths;
  final Validate validate;
  final MakeProvider makeProvider;

  /// Tests pin it; the app uses the local date.
  final DateTime? today;
  final FlutterSecureStorage keys;
  final NoteIndex index;

  ProviderSpec? spec;
  String? model;
  Agent? _agent;
  final transcript = <ChatLine>[];
  bool busy = false;

  bool get ready => _agent != null;

  String get _settings => p.join(paths.state.path, 'settings.json');

  static String _keyName(ProviderSpec spec) => 'notelore.${spec.name}.api_key';

  /// Picks up the provider chosen on an earlier run; no network involved.
  Future<void> load() async {
    final Object? saved;
    try {
      saved = jsonDecode(File(_settings).readAsStringSync());
    } on FileSystemException {
      return; // first run
    } on FormatException {
      return; // damaged: set up again
    }
    if (saved case {'provider': final String name, 'model': final String chosen}) {
      final found = providerSpecs.where((s) => s.name == name).firstOrNull;
      if (found == null) return;
      final key = found.requiresApiKey ? await keys.read(key: _keyName(found)) : '';
      if (key == null) return; // the keystore lost it: set up again
      _use(found, key, chosen);
    }
  }

  /// Checks [key] with the provider, then remembers it. Throws
  /// [KeyValidationError] or [TransientValidationError] and changes nothing.
  Future<void> connect(ProviderSpec spec, String key, {String? model}) async {
    final trimmed = key.trim();
    await validate(spec, trimmed);
    if (spec.requiresApiKey) await keys.write(key: _keyName(spec), value: trimmed);
    _use(spec, trimmed, model ?? spec.defaultModel);
    _save();
  }

  /// A blank [chosen] goes back to the provider's default model.
  Future<void> setModel(String chosen) async {
    final current = spec;
    if (current == null) return;
    final key = current.requiresApiKey ? await keys.read(key: _keyName(current)) : '';
    final trimmed = chosen.trim();
    _use(current, key!, trimmed.isEmpty ? current.defaultModel : trimmed);
    _save();
  }

  Future<void> logout() async {
    final current = spec;
    if (current != null && current.requiresApiKey) await keys.delete(key: _keyName(current));
    final settings = File(_settings);
    if (settings.existsSync()) settings.deleteSync();
    spec = null;
    model = null;
    _agent = null;
    transcript.clear();
    notifyListeners();
  }

  void _use(ProviderSpec chosen, String key, String chosenModel) {
    spec = chosen;
    model = chosenModel;
    final toolbox = Toolbox(paths.notes.path, index, today: today);
    _agent = Agent(makeProvider(chosen, key, model: chosenModel), toolbox, today: today);
    notifyListeners();
  }

  void _save() =>
      atomicWrite(_settings, '${jsonEncode({'provider': spec!.name, 'model': model})}\n');

  /// One chat turn. A provider failure becomes an error line; the agent has
  /// already taken the turn back, so the user can simply send again.
  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || busy) return;
    transcript.add((role: ChatRole.user, text: message));
    busy = true;
    notifyListeners();
    try {
      final answer = await _agent!.ask(message);
      transcript.add((role: ChatRole.assistant, text: answer));
    } on Exception catch (error) {
      transcript.add((role: ChatRole.error, text: '$error'));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<NoteInfo> listNotes() => (index..rebuild()).listNotes();

  /// The note as Markdown from its `# title` down (the front matter is for tools).
  String readNote(NoteInfo note) =>
      withoutFrontMatter(File(notePath(paths.notes.path, note.kind, note.slug)).readAsStringSync());

  @override
  void dispose() {
    index.close();
    super.dispose();
  }
}

String withoutFrontMatter(String text) {
  if (!text.startsWith('---\n')) return text;
  final end = text.indexOf('\n---\n', 3);
  return end < 0 ? text : text.substring(end + 5);
}
