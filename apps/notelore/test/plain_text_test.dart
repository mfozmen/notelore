import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/plain_text.dart';

void main() {
  test('an answer copies as words a messenger shows as they are (#335)', () {
    expect(plainText('**Merhaba!**\nİkinci satır.'), 'Merhaba!\nİkinci satır.');
    expect(
      plainText(
        '# Mopsos\n\nSaved to **Mopsos**, _today_.\n\nDecisions so far:\n- Database: SQLite\n- Hosting: Fly.io',
      ),
      'Mopsos\n\nSaved to Mopsos, today.\n\nDecisions so far:\n- Database: SQLite\n- Hosting: Fly.io',
    );
    expect(plainText('1. First\n2. Second'), '1. First\n2. Second');
  });

  test('a link keeps where it goes; code, quotes and images keep their words', () {
    expect(
      plainText('See [the docs](https://example.com/d).'),
      'See the docs (https://example.com/d).',
    );
    expect(plainText('<https://example.com>'), 'https://example.com');
    expect(plainText('Use `SQLite` here.'), 'Use SQLite here.');
    expect(plainText('```\ncache.ttl = 24h\n```'), 'cache.ttl = 24h');
    expect(plainText('> Keep the old cache.'), 'Keep the old cache.');
    expect(plainText('Done. ![a chart](https://evil.example/p.png)'), 'Done. a chart');
    expect(plainText('- a\n  - b'), '- a\n  - b');
    expect(plainText('3. Third\n4. Fourth'), '3. Third\n4. Fourth');
    expect(plainText('Line one  \nLine two'), 'Line one\nLine two');
    expect(plainText('<div>raw</div>'), '<div>raw</div>');
    expect(plainText(''), '');
  });
}
