package com.tangenix.podtrackio.ui.play

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.pow

enum class ChunkyKind { PRIMARY, SECONDARY, SUCCESS, DANGER, GEM, FLAME, GOLD }

/** 3D button: the face drops onto its lip when pressed and springs back past rest on release. */
@Composable
fun ChunkyButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ChunkyKind = ChunkyKind.PRIMARY,
    small: Boolean = false,
    fullWidth: Boolean = true,
    enabled: Boolean = true,
    icon: ImageVector? = null,
) {
    val tint = MaterialTheme.colorScheme.primary
    val dark = isDarkSurface()
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val depth = if (small) 3.dp else 5.dp
    val face = if (!enabled) (if (dark) Color(0xFF37464F) else Color(0xFFE5E5E5)) else when (kind) {
        ChunkyKind.PRIMARY -> tint; ChunkyKind.SECONDARY -> cardSurface(); ChunkyKind.SUCCESS -> Palette.success
        ChunkyKind.DANGER -> Palette.error; ChunkyKind.GEM -> Palette.gem; ChunkyKind.FLAME -> Palette.flame; ChunkyKind.GOLD -> Palette.gold
    }
    val lip = if (!enabled) (if (dark) Color(0xFF2A363D) else Color(0xFFCECECE)) else when (kind) {
        ChunkyKind.PRIMARY -> tint.shaded(); ChunkyKind.SECONDARY -> if (dark) Color.Black.copy(alpha = .5f) else Color(0xFFE5E5E5)
        ChunkyKind.SUCCESS -> Palette.successLip; ChunkyKind.DANGER -> Palette.errorLip; ChunkyKind.GEM -> Palette.gemLip
        ChunkyKind.FLAME -> Palette.flameDeep; ChunkyKind.GOLD -> Palette.goldLip
    }
    val fg = if (!enabled) Palette.ash else when (kind) { ChunkyKind.SECONDARY -> if (dark) Color.White else tint; ChunkyKind.GOLD -> Palette.ink; else -> Color.White }
    val press by animateFloatAsState(if (pressed && enabled) 1f else 0f,
        if (pressed) tween(60) else spring(dampingRatio = 0.42f, stiffness = 700f), label = "press")
    LaunchedEffect(pressed) { if (enabled) PlayFeedback.play(if (pressed) Cue.PRESS else Cue.RELEASE, sound = false) }
    val radius = if (small) 12.dp else 16.dp
    Box(
        modifier
            .then(if (fullWidth) Modifier.fillMaxWidth() else Modifier)
            .padding(bottom = depth)
            .drawBehind { drawRoundRect(lip, topLeft = Offset(0f, depth.toPx()), size = size, cornerRadius = CornerRadius(radius.toPx())) }
            .graphicsLayer { translationY = press * depth.toPx(); scaleX = 1f - press * 0.03f; scaleY = 1f - press * 0.03f }
            .clip(RoundedCornerShape(radius))
            .background(face)
            .drawBehind {
                // Glossy top highlight: the detail that makes the face read as a solid object.
                if (kind != ChunkyKind.SECONDARY && enabled) drawRoundRect(Color.White.copy(alpha = .22f), Offset(size.width * .075f, 5.dp.toPx()),
                    Size(size.width * .85f, 4.dp.toPx()), CornerRadius(2.dp.toPx()))
            }
            .then(if (kind == ChunkyKind.SECONDARY) Modifier.border(2.dp, lip, RoundedCornerShape(radius)) else Modifier)
            .clickable(interaction, null, enabled = enabled, onClick = onClick)
            .padding(horizontal = if (small) 14.dp else 20.dp, vertical = if (small) 9.dp else 15.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            icon?.let { Icon(it, null, tint = fg, modifier = Modifier.size(if (small) 16.dp else 20.dp)) }
            Text(if (small) text else text.uppercase(), color = fg, style = playType(if (small) 14 else 17, if (small) FontWeight.Bold else FontWeight.Black), maxLines = 1)
        }
    }
}

