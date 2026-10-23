package com.tangenix.podtrackio.ui.play

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

enum class BurstStyle { CONFETTI, CANNONS, SPARKS, GEMS, ICE }

private data class Particle(
    val ox: Float, val oy: Float, val vx: Float, val vy: Float, val gravity: Float, val spin: Float, val angle: Float,
    val size: Float, val color: Color, val shape: Int, val life: Float, val wobble: Float,
)

val defaultConfetti = listOf(Palette.flame, Palette.gold, Palette.success, Palette.gem, Palette.purple, Palette.error)

/** Physics particles in one Canvas, restarted whenever `trigger` changes (0 = idle). */
@Composable
fun ParticleBurst(trigger: Int, modifier: Modifier = Modifier, style: BurstStyle = BurstStyle.CONFETTI, count: Int = 70, colors: List<Color> = defaultConfetti) {
    if (reduceMotionEnabled()) return
    var particles by remember { mutableStateOf(emptyList<Particle>()) }
    var time by remember { mutableFloatStateOf(-1f) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        val r = Random(System.nanoTime())
        fun range(a: Float, b: Float) = a + r.nextFloat() * (b - a)
        particles = List(count) { i ->
            when (style) {
                BurstStyle.CANNONS -> {
                    val left = i % 2 == 0
                    val a = if (left) range(-PI.toFloat() * .42f, -PI.toFloat() * .28f) else range(-PI.toFloat() * .72f, -PI.toFloat() * .58f)
                    val sp = range(1.3f, 2.1f)
                    Particle(if (left) .02f else .98f, 1f, cos(a) * sp * .55f, sin(a) * sp, 1.9f, range(-10f, 10f), range(0f, 6.28f), range(9f, 15f), colors[i % colors.size], r.nextInt(3), range(1.8f, 2.6f), range(5f, 11f))
                }
                BurstStyle.CONFETTI -> {
                    val a = range(-PI.toFloat() * .85f, -PI.toFloat() * .15f); val sp = range(.6f, 1.35f)
                    Particle(.5f + range(-.08f, .08f), .55f, cos(a) * sp * .6f, sin(a) * sp, 1.5f, range(-8f, 8f), range(0f, 6.28f), range(8f, 14f), colors[i % colors.size], r.nextInt(3), range(1.6f, 2.4f), range(4f, 10f))
                }
                else -> {
                    val a = range(0f, 2 * PI.toFloat()); val sp = if (style == BurstStyle.GEMS) range(.35f, .7f) else range(.45f, .9f)
                    Particle(.5f, .5f, cos(a) * sp, sin(a) * sp, if (style == BurstStyle.SPARKS) .25f else .9f, if (style == BurstStyle.SPARKS) 0f else range(-6f, 6f),
                        if (style == BurstStyle.SPARKS) a + PI.toFloat() / 2 else range(0f, 6.28f), if (style == BurstStyle.GEMS) range(9f, 15f) else range(6f, 11f),
                        colors[i % colors.size], r.nextInt(2), range(.7f, 1.2f), 0f)
                }
            }
        }
        val start = withFrameNanos { it }
        val longest = particles.maxOf { it.life }
        while (isActive) {
            val t = withFrameNanos { (it - start) / 1e9f }
            time = t
            if (t > longest) { time = -1f; break }
        }
    }
    Canvas(modifier) {
        val t = time
        if (t < 0f) return@Canvas
        particles.forEach { p ->
            if (t >= p.life) return@forEach
            val x = (p.ox + p.vx * t + sin(t * p.wobble) * .012f) * size.width
            val y = (p.oy + p.vy * t + .5f * p.gravity * t * t) * size.height
            val fade = ((p.life - t) / (p.life * .35f)).coerceIn(0f, 1f)
            val s = p.size * density / 2.2f
            translate(x, y) {
                rotate(Math.toDegrees((p.angle + p.spin * t).toDouble()).toFloat(), Offset.Zero) {
                    when {
                        style == BurstStyle.GEMS -> {
                            val path = Path().apply { moveTo(0f, -s); lineTo(s * .75f, -s * .2f); lineTo(0f, s); lineTo(-s * .75f, -s * .2f); close() }
                            drawPath(path, Palette.gem, alpha = fade)
                        }
                        style == BurstStyle.ICE -> {
                            val path = Path().apply { moveTo(-s * .5f, -s * .6f); lineTo(s * .6f, -s * .3f); lineTo(s * .2f, s * .7f); close() }
                            drawPath(path, if (p.shape == 0) Palette.ice else Color.White, alpha = fade)
                        }
                        style == BurstStyle.SPARKS -> {
                            val len = s * (1.2f + 2.2f * fade)
                            drawRoundRect(p.color, Offset(-s * .18f, -len / 2), Size(s * .36f, len), CornerRadius(s * .18f), alpha = fade)
                        }
                        p.shape == 0 -> {
                            val flip = abs(cos(t * p.wobble))
                            drawRoundRect(p.color, Offset(-s * .5f * flip, -s * .3f), Size(s * flip, s * .6f), CornerRadius(3f), alpha = fade)
                        }
                        p.shape == 1 -> drawCircle(p.color, s * .35f, Offset.Zero, alpha = fade)
                        else -> {
                            val path = Path()
                            for (i in 0 until 10) {
                                val rr = if (i % 2 == 0) s * .55f else s * .25f
                                val a = i * PI / 5 - PI / 2
                                val pt = Offset((cos(a) * rr).toFloat(), (sin(a) * rr).toFloat())
                                if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y)
                            }
                            path.close(); drawPath(path, p.color, alpha = fade)
                        }
                    }
                }
            }
        }
    }
}

