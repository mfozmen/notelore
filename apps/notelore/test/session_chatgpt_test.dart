import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  final plan = findProvider('chatgpt');

  test('the ChatGPT plan is offered only where its sign-in exists (not on phones)', () {
    expect(Harness().session().providers.map((s) => s.name), isNot(contains('chatgpt')));
    expect(Harness(chatGpt: FakeAuth()).session().providers.first.name, 'chatgpt');
  });

  test('connecting signs in with ChatGPT and starts on the cheapest plan model', () async {
    final sign = FakeAuth();
    final harness = Harness(chatGpt: sign)..planModels = ['gpt-6.1', 'gpt-6.1-mini', 'gpt-5.5'];
    final session = harness.session();
    await session.connect(plan, '');
    expect(sign.granted, isTrue);
    expect(session.ready, isTrue);
    expect(session.model, 'gpt-6.1-mini');
    expect(session.models, ['gpt-6.1-mini', 'gpt-6.1']); // only the current versions
    expect(harness.tokens.last, isNotNull); // the provider gets the plan's token
    expect(await const FlutterSecureStorage().readAll(), {
      'notelore.chatgpt.welcomed': 'yes', // no API key is stored
    });
    expect(session.showPlanWelcome, isTrue); // the first time only
  });

  test('the welcome shows once per device', () async {
    final harness = Harness(chatGpt: FakeAuth());
    final session = harness.session();
    await session.connect(plan, '');
    session.showPlanWelcome = false; // shown and dismissed
    await session.logout();
    await session.connect(plan, '');
    expect(session.showPlanWelcome, isFalse);
  });

  test('a refused ChatGPT sign-in changes nothing', () async {
    final harness = Harness(
      chatGpt: FakeAuth()..failSignIn = const SignInFailed('access_denied', service: 'ChatGPT'),
    );
    final session = harness.session();
    await expectLater(session.connect(plan, ''), throwsA(isA<SignInFailed>()));
    expect(session.ready, isFalse);
  });

  test('a plan that lists no models is not connected', () async {
    final harness = Harness(chatGpt: FakeAuth())..planModels = [];
    final session = harness.session();
    await expectLater(session.connect(plan, ''), throwsA(isA<TransientValidationError>()));
    expect(session.ready, isFalse);
  });

  test('a restart keeps the plan while signed in, and asks again when not', () async {
    final sign = FakeAuth();
    final harness = Harness(chatGpt: sign);
    await harness.session().connect(plan, '');
    final again = harness.session();
    await again.load();
    expect(again.ready, isTrue);
    expect(again.spec!.name, 'chatgpt');
    sign.granted = false; // signed out, or revoked
    final third = harness.session();
    await third.load();
    expect(third.ready, isFalse);
  });

  test('a blank model goes back to the cheapest plan model', () async {
    final harness = Harness(chatGpt: FakeAuth())..planModels = ['gpt-6.1', 'gpt-6.1-mini'];
    final session = harness.session();
    await session.connect(plan, '');
    await session.setModel('gpt-6.1');
    expect(session.defaultModel, 'gpt-6.1-mini');
    await session.setModel('');
    expect(session.model, 'gpt-6.1-mini');
  });

  test('refreshing the list never opens a browser', () async {
    final sign = FakeAuth();
    final harness = Harness(chatGpt: sign);
    final session = harness.session();
    await session.connect(plan, '');
    sign.failSignIn = const SignInFailed('must not be asked', service: 'ChatGPT');
    harness.planModels = ['gpt-plan-c'];
    await session.refreshModels();
    expect(session.models, ['gpt-plan-c']);
  });

  test('logging out signs out of ChatGPT too', () async {
    final sign = FakeAuth();
    final session = Harness(chatGpt: sign).session();
    await session.connect(plan, '');
    await session.logout();
    expect(sign.signedOut, isTrue);
    expect(session.ready, isFalse);
  });
}
