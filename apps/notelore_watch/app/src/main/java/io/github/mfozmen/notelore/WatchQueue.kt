package io.github.mfozmen.notelore

import java.util.UUID

/** One message spoken on the watch, with the answer once the phone sends it. */
data class WatchEntry(
    val id: String,
    val text: String,
    val answer: String?,
    val sent: Boolean,
    val status: String? = null,
)

/**
 * The watch's queue (#839): what was said while the phone was away, in order,
 * kept across restarts; an entry leaves the queue only when the phone's answer
 * confirms it. Plain Kotlin over a store, so the order and survival are tested
 * without a watch.
 */
class WatchQueue(
    private val load: () -> List<WatchEntry>,
    private val save: (List<WatchEntry>) -> Unit,
) {
    val entries: List<WatchEntry> get() = load()

    /** Still waiting for the phone: the visible queue. */
    val pending: List<WatchEntry> get() = load().filter { it.answer == null }

    fun add(text: String, id: String = UUID.randomUUID().toString()): WatchEntry {
        val entry = WatchEntry(id, text, null, sent = false)
        save(load() + entry)
        return entry
    }

    fun markSent(id: String) {
        save(load().map { if (it.id == id) it.copy(sent = true) else it })
    }

    fun answer(id: String, answer: String) {
        save(load().map { if (it.id == id) it.copy(answer = answer, status = null) else it })
    }

    /// A reason the turn did not run: shown, but the message stays queued.
    fun status(id: String, status: String) {
        save(load().map { if (it.id == id && it.answer == null) it.copy(status = status) else it })
    }
}
