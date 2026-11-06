import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/model_names.dart';

void main() {
  test('model ids read as names; unknown ones stay as they are (#722)', () {
    expect(readableModel('claude-sonnet-5-5'), 'Claude Sonnet 5.5');
    expect(readableModel('claude-sonnet-5-5-20260801'), 'Claude Sonnet 5.5');
    expect(readableModel('claude-3-5-sonnet-20241022'), 'Claude Sonnet 3.5');
    expect(readableModel('claude-opus-4-8'), 'Claude Opus 4.8');
    expect(readableModel('gpt-5.1'), 'GPT-5.1');
    expect(readableModel('gpt-5'), 'GPT-5');
    expect(readableModel('gpt-5-mini'), 'GPT-5 mini');
    expect(readableModel('gpt-4o-mini'), 'GPT-4o mini');
    expect(readableModel('gpt-5-nano-2025-08-07'), 'GPT-5 nano');
    expect(readableModel('gemini-2.5-flash'), 'Gemini 2.5 Flash');
    expect(readableModel('gemini-3.1-flash-lite'), 'Gemini 3.1 Flash Lite');
    expect(readableModel('deepseek-flash'), 'DeepSeek Flash');
    expect(readableModel('deepseek'), 'deepseek');
    // Unknown or not a model: the id as it is.
    expect(readableModel('claude-x'), 'claude-x');
    expect(readableModel('claude-sonnet'), 'claude-sonnet');
    expect(readableModel('gemini-exp-1206'), 'gemini-exp-1206');
    expect(readableModel('qwen3:4b'), 'qwen3:4b');
    expect(readableModel('model-a'), 'model-a');
    expect(readableModel('gemini-2.5-'), 'gemini-2.5-');
    expect(readableModel('deepseek-'), 'deepseek-');
    expect(readableModel(''), '');
  });
}
