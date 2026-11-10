package io.github.mfozmen.notelore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchQueueTest {
    private var stored = mutableListOf<WatchEntry>()
    private val queue = WatchQueue(load = { stored.toList() }, save = { stored = it.toMutableList() })

    @Test
    fun `keeps the spoken messages in order`() {
        queue.add("bir", id = "1")
        queue.add("iki", id = "2")
        assertEquals(listOf("1", "2"), queue.pending.map { it.id })
        assertEquals(listOf("bir", "iki"), queue.pending.map { it.text })
    }

    @Test
    fun `survives a restart`() {
        queue.add("bir", id = "1")
        queue.markSent("1")
        val afterRestart = WatchQueue(load = { stored.toList() }, save = { stored = it.toMutableList() })
        assertEquals(listOf("bir"), afterRestart.pending.map { it.text })
        assertTrue(afterRestart.pending.single().sent)
    }

    @Test
    fun `leaves the queue only when the phone answers`() {
        queue.add("bir", id = "1")
        queue.markSent("1")
        assertEquals(1, queue.pending.size)
        queue.answer("1", "Kaydettim.")
        assertEquals(0, queue.pending.size)
        assertEquals("Kaydettim.", queue.entries.single().answer)
    }
}
