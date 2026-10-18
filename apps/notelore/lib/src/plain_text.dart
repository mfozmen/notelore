/// An answer's Markdown as plain words (#335), for Copy: a messenger or a mail
/// shows them as they are, never `**Mopsos**`. The notes' own export keeps the
/// Markdown.
library;

import 'package:markdown/markdown.dart' as md;

/// [markdown] without its marks: blocks a blank line apart, list items one a
/// line ("- " or their number), a link's address after its words, an image's
/// words in its place.
String plainText(String markdown) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(markdown);
  return _blocks(nodes, '').trim();
}

String _blocks(List<md.Node> nodes, String indent) {
  final out = StringBuffer();
  for (final node in nodes) {
    final block = _block(node, indent);
    if (block.isEmpty) continue;
    // A list stays under the line that leads into it ("Decisions so far:").
    if (out.isNotEmpty) out.write(_isList(node) ? '\n' : '\n\n');
    out.write(block);
  }
  return out.toString();
}

bool _isList(md.Node node) => node is md.Element && (node.tag == 'ul' || node.tag == 'ol');

String _block(md.Node node, String indent) {
  if (node is! md.Element) return _inline(node);
  return switch (node.tag) {
    'ul' || 'ol' => _list(node, indent),
    'blockquote' => _blocks(node.children!, indent),
    'pre' => _inline(node).trimRight(),
    'table' => _table(node),
    _ => _inline(node).trim(), // a paragraph, a heading
  };
}

/// One item a line, after "- " or its number.
String _list(md.Element list, String indent) {
  final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
  return [
    for (final (index, item) in list.children!.indexed)
      '$indent${list.tag == 'ol' ? '${start + index}.' : '-'} ${_item(item as md.Element, indent)}',
  ].join('\n');
}

/// A row a line, its cells " | " apart; the header is the first row.
String _table(md.Element table) => [
  for (final part in table.children!)
    for (final row in (part as md.Element).children!)
      [for (final cell in (row as md.Element).children!) _inline(cell).trim()].join(' | '),
].join('\n');

/// A list item's words, and a list inside it indented under them.
String _item(md.Element item, String indent) {
  final words = StringBuffer();
  final nested = <String>[];
  for (final child in item.children!) {
    if (_isList(child)) {
      nested.add(_block(child, '$indent  '));
    } else {
      words.write(_inline(child));
    }
  }
  return [words.toString().trim(), ...nested].join('\n');
}

String _inline(md.Node node) {
  if (node is! md.Element) return node.textContent;
  switch (node.tag) {
    case 'input': // a task's box
      return node.attributes['checked'] == 'true' ? '[x] ' : '[ ] ';
    case 'img':
      return node.attributes['alt'] ?? '';
    case 'br':
      return '\n';
    case 'a':
      final words = (node.children ?? const <md.Node>[]).map(_inline).join();
      final href = node.attributes['href'] ?? '';
      return href.isEmpty || href == words ? words : '$words ($href)';
  }
  return (node.children ?? const <md.Node>[]).map(_inline).join();
}