/** A pressable card that sinks into its lip; selected tiles take the tint (answers, chips, quests). */
@Composable
fun ChunkyTile(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    tint: Color? = null,
    radius: Dp = 18.dp,
    enabled: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val accent = tint ?: MaterialTheme.colorScheme.primary
    val dark = isDarkSurface()
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val press by animateFloatAsState(if (pressed) 1f else 0f, if (pressed) tween(60) else spring(dampingRatio = 0.5f, stiffness = 700f), label = "tile")
    LaunchedEffect(pressed) { if (pressed) PlayFeedback.play(Cue.TAP, sound = false) }
    val surface = if (selected) (if (dark) accent.copy(alpha = .22f) else accent.lightened(.82f)) else cardSurface()
    val edge = if (selected) accent else cardEdge()
    val lip = if (selected) accent.shaded() else if (dark) Color.Black.copy(alpha = .45f) else Color(0xFFE5E5E5)
    Box(
        modifier
            .padding(bottom = 4.dp)
            .drawBehind { drawRoundRect(lip, topLeft = Offset(0f, 4.dp.toPx()), size = size, cornerRadius = CornerRadius(radius.toPx())) }
            .graphicsLayer { translationY = press * 4.dp.toPx() }
            .clip(RoundedCornerShape(radius))
            .background(surface)
            .border(2.dp, edge, RoundedCornerShape(radius))
            .clickable(interaction, null, enabled = enabled, onClick = onClick),
        content = content,
    )
}

/** Rounded bar with highlight stripe, glowing head, a shine sweep and a head bulge whenever it grows. */
@Composable
fun PlayProgressBar(value: Float, modifier: Modifier = Modifier, tint: Color = Palette.success, height: Dp = 16.dp) {
    val target = value.coerceIn(0f, 1f)
    val shown = remember { Animatable(0f) }
    val shine = remember { Animatable(-0.3f) }
    val bulge = remember { Animatable(1f) }
    var previous by remember { mutableStateOf(-1f) }
    LaunchedEffect(target) {
        val grew = previous >= 0f && target > previous
        previous = target
        launch { shown.animateTo(target, spring(dampingRatio = 0.7f, stiffness = 120f)) }
        if (grew) {
            launch { bulge.animateTo(1f, keyframes { durationMillis = 450; 1.35f at 100; 0.95f at 250 }) }
            shine.snapTo(-0.3f); shine.animateTo(1.3f, tween(700))
        }
    }
    val track = if (isDarkSurface()) Color.White.copy(alpha = .10f) else Color(0xFFE5E5E5)
    Canvas(modifier.fillMaxWidth().height(height).graphicsLayer { scaleY = bulge.value }) {
        val r = CornerRadius(size.height / 2)
        drawRoundRect(track, cornerRadius = r)
        val w = if (shown.value > 0f) maxOf(size.height, size.width * shown.value) else 0f
        if (w > 0f) {
            drawRoundRect(tint.copy(alpha = .35f), topLeft = Offset(0f, -2f), size = Size(w, size.height + 4f), cornerRadius = r)
            drawRoundRect(Brush.verticalGradient(listOf(tint.lightened(.12f), tint)), size = Size(w, size.height), cornerRadius = r)
            drawRoundRect(Color.White.copy(alpha = .3f), topLeft = Offset(size.height * .45f, size.height * .2f),
                size = Size((w - size.height * .9f).coerceAtLeast(0f), size.height * .22f), cornerRadius = CornerRadius(size.height))
            val sx = shine.value * w
            if (shine.value in 0f..1.2f) drawRoundRect(Brush.horizontalGradient(listOf(Color.Transparent, Color.White.copy(alpha = .55f), Color.Transparent), startX = sx - w * .2f, endX = sx + w * .2f),
                size = Size(w, size.height), cornerRadius = r)
        }
    }
}

/** Mechanical counter: each digit rolls to its value, rightmost first. */
@Composable
fun RollingNumber(value: Int, size: Int = 96, color: Color = Palette.flame, modifier: Modifier = Modifier) {
    val digits = value.toString().map { it.digitToInt() }
    val reduce = reduceMotionEnabled()
    Row(modifier) {
        digits.forEachIndexed { index, digit ->
            val anim = remember(digits.size, index) { Animatable(digit.toFloat()) }
            LaunchedEffect(digit) {
                delay(((digits.size - 1 - index) * 60).toLong())
                if (reduce) anim.snapTo(digit.toFloat()) else anim.animateTo(digit.toFloat(), spring(dampingRatio = 0.6f, stiffness = 260f))
            }
            val h = (size * 1.18f).dp
            Box(Modifier.height(h).clip(RoundedCornerShape(0.dp))) {
                Column(Modifier.wrapContentHeight(Alignment.Top, unbounded = true).graphicsLayer { translationY = -anim.value * h.toPx() }) {
                    (0..9).forEach { n -> Box(Modifier.height(h), contentAlignment = Alignment.Center) { Text("$n", color = color, style = playType(size)) } }
                }
            }
        }
    }
}

