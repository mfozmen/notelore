package io.github.mfozmen.notelore.wear

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A [DataLayer] in memory: what was sent, and messages handed in as if the phone sent them. */
class FakeDataLayer(var connected: Boolean = true) : DataLayer {
    val sent = mutableListOf<Pair<String, String>>()
    private val listeners = mutableListOf<(String, String) -> Unit>()

    override suspend fun send(path: String, text: String): Boolean {
        if (!connected) return false
        sent += path to text
        return true
    }

    override fun listen(onMessage: (path: String, text: String) -> Unit): () -> Unit {
        listeners += onMessage
        return { listeners -= onMessage }
    }

    fun receive(path: String, text: String) = listeners.toList().forEach { it(path, text) }
}

class DataLayerTest {
    @Test
    fun sendReachesTheOtherSideOnlyWhileConnected() = runTest {
        val layer = FakeDataLayer()
        assertTrue(layer.send("/notelore/say", "buy milk"))
        layer.connected = false
        assertFalse(layer.send("/notelore/say", "lost"))
        assertEquals(listOf("/notelore/say" to "buy milk"), layer.sent)
    }

    @Test
    fun messagesArriveUntilTheListenerStops() {
        val layer = FakeDataLayer()
        val heard = mutableListOf<Pair<String, String>>()
        val stop = layer.listen { path, text -> heard += path to text }
        layer.receive("/notelore/answer", "Postgres")
        stop()
        layer.receive("/notelore/answer", "not heard")
        assertEquals(listOf("/notelore/answer" to "Postgres"), heard)
    }
}
