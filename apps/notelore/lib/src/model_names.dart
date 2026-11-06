final _numbers = RegExp(r'^\d+(\.\d+)?$');

String _cap(String word) => word[0].toUpperCase() + word.substring(1);

/// A short name people read, from a provider's model id, or the id itself when
/// the family is unknown (#722).
String readableModel(String id) {
  final base = id
      .replaceFirst(RegExp(r'-\d{8}$'), '')
      .replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
  final parts = base.split('-');
  if (parts.length < 2 || parts.any((part) => part.isEmpty)) return id;
  final name = switch (parts.first) {
    'claude' => _claude(parts),
    'gpt' => _gpt(parts),
    'gemini' => _gemini(parts),
    'deepseek' => _deepseek(parts),
    _ => null,
  };
  return name ?? id;
}

String? _claude(List<String> parts) {
  final family = parts.firstWhere(
    (part) => const {'sonnet', 'opus', 'haiku'}.contains(part),
    orElse: () => '',
  );
  final version = parts.where(_numbers.hasMatch).toList();
  if (family.isEmpty || version.isEmpty) return null;
  return 'Claude ${_cap(family)} ${version.join('.')}';
}

String? _gpt(List<String> parts) {
  if (!RegExp(r'^\d').hasMatch(parts[1])) return null;
  final rest = parts.skip(2).where((part) => !_numbers.hasMatch(part)).toList();
  return 'GPT-${parts[1]}${rest.isEmpty ? '' : ' ${rest.join(' ')}'}';
}

String? _gemini(List<String> parts) {
  if (!_numbers.hasMatch(parts[1])) return null;
  final rest = parts.skip(2).map(_cap).toList();
  return 'Gemini ${parts[1]}${rest.isEmpty ? '' : ' ${rest.join(' ')}'}';
}

String? _deepseek(List<String> parts) {
  final rest = parts.skip(1).map(_cap).toList();
  return rest.isEmpty ? null : 'DeepSeek ${rest.join(' ')}';
}