/** Counts up with a haptic tick every couple of steps and rising pitch; slams when it lands. */
@Composable
fun CountUpText(value: Int, size: Int = 34, color: Color = MaterialTheme.colorScheme.onSurface, suffix: String = "", modifier: Modifier = Modifier) {
    var shown by remember { mutableIntStateOf(0) }
    var landed by remember { mutableIntStateOf(0) }
    val reduce = reduceMotionEnabled()
    LaunchedEffect(value) {
        if (reduce || value == 0) { shown = value; return@LaunchedEffect }
        val steps = minOf(value, 24)
        val start = shown
        for (step in 1..steps) {
            val p = step.toFloat() / steps
            shown = start + ((value - start) * (1 - (1 - p).pow(3))).toInt()
            if (step % 2 == 0 || step == steps) {
                PlayFeedback.play(Cue.TICK, sound = false, intensity = 0.5f + p * 0.5f)
                PlayFeedback.sound(com.tangenix.podtrackio.R.raw.tick, rate = 0.9f + p * 0.6f, volume = 0.35f)
            }
            delay((900f / steps * (0.6f + p)).toLong())
        }
        shown = value; landed++
    }
    Text("$shown$suffix", color = color, style = playType(size), modifier = modifier.slam(landed, 1.25f))
}

@Composable
fun StatPill(icon: ImageVector, value: String, color: Color, modifier: Modifier = Modifier) {
    var pop by remember { mutableIntStateOf(0) }
    LaunchedEffect(value) { pop++ }
    Row(modifier.slam(if (pop > 1) pop else 0, 1.2f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
        Text(value, color = color, style = playType(15))
    }
}

// MARK: - Motion modifiers

/** Exaggerated landing: overshoot, squash, settle. Plays each time `trigger` changes (0 = idle). */
fun Modifier.slam(trigger: Int, from: Float = 2.4f): Modifier = composed {
    val sx = remember { Animatable(1f) }
    val sy = remember { Animatable(1f) }
    val alpha = remember { Animatable(1f) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        launch { sx.snapTo(from); sx.animateTo(1f, keyframes { durationMillis = 600; 0.86f at 160; 1.08f at 300 }) }
        launch { sy.snapTo(from); sy.animateTo(1f, keyframes { durationMillis = 600; 1.12f at 160; 0.95f at 300 }) }
        launch { alpha.snapTo(0f); alpha.animateTo(1f, tween(100)) }
    }
    graphicsLayer { scaleX = sx.value; scaleY = sy.value; this.alpha = alpha.value }
}

/** Squash-and-stretch hop. */
fun Modifier.hop(trigger: Int, height: Float = 26f): Modifier = composed {
    val y = remember { Animatable(0f) }
    val sx = remember { Animatable(1f) }
    val sy = remember { Animatable(1f) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        launch { y.animateTo(0f, keyframes { durationMillis = 620; 4f at 70; -height at 250; 0f at 410 }) }
        launch { sx.animateTo(1f, keyframes { durationMillis = 620; 1.18f at 70; 0.9f at 250; 1.12f at 410 }) }
        launch { sy.animateTo(1f, keyframes { durationMillis = 620; 0.82f at 70; 1.12f at 250; 0.88f at 410 }) }
    }
    graphicsLayer { translationY = y.value * density; scaleX = sx.value; scaleY = sy.value; transformOrigin = TransformOrigin(0.5f, 1f) }
}

/** Camera shake with a decaying wobble. */
fun Modifier.impactShake(trigger: Int, strength: Float = 9f): Modifier = composed {
    val x = remember { Animatable(0f) }
    LaunchedEffect(trigger) {
        if (trigger == 0) return@LaunchedEffect
        x.animateTo(0f, keyframes { durationMillis = 290; strength at 40 using LinearEasing; -strength * .8f at 90; strength * .6f at 140; -strength * .4f at 190; strength * .2f at 240 })
    }
    graphicsLayer { translationX = x.value * density }
}
