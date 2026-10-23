package com.tangenix.podtrackio.ui.play

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sin
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.text.font.FontWeight

enum class EchoMood { IDLE, HAPPY, CHEER, PROUD, WORRIED, SLEEPY, FROZEN, THINKING, TALKING }

/** Echo's geometry in a 200×200 design space. Mirrors EchoSpec.swift exactly. */
object EchoSpec {
    const val body = "M100 34 C146 34 170 66 172 110 C174 152 144 180 100 180 C56 180 26 152 28 110 C30 66 54 34 100 34 Z"
    const val band = "M30 104 C30 -6 170 -6 170 104"
    val happyEyes = listOf("M64 104 Q80 86 96 104", "M104 104 Q120 86 136 104")
    val closedEyes = listOf("M64 102 Q80 110 96 102", "M104 102 Q120 110 136 102")
    val brows = listOf("M66 72 Q80 65 94 72", "M106 72 Q120 65 134 72")
    val soundArcs = listOf("M192 92 Q200 110 192 128", "M200 82 Q212 110 200 138", "M8 92 Q0 110 8 128", "M0 82 Q-12 110 0 138")
    const val mouthSmile = "M86 130 Q100 145 114 130"
    const val mouthGrin = "M82 128 Q100 162 118 128 Q100 136 82 128 Z"
    const val mouthFlat = "M90 137 L110 137"
    const val mouthWorried = "M87 141 Q100 129 113 141"
    const val mouthSmirk = "M87 133 Q104 145 117 127"
    const val mouthFrozen = "M85 136 L92.5 131 L100 136 L107.5 131 L115 136"
    const val mouthSleepy = "M93 138 Q100 142 107 138"
    val eyes = listOf(Offset(80f, 100f), Offset(120f, 100f))
    val cups = listOf(Rect(12f, 82f, 46f, 138f), Rect(154f, 82f, 188f, 138f))
    val pads = listOf(Rect(36f, 90f, 50f, 130f), Rect(150f, 90f, 164f, 130f))
}

private fun svg(d: String): Path = PathParser().parsePathString(d).toPath()

private object EchoPaths {
    val body = svg(EchoSpec.body)
    val band = svg(EchoSpec.band)
    val happyEyes = EchoSpec.happyEyes.map(::svg)
    val closedEyes = EchoSpec.closedEyes.map(::svg)
    val brows = EchoSpec.brows.map(::svg)
    val arcs = EchoSpec.soundArcs.map(::svg)
    val smile = svg(EchoSpec.mouthSmile); val grin = svg(EchoSpec.mouthGrin); val flat = svg(EchoSpec.mouthFlat)
    val worried = svg(EchoSpec.mouthWorried); val smirk = svg(EchoSpec.mouthSmirk); val frozen = svg(EchoSpec.mouthFrozen); val sleepy = svg(EchoSpec.mouthSleepy)
}

@Composable
private fun frameTime(paused: Boolean): State<Float> = produceState(0f, paused) {
    if (paused) return@produceState
    val start = withFrameNanos { it }
    while (isActive) value = withFrameNanos { (it - start) / 1e9f } + 1000f
}

/** Echo, drawn and animated procedurally: breathing, blinking, glancing, hopping and talking. */
@Composable
fun Echo(mood: EchoMood = EchoMood.IDLE, size: Dp = 120.dp, tint: Color = MaterialTheme.colorScheme.primary, modifier: Modifier = Modifier) {
    val t by frameTime(reduceMotionEnabled())
    Canvas(modifier.size(size)) {
        val scale = this.size.minDimension / 232f
        withTransform({ scale(scale, scale, Offset.Zero); translate(16f, 14f) }) { drawEcho(mood, t, if (mood == EchoMood.FROZEN) Palette.ice else tint) }
    }
}

