package io.github.mfozmen.notelore

import android.content.Context
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject

/** The watch's messages in SharedPreferences, so they survive a restart. */
object WatchStore {
    private const val prefs = "notelore_watch"
    private const val key = "entries"

    fun queue(context: Context): WatchQueue = WatchQueue(
        load = { read(context) },
        save = { write(context, it) },
    )

    /** Sends every queued message not sent yet, in order, when the phone is back. */
    fun flush(context: Context) {
        val queue = queue(context)
        // Everything unanswered; the phone ignores a repeat by its id.
        val unsent = queue.pending
        if (unsent.isEmpty()) return
        Wearable.getNodeClient(context).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                for (entry in unsent) {
                    val data = JSONObject().put("id", entry.id).put("text", entry.text)
                        .toString().toByteArray()
                    Wearable.getMessageClient(context)
                        .sendMessage(node.id, "/notelore/ask", data)
                    queue.markSent(entry.id)
                }
            }
        }
    }

    /** Sends one message now, if a phone is connected; false leaves it queued. */
    fun send(context: Context, entry: WatchEntry) {
        Wearable.getNodeClient(context).connectedNodes.addOnSuccessListener { nodes ->
            if (nodes.isEmpty()) return@addOnSuccessListener
            val data = JSONObject().put("id", entry.id).put("text", entry.text)
                .toString().toByteArray()
            for (node in nodes) {
                Wearable.getMessageClient(context)
                    .sendMessage(node.id, "/notelore/ask", data)
            }
            queue(context).markSent(entry.id)
        }
    }

    private fun read(context: Context): List<WatchEntry> {
        val raw = context.getSharedPreferences(prefs, Context.MODE_PRIVATE).getString(key, null)
            ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val item = array.getJSONObject(i)
                WatchEntry(
                    id = item.getString("id"),
                    text = item.getString("text"),
                    answer = if (item.isNull("answer")) null else item.getString("answer"),
                    sent = item.optBoolean("sent"),
                    status = if (item.isNull("status")) null else item.getString("status"),
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun write(context: Context, entries: List<WatchEntry>) {
        val array = JSONArray()
        for (entry in entries) {
            array.put(
                JSONObject()
                    .put("id", entry.id)
                    .put("text", entry.text)
                    .put("answer", entry.answer)
                    .put("sent", entry.sent)
                    .put("status", entry.status),
            )
        }
        context.getSharedPreferences(prefs, Context.MODE_PRIVATE).edit()
            .putString(key, array.toString()).apply()
    }
}
