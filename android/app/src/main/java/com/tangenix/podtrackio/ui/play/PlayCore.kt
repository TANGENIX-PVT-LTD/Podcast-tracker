package com.tangenix.podtrackio.ui.play

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tangenix.podtrackio.R
import kotlinx.coroutines.delay

/** The "Play" layer, mirrored from the Apple apps' PlayTokens.swift. */
object Palette {
    val flame = Color(0xFFFF9600)
    val flameDeep = Color(0xFFFF4B00)
    val flameCore = Color(0xFFFFD54A)
    val success = Color(0xFF58CC02)
    val successLip = Color(0xFF46A302)
    val gem = Color(0xFF1CB0F6)
    val gemLip = Color(0xFF1899D6)
    val gold = Color(0xFFFFC800)
    val goldLip = Color(0xFFE5A400)
    val error = Color(0xFFFF4B4B)
    val errorLip = Color(0xFFEA2B2B)
    val ice = Color(0xFF84D8FF)
    val iceDeep = Color(0xFF49C0F8)
    val ash = Color(0xFFAFAFAF)
    val ink = Color(0xFF2B2F3A)
    val purple = Color(0xFFCE82FF)
}

object Motion {
    fun <T> snappy() = spring<T>(dampingRatio = 0.72f, stiffness = 900f)
    fun <T> bouncy() = spring<T>(dampingRatio = 0.5f, stiffness = Spring.StiffnessMediumLow)
    fun <T> gentle() = spring<T>(dampingRatio = 0.85f, stiffness = Spring.StiffnessLow)
}

fun Color.shaded(amount: Float = 0.22f) = lerp(this, Color.Black, amount)
fun Color.lightened(amount: Float) = lerp(this, Color.White, amount)

/** Rounded, heavy display type: the Duolingo voice. */
fun playType(size: Int, weight: FontWeight = FontWeight.Black) = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = weight, fontSize = size.sp, letterSpacing = 0.sp)

@Composable
fun isDarkSurface() = MaterialTheme.colorScheme.background.luminance() < 0.4f

@Composable
fun cardSurface() = if (isDarkSurface()) Color(0xFF1D2230) else Color.White

@Composable
fun cardEdge() = if (isDarkSurface()) Color.White.copy(alpha = 0.10f) else Color(0xFFE5E5E5)

/** Solid card with a 2dp border and a bottom lip: the tactile surface used everywhere. */
fun Modifier.chunkyCard(radius: Dp = 20.dp, fill: Color? = null, border: Color? = null, lip: Dp = 4.dp) = composed {
    val surface = fill ?: cardSurface()
    val edge = border ?: cardEdge()
    val lipColor = border ?: if (isDarkSurface()) Color.Black.copy(alpha = 0.45f) else Color(0xFFE5E5E5)
    this
        .padding(bottom = lip)
        .drawBehind {
            drawRoundRect(lipColor, topLeft = Offset(0f, lip.toPx()), size = size, cornerRadius = CornerRadius(radius.toPx()))
        }
        .background(surface, RoundedCornerShape(radius))
        .border(2.dp, edge, RoundedCornerShape(radius))
}

// MARK: - Feedback

enum class Cue(val sound: Int?) {
    PRESS(null), RELEASE(null), TAP(null), SELECT(R.raw.tick), TICK(R.raw.tick), POP(R.raw.pop),
    CORRECT(R.raw.correct), WRONG(R.raw.wrong), SUCCESS(null), IGNITE(R.raw.ignite), STREAK_FLIP(R.raw.streak),
    CHEST(R.raw.chest), LEVEL_UP(R.raw.levelup), FREEZE(R.raw.freeze), LAND(null), THUD(null), IMPACT(null), SWING(null),
}

/**
 * Haptics + sound with one entry point, so every visual beat can fire both on the same frame.
 * Uses VibrationEffect.Composition primitives (API 30+) for crisp Duolingo-style taps, with waveform fallbacks.
 */
object PlayFeedback {
    var hapticsEnabled = true
    var soundsEnabled = true
    private var vibrator: Vibrator? = null
    private var pool: SoundPool? = null
    private val loaded = mutableMapOf<Int, Int>()

