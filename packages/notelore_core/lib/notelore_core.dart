/// Notelore's shared core in pure Dart: note format, store, search index, sync,
/// LLM providers and the agent. The port from Python lands milestone by milestone (#60).
library;

export 'src/i18n.dart' show sectionHeading, sectionHeadings, sectionKey;
export 'src/paths.dart' show NotelorePaths;
export 'src/store/format.dart'
    show Decision, Entry, Note, NoteEntry, NotANote, Raw, Section, Todo, isoDate, parse, serialize;
export 'src/store/front_matter.dart' show dumpFrontMatter, loadFrontMatter;
export 'src/store/index.dart' show Hit, NoteIndex, NoteInfo, fts5Available;
export 'src/store/notes.dart'
    show
        Pause,
        Rename,
        activeDecision,
        addEntry,
        addTodo,
        archiveEntries,
        archiveFolder,
        archiveNote,
        atomicWrite,
        completeTodo,
        createNote,
        kinds,
        localToday,
        markdownFiles,
        moveWithRetry,
        notePath,
        readNote,
        recordDecision,
        slugify,
        writeNote;
export 'src/store/stale.dart' show Stale, findStaleNotes;
