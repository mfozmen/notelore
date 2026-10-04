/// Notelore's shared core in pure Dart: note format, store, search index, sync,
/// LLM providers and the agent. The port from Python lands milestone by milestone (#60).
library;

export 'src/i18n.dart' show sectionHeading, sectionHeadings, sectionKey;
export 'src/paths.dart' show NotelorePaths;
export 'src/store/format.dart'
    show Decision, Entry, Note, NoteEntry, NotANote, Raw, Section, Todo, isoDate, parse, serialize;
export 'src/store/front_matter.dart' show dumpFrontMatter, loadFrontMatter;