private fun DrawScope.drawEcho(mood: EchoMood, t: Float, base: Color) {
    val ink = Palette.ink
    val top = base.lightened(.25f); val shade = base.shaded(.25f)
    val breathe = sin(t * 2 * Math.PI.toFloat() / 2.4f)
    var hop = 0f; var sx = 1f; var sy = 1f
    if (mood == EchoMood.CHEER) {
        val p = (t / .62f) % 1f
        hop = sin(Math.PI.toFloat() * p)
        val ground = p < .1f || p > .9f
        sx = if (ground) 1.07f else .97f; sy = if (ground) .92f else 1.04f
    } else if (mood == EchoMood.PROUD) { sx = 1.02f; sy = 1.03f }
    val shiver = when (mood) { EchoMood.FROZEN -> sin(t * 47) * 1.1f; EchoMood.WORRIED -> sin(t * 31) * .5f; else -> 0f }
    val tilt = when (mood) { EchoMood.PROUD -> -4f; EchoMood.THINKING -> 5f; EchoMood.TALKING -> sin(t * 2.1f) * 2.5f; else -> 0f }

    val shadowW = 110f * (1 - hop * .35f)
    drawOval(Color.Black.copy(alpha = .10f * (1 - hop * .5f)), Offset(100 - shadowW / 2, 183f), Size(shadowW, 12f))

    withTransform({
        translate(shiver, -hop * 18f)
        rotate(tilt, Offset(100f, 180f))
        scale(sx * (1 - .012f * breathe), sy * (1 + .025f * breathe), Offset(100f, 180f))
    }) {
        listOf(Offset(78f, 180f), Offset(122f, 180f)).forEach { drawOval(shade, it - Offset(17f, 8f), Size(34f, 16f)) }
        drawPath(EchoPaths.body, Brush.verticalGradient(listOf(top, base), 34f, 180f))
        clipPath(EchoPaths.body) {
            drawOval(Color.White.copy(alpha = .10f), Offset(50f, 122f), Size(100f, 68f))
            drawOval(Color.White.copy(alpha = .35f), Offset(55f, 54f), Size(30f, 16f))
        }
        translate(0f, sin(t * 2 * Math.PI.toFloat() / 2.4f - .6f) * 1.4f) {
            drawPath(EchoPaths.band, ink, style = Stroke(13f, cap = StrokeCap.Round))
            drawPath(EchoPaths.band, Color.White.copy(alpha = .15f), style = Stroke(3f, cap = StrokeCap.Round))
            EchoSpec.pads.forEach { drawRoundRect(ink, it.topLeft, it.size, androidx.compose.ui.geometry.CornerRadius(6f)) }
            EchoSpec.cups.forEach { cup ->
                drawRoundRect(Palette.flameDeep, cup.topLeft + Offset(0f, 4f), cup.size, androidx.compose.ui.geometry.CornerRadius(15f))
                drawRoundRect(Palette.flame, cup.topLeft, cup.size, androidx.compose.ui.geometry.CornerRadius(15f))
                drawRoundRect(Color.White.copy(alpha = .35f), Offset(cup.center.x - 4, cup.top + 8), Size(8f, 14f), androidx.compose.ui.geometry.CornerRadius(4f))
            }
            if (mood in setOf(EchoMood.TALKING, EchoMood.CHEER, EchoMood.HAPPY)) EchoPaths.arcs.forEachIndexed { i, arc ->
                val phase = (t * 1.6f - (i % 2) * .35f) % 1f
                drawPath(arc, Palette.flame.copy(alpha = .75f * (1 - phase)), style = Stroke(4.5f, cap = StrokeCap.Round))
            }
        }
        drawFace(mood, t, ink)
    }
    if (mood == EchoMood.THINKING) listOf(Triple(156f, 30f, 4f), Triple(168f, 17f, 6f), Triple(185f, 4f, 8.5f)).forEachIndexed { i, (x, y, r) ->
        val rr = r * (1 + .08f * sin(t * 4 - i))
        drawCircle(Color.White, rr, Offset(x, y)); drawCircle(ink.copy(alpha = .7f), rr, Offset(x, y), style = Stroke(2.5f))
    }
}

