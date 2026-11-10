package io.github.mfozmen.notelore.wear

import android.content.Context
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/** Messages to and from the other side of the Wearable Data Layer: the paired phone. */
interface DataLayer {
    /** Sends [text] on [path] to every connected node; false when none is connected. */
    suspend fun send(path: String, text: String): Boolean

    /** Calls [onMessage] for each message that arrives, until the returned function is called. */
    fun listen(onMessage: (path: String, text: String) -> Unit): () -> Unit
}

/** The real [DataLayer] over Play services' MessageClient; thin, so JVM tests use a fake. */
class MessageClientDataLayer(context: Context) : DataLayer {
    private val nodes = Wearable.getNodeClient(context)
    private val messages = Wearable.getMessageClient(context)

    override suspend fun send(path: String, text: String): Boolean {
        val connected = nodes.connectedNodes.await()
        for (node in connected) messages.sendMessage(node.id, path, text.encodeToByteArray()).await()
        return connected.isNotEmpty()
    }

    override fun listen(onMessage: (path: String, text: String) -> Unit): () -> Unit {
        val listener = MessageClient.OnMessageReceivedListener { onMessage(it.path, it.data.decodeToString()) }
        messages.addListener(listener)
        return { messages.removeListener(listener) }
    }
}
