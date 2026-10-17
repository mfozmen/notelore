/// Notelore's shared core in pure Dart: note format, store, search index, sync,
/// LLM providers and the agent. The port from Python lands milestone by milestone (#60).
library;

export 'src/agent.dart'
    show Agent, TurnStopped, defaultMaxTurns, describeTool, suggestedAnswers, systemPrompt;
export 'src/i18n.dart' show sectionHeading, sectionHeadings, sectionKey;
export 'src/oauth.dart' show NotSignedIn, OAuthSignIn, SignInFailed;
export 'src/paths.dart' show NotelorePaths;
export 'src/providers/base.dart'
    show
        AgentResponse,
        Block,
        LlmProvider,
        Message,
        ProviderGroup,
        ProviderSpec,
        TokenUsage,
        Tool,
        findProvider,
        providerSpecs;
export 'src/providers/chatgpt.dart'
    show BearerToken, ChatGptProvider, PlanLimitReached, chatGptUsageUrl, listChatGptModels;
export 'src/providers/chatgpt_auth.dart' show ChatGptAuth;
export 'src/providers/http.dart' show HttpError, NetworkError, Transport, defaultTransport;
export 'src/providers/ollama.dart' show ollamaHost;
export 'src/providers/providers.dart' show createProvider;
export 'src/providers/validator.dart'
    show KeyValidationError, TransientValidationError, cheapestModel, currentModels, validateKey;
export 'src/secret.dart' show defaultIterations, hashSecret, verifySecret;
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
        ArchivedNote,
        RestoreTaken,
        archiveEntries,
        archiveFolder,
        archiveNote,
        atomicWrite,
        completeTodo,
        createNote,
        kinds,
        listArchived,
        localToday,
        markdownFiles,
        moveWithRetry,
        notePath,
        readNote,
        restoreArchived,
        recordDecision,
        slugify,
        writeNote;
export 'src/store/stale.dart' show Stale, findStaleNotes;
export 'src/store/transfer.dart'
    show ImportOutcome, Imported, LineStyle, OutlineLine, importNote, metaLine, notesHtml, outline;
export 'src/sync/drive.dart' show AccessToken, DriveRemote, driveScope;
export 'src/sync/engine.dart' show Remote, RemoteFile, SyncReport, sync;
export 'src/sync/google_auth.dart' show DriveAuth, LoopbackAuth;
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
export 'src/usage.dart'
    show
        MeteredProvider,
        Price,
        UsageCount,
        UsageMeter,
        UsageSummary,
        prices,
        pricesTaken,
        summarize;