private fun DrawScope.drawFace(mood: EchoMood, t: Float, ink: Color) {
    val blush = if (mood == EchoMood.WORRIED || mood == EchoMood.FROZEN) .2f else .5f
    listOf(Offset(62f, 127f), Offset(138f, 127f)).forEach { drawOval(Color(0xFFFF8FAB).copy(alpha = blush), it - Offset(10f, 6f), Size(20f, 12f)) }
    when (mood) {
        EchoMood.CHEER -> EchoPaths.happyEyes.forEach { drawPath(it, ink, style = Stroke(7f, cap = StrokeCap.Round)) }
        EchoMood.SLEEPY -> EchoPaths.closedEyes.forEach { drawPath(it, ink, style = Stroke(6f, cap = StrokeCap.Round)) }
        else -> {
            val lid = blink(t)
            val look = when (mood) {
                EchoMood.THINKING -> Offset(4.8f, -6.3f)
                EchoMood.WORRIED, EchoMood.FROZEN -> Offset(sin(t * 3) * 1.5f, 2.8f)
                else -> Offset(sin(t * .6f) * 2.7f + if (sin(t * .37f) > .92f) 5.4f else 0f, kotlin.math.cos(t * .45f) * 2.1f)
            }
            EchoSpec.eyes.forEach { c ->
                scale(1f, (1 - lid).coerceAtLeast(.08f), c) {
                    drawOval(Color.White, c - Offset(18f, 21f), Size(36f, 42f))
                    drawOval(ink.copy(alpha = .12f), c - Offset(18f, 21f), Size(36f, 42f), style = Stroke(1.5f))
                    val p = c + look + Offset(0f, if (mood == EchoMood.PROUD) -2f else 0f)
                    val r = if (mood == EchoMood.WORRIED || mood == EchoMood.FROZEN) 8f else 10f
                    drawCircle(ink, r, p)
                    drawCircle(Color.White, 3.5f, p + Offset(-3.5f, -4.5f))
                    drawCircle(Color.White.copy(alpha = .85f), 1.6f, p + Offset(4f, 4.5f))
                }
            }
        }
    }
    val (tiltDeg, lift) = when (mood) {
        EchoMood.WORRIED, EchoMood.FROZEN -> -14f to -2f
        EchoMood.PROUD -> 9f to 2f
        EchoMood.CHEER, EchoMood.HAPPY -> 0f to -5f
        EchoMood.THINKING -> -6f to -3f
        EchoMood.SLEEPY -> 0f to 3f
        else -> 0f to 0f
    }
    EchoPaths.brows.forEachIndexed { i, brow ->
        val pivot = if (i == 0) Offset(80f, 70f) else Offset(120f, 70f)
        val extra = if (mood == EchoMood.THINKING && i == 1) -4f else 0f
        withTransform({ translate(0f, lift + extra); rotate(tiltDeg * if (i == 0) 1 else -1, pivot) }) {
            drawPath(brow, ink, style = Stroke(5.5f, cap = StrokeCap.Round))
        }
    }
    val stroke = Stroke(5.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    when (mood) {
        EchoMood.IDLE -> drawPath(EchoPaths.smile, ink, style = stroke)
        EchoMood.HAPPY, EchoMood.CHEER -> {
            drawPath(EchoPaths.grin, ink)
            clipPath(EchoPaths.grin) { drawOval(Color(0xFFFF6B8A), Offset(91f, 142f), Size(18f, 10f)) }
        }
        EchoMood.PROUD -> drawPath(EchoPaths.smirk, ink, style = stroke)
        EchoMood.WORRIED -> drawPath(EchoPaths.worried, ink, style = stroke)
        EchoMood.SLEEPY -> drawPath(EchoPaths.sleepy, ink, style = stroke)
        EchoMood.FROZEN -> drawPath(EchoPaths.frozen, ink, style = stroke)
        EchoMood.THINKING -> drawPath(EchoPaths.flat, ink, style = stroke)
        EchoMood.TALKING -> when ((t * 9).toInt() % 4) {
            0 -> drawOval(ink, Offset(93f, 129f), Size(14f, 18f))
            2 -> drawOval(ink, Offset(91f, 131.5f), Size(18f, 11f))
            else -> drawPath(EchoPaths.smile, ink, style = stroke)
        }
    }
}

private fun blink(t: Float): Float {
    val window = 3.7f
    val cycle = floor(t / window)
    val offset = abs((sin(cycle * 12.9898f) * 43758.5453f) % 1f)
    val phase = t - cycle * window - offset * 2.8f
    return if (phase > 0 && phase < .16f) sin(Math.PI.toFloat() * phase / .16f) * .95f else 0f
}

/** Echo with a chunky speech bubble that pops in whenever the line changes. */
@Composable
fun EchoSays(mood: EchoMood, text: String, modifier: Modifier = Modifier, size: Dp = 86.dp) {
    var pop by remember { mutableIntStateOf(0) }
    LaunchedEffect(text) { pop++ }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Echo(mood, size)
        Text(text, style = playType(16, FontWeight.Bold), color = if (isDarkSurface()) Color.White else Palette.ink,
            modifier = Modifier.slam(pop, 0.6f).chunkyCard(16.dp, lip = 3.dp).padding(horizontal = 14.dp, vertical = 11.dp))
    }
}