    fun init(context: Context) {
        if (vibrator != null) return
        vibrator = if (Build.VERSION.SDK_INT >= 31) (context.getSystemService(VibratorManager::class.java))?.defaultVibrator
        else @Suppress("DEPRECATION") context.getSystemService(Vibrator::class.java)
        pool = SoundPool.Builder().setMaxStreams(8).setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        ).build()
        listOf(R.raw.tick, R.raw.pop, R.raw.correct, R.raw.wrong, R.raw.ignite, R.raw.streak, R.raw.chest, R.raw.levelup, R.raw.complete, R.raw.freeze)
            .forEach { loaded[it] = pool!!.load(context, it, 1) }
    }

    fun play(cue: Cue, sound: Boolean = true, intensity: Float = 1f) {
        if (hapticsEnabled) vibrate(cue, intensity)
        if (sound && soundsEnabled) cue.sound?.let { sound(it) }
    }

    /** rate > 1 raises pitch: count-ups climb as they near the total. */
    fun sound(res: Int, rate: Float = 1f, volume: Float = 0.85f) {
        if (!soundsEnabled) return
        val id = loaded[res] ?: return
        pool?.play(id, volume, volume, 1, 0, rate.coerceIn(0.5f, 2f))
    }

    private fun vibrate(cue: Cue, intensity: Float) {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        val s = intensity.coerceIn(0.05f, 1f)
        if (Build.VERSION.SDK_INT >= 31 && v.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_CLICK, VibrationEffect.Composition.PRIMITIVE_TICK,
                VibrationEffect.Composition.PRIMITIVE_THUD, VibrationEffect.Composition.PRIMITIVE_QUICK_RISE, VibrationEffect.Composition.PRIMITIVE_SLOW_RISE)) {
            val c = VibrationEffect.startComposition()
            val CLICK = VibrationEffect.Composition.PRIMITIVE_CLICK
            val TICK = VibrationEffect.Composition.PRIMITIVE_TICK
            val THUD = VibrationEffect.Composition.PRIMITIVE_THUD
            when (cue) {
                Cue.PRESS -> c.addPrimitive(CLICK, 0.55f * s)
                Cue.RELEASE -> c.addPrimitive(TICK, 0.4f * s)
                Cue.TAP -> c.addPrimitive(CLICK, 0.4f * s)
                Cue.SELECT, Cue.TICK -> c.addPrimitive(TICK, 0.55f * s)
                Cue.POP -> c.addPrimitive(CLICK, 0.9f * s)
                Cue.LAND -> c.addPrimitive(CLICK, 0.7f * s)
                Cue.THUD -> c.addPrimitive(THUD, 1f * s)
                Cue.SWING -> c.addPrimitive(THUD, 0.7f * s)
                Cue.IMPACT -> { c.addPrimitive(CLICK, 1f * s); c.addPrimitive(THUD, 1f * s, 10) }
                Cue.CORRECT -> { c.addPrimitive(CLICK, 0.6f * s); c.addPrimitive(CLICK, 1f * s, 90) }
                Cue.WRONG -> { c.addPrimitive(THUD, 0.9f * s); c.addPrimitive(THUD, 0.9f * s, 120) }
                Cue.SUCCESS -> { c.addPrimitive(CLICK, 0.5f * s); c.addPrimitive(CLICK, 1f * s, 120) }
                // Flame grows grey → orange for ~450ms, then pops: slow rise then a hard click.
                Cue.IGNITE -> { c.addPrimitive(VibrationEffect.Composition.PRIMITIVE_SLOW_RISE, 0.8f * s); c.addPrimitive(CLICK, 1f * s, 30) }
                Cue.STREAK_FLIP -> { c.addPrimitive(CLICK, 1f * s); c.addPrimitive(THUD, 0.7f * s, 20) }
                Cue.CHEST -> { c.addPrimitive(THUD, 0.5f * s); c.addPrimitive(THUD, 0.7f * s, 300); c.addPrimitive(THUD, 0.9f * s, 300); c.addPrimitive(CLICK, 1f * s, 280) }
                Cue.LEVEL_UP -> { c.addPrimitive(VibrationEffect.Composition.PRIMITIVE_SLOW_RISE, 0.9f * s); c.addPrimitive(CLICK, 0.6f * s, 60); c.addPrimitive(CLICK, 0.8f * s, 120); c.addPrimitive(CLICK, 1f * s, 120) }
                Cue.FREEZE -> repeat(5) { c.addPrimitive(TICK, (0.6f - it * 0.1f) * s, if (it == 0) 0 else 40) }
            }
            v.vibrate(c.compose())
        } else {
            val effect = when (cue) {
                Cue.TICK, Cue.SELECT, Cue.RELEASE -> VibrationEffect.createOneShot(8, (60 * s).toInt().coerceAtLeast(1))
                Cue.PRESS, Cue.TAP, Cue.LAND, Cue.POP -> VibrationEffect.createOneShot(14, (140 * s).toInt().coerceAtLeast(1))
                Cue.WRONG -> VibrationEffect.createWaveform(longArrayOf(0, 30, 90, 30), intArrayOf(0, (220 * s).toInt(), 0, (220 * s).toInt()), -1)
                Cue.IGNITE -> VibrationEffect.createWaveform(longArrayOf(0, 150, 150, 150, 20), intArrayOf(0, 40, 110, 200, 255), -1)
                else -> VibrationEffect.createOneShot(30, (255 * s).toInt().coerceAtLeast(1))
            }
            v.vibrate(effect)
        }
    }
}

/** One beat in a choreographed moment: its state change, haptic and sound fire together. */
data class Beat(val at: Double, val cue: Cue? = null, val sound: Boolean = true, val intensity: Float = 1f, val action: () -> Unit = {})

/** Runs beats against an absolute clock so long sequences never drift. */
suspend fun runBeats(beats: List<Beat>, reduceMotion: Boolean = false) {
    val start = System.nanoTime()
    for (beat in beats.sortedBy { it.at }) {
        if (!reduceMotion) {
            val wait = (beat.at * 1000).toLong() - (System.nanoTime() - start) / 1_000_000
            if (wait > 0) delay(wait)
        }
        beat.action()
        beat.cue?.let { PlayFeedback.play(it, beat.sound, beat.intensity) }
    }
}

@Composable
fun reduceMotionEnabled(): Boolean {
    val context = androidx.compose.ui.platform.LocalContext.current
    return android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
}
