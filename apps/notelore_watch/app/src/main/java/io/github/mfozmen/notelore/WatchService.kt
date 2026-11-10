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
        WatchStore.queue(this).answer(payload.optString("id"), payload.optString("answer"))
    }

    override fun onPeerConnected(peer: Node) {
        WatchStore.flush(this)
    }
}