/** Embers drifting up from a flame; deterministic per index. */
@Composable
fun EmberField(active: Boolean, modifier: Modifier = Modifier, count: Int = 18) {
    if (!active || reduceMotionEnabled()) return
    val time by produceState(0f) { val start = withFrameNanos { it }; while (isActive) value = withFrameNanos { (it - start) / 1e9f } }
    val colors = listOf(Palette.flame, Palette.gold, Palette.flameDeep)
    Canvas(modifier) {
        for (i in 0 until count) {
            val seed = i * 12.9898f
            val speed = .35f + (sin(seed) * .5f + .5f) * .45f
            val phase = ((time * speed + (sin(seed * 3.1f) * .5f + .5f)) % 1f)
            val x = size.width * (.5f + sin(seed * 7.3f) * .32f + sin(time * 2 + seed) * .04f * phase)
            val y = size.height * (.95f - phase * .95f)
            val r = (2.2f + (sin(seed * 5.7f) * .5f + .5f) * 3.2f) * (1 - phase * .6f) * density / 2f
            drawCircle(colors[i % 3], r, Offset(x, y), alpha = sin(PI.toFloat() * phase) * .9f)
        }
    }
}

/** Expanding ring marking the instant something lands. */
@Composable
fun ShockwaveRing(trigger: Int, color: Color, modifier: Modifier = Modifier) {
    val progress = remember { Animatable(1f) }
    LaunchedEffect(trigger) { if (trigger > 0) { progress.snapTo(0f); progress.animateTo(1f, tween(550)) } }
    Canvas(modifier) {
        val p = progress.value
        if (p >= 1f) return@Canvas
        val eased = 1 - (1 - p) * (1 - p)
        drawCircle(color, radius = size.minDimension / 2 * (.25f + 1.65f * eased), alpha = .9f * (1 - p), style = Stroke(width = (26f - 25f * eased) * density / 2))
    }
}

/** Full-screen flash for the brightest beats. */
@Composable
fun ImpactFlash(trigger: Int, color: Color = Color.White) {
    val alpha = remember { Animatable(0f) }
    LaunchedEffect(trigger) { if (trigger > 0) { alpha.snapTo(.75f); alpha.animateTo(0f, tween(320, easing = LinearEasing)) } }
    if (alpha.value > 0f) Canvas(Modifier.fillMaxSize()) { drawRect(color, alpha = alpha.value) }
}

/** Slowly rotating sunburst behind flames, chests and badges. */
@Composable
fun Rays(color: Color, modifier: Modifier = Modifier) {
    val time by produceState(0f) { val start = withFrameNanos { it }; while (isActive) value = withFrameNanos { (it - start) / 1e9f } }
    val reduce = reduceMotionEnabled()
    Canvas(modifier) {
        val c = center; val radius = size.minDimension / 2
        rotate(if (reduce) 0f else time * 18f, c) {
            for (i in 0 until 12) {
                val a = i / 12.0 * 2 * PI; val spread = .13
                val path = Path().apply {
                    moveTo(c.x, c.y)
                    lineTo(c.x + (cos(a - spread) * radius).toFloat(), c.y + (sin(a - spread) * radius).toFloat())
                    lineTo(c.x + (cos(a + spread) * radius).toFloat(), c.y + (sin(a + spread) * radius).toFloat()); close()
                }
                drawPath(path, Brush.radialGradient(listOf(color.copy(alpha = .45f), color.copy(alpha = 0f)), c, radius))
            }
        }
    }
}
