import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/main.dart' as app;
import 'package:notelore/src/app.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// path_provider answering from a temp folder instead of the platform.
class FakeFolders extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakeFolders(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'documents');
}

void main() {
  late String root;
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('notelore_main_');
    addTearDown(() => dir.deleteSync(recursive: true));
    root = dir.path;
    PathProviderPlatform.instance = FakeFolders(root);
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('desktop: notes in a visible ~/Notelore, state in the support folder', () async {
    final session = await app.openSession(environment: {'HOME': root}, mobile: false);
    addTearDown(session.dispose);
    expect(session.paths.notes.path, p.join(root, 'Notelore'));
    expect(session.paths.state.path, p.join(root, 'support'));
    expect(session.ready, isFalse);
  });

  test('phone: notes in the app documents', () async {
    final session = await app.openSession(environment: {}, mobile: true);
    addTearDown(session.dispose);
    expect(session.paths.notes.path, p.join(root, 'documents', 'Notelore'));
  });

  test('NOTELORE_HOME overrides everything', () async {
    final session = await app.openSession(environment: {'NOTELORE_HOME': root});
    addTearDown(session.dispose);
    expect(session.paths.notes.path, p.join(root, 'notes'));
    expect(session.paths.state.path, p.join(root, 'state'));
  });

  testWidgets('main() runs the app', (tester) async {
    await tester.runAsync(() async => app.main());
    await tester.pump();
    expect(find.byType(NoteloreApp), findsOneWidget);
  });
}
