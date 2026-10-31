package com.tangenix.podtrackio.ui.screens

import org.junit.Assert.*
import org.junit.Test

class LearningPlayerDocumentTest {
    @Test fun `only validated video identifiers reach the player document`() {
        val origin = "https://com.tangenix.podtrackio.full.debug/"
        val html = learningPlayerDocument("abcdefghijk", -10, false, origin)
        assertTrue(html.contains("start:0"))
        assertTrue(html.contains("origin:'$origin'"))
        assertTrue(html.contains("strict-origin-when-cross-origin"))
        assertTrue(learningPlayerDocument("abcdefghijk", Int.MAX_VALUE, true, origin).contains("start:604800"))
        assertThrows(IllegalArgumentException::class.java) { learningPlayerDocument("abcdefghijk", 0, false, "';alert(1)//") }
        assertTrue(html.contains("player.getPlayerState()===1"))
        assertTrue(html.contains("var player, wantPlay=false"))
        assertThrows(IllegalArgumentException::class.java) { learningPlayerDocument("';alert(1)//", 0, true, origin) }
    }
}
