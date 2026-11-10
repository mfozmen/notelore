package io.github.mfozmen.notelore

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/// Answers from the phone (#823), and the moment it is back: sends the queue.
class WatchService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/notelore/answer") return
        val payload = runCatching { JSONObject(String(event.data)) }.getOrNull() ?: return
        val id = payload.optString("id")
        val answer = payload.optString("answer")
        if (payload.optBoolean("status")) {
            WatchStore.queue(this).status(id, answer) // not run: it stays queued
        } else {
            WatchStore.queue(this).answer(id, answer)
        }
    }

    override fun onPeerConnected(peer: Node) {
        WatchStore.flush(this)
    }
}
