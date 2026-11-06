/// A short name people read, from a provider's model id, or the id itself when
/// the family is unknown (#722).
String readableModel(String id) {
  final base = id
      .replaceFirst(RegExp(r'-\d{8}$'), '')
      .replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
  final parts = base.split('-');
  if (parts.length < 2 || parts.any((part) => part.isEmpty)) return id;
  final numbers = RegExp(r'^\d+(\.\d+)?$');
  String cap(String word) => word[0].toUpperCase() + word.substring(1);
  switch (parts.first) {
    case 'claude':
      final family = parts.firstWhere(
        (p) => const {'sonnet', 'opus', 'haiku'}.contains(p),
        orElse: () => '',
      );
      final version = parts.where(numbers.hasMatch).toList();
      if (family.isEmpty || version.isEmpty) return id;
      return 'Claude ${cap(family)} ${version.join('.')}';
    case 'gpt':
      if (!RegExp(r'^\d').hasMatch(parts[1])) return id;
      final rest = parts.skip(2).where((p) => !numbers.hasMatch(p)).toList();
      return 'GPT-${parts[1]}${rest.isEmpty ? '' : ' ${rest.join(' ')}'}';
    case 'gemini':
      if (!numbers.hasMatch(parts[1])) return id;
      final rest = parts.skip(2).map(cap).toList();
      return 'Gemini ${parts[1]}${rest.isEmpty ? '' : ' ${rest.join(' ')}'}';
    case 'deepseek':
      final rest = parts.skip(1).map(cap).toList();
      return rest.isEmpty ? id : 'DeepSeek ${rest.join(' ')}';
    default:
      return id;
  }
}
