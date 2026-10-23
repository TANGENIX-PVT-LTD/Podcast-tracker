package com.tangenix.podtrackio.ui.screens

import org.junit.Assert.*
import org.junit.Test

class LearningPlayerDocumentTest {
    @Test fun `only validated video identifiers reach the player document`() {
        val html = learningPlayerDocument("abcdefghijk", -10, false)
        assertTrue(html.contains("start:0"))
        assertTrue(html.contains("player.getPlayerState()===1"))
        assertTrue(html.contains("var player, wantPlay=false"))
        assertThrows(IllegalArgumentException::class.java) { learningPlayerDocument("';alert(1)//", 0, true) }
    }
}
