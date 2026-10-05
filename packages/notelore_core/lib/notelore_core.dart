/// Notelore's shared core in pure Dart: note format, store, search index, sync,
/// LLM providers and the agent. The port from Python lands milestone by milestone (#60).
library;

export 'src/agent.dart' show Agent, defaultMaxTurns, systemPrompt;
export 'src/i18n.dart' show sectionHeading, sectionHeadings, sectionKey;
export 'src/paths.dart' show NotelorePaths;
export 'src/providers/base.dart'
    show
        AgentResponse,
        Block,
        LlmProvider,
        Message,
        ProviderSpec,
        Tool,
        findProvider,
        providerSpecs;
export 'src/providers/http.dart' show HttpError, NetworkError, Transport, defaultTransport;
export 'src/providers/ollama.dart' show ollamaHost;
export 'src/providers/providers.dart' show createProvider;
export 'src/providers/validator.dart'
    show KeyValidationError, TransientValidationError, validateKey;
export 'src/store/format.dart'
    show
        Decision,
        Entry,
        Note,
        NoteEntry,
        NotANote,
        Raw,
        Section,
        Todo,
        isoDate,
        parse,
        parseIsoDate,
        serialize;
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
export 'src/sync/engine.dart' show Remote, RemoteFile, SyncReport, sync;
export 'src/sync/manifest.dart' show Manifest, ManifestEntry, checkedRel, contentHash;
export 'src/sync/merge.dart'
    show
        Clean,
        Conflict,
        MergePart,
        Merged,
        Resolver,
        SyncAction,
        UnresolvedConflicts,
        autoResolve,
        decide,
        threeWay;
export 'src/sync/resolve.dart' show Ask, ModelResolver, askProvider;
export 'src/tools.dart' show Toolbox, noteTools;
