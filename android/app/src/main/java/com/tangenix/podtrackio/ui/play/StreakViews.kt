package com.tangenix.podtrackio.ui.play

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Diamond
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.MilitaryTech
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.tangenix.podtrackio.domain.*
import kotlinx.coroutines.isActive
import kotlin.math.sin

enum class FlameState { LIT, DIM, ASH, FROZEN }

/** Flame shapes in a 100×120 space, mirrored from FlameSpec in StreakFlame.swift. */
private object FlamePaths {
    val outer: Path = PathParser().parsePathString("M50 4 C60 24 90 40 92 72 C94 100 74 117 50 117 C26 117 6 100 8 72 C9 52 20 40 28 26 C32 38 38 45 44 47 C42 32 44 16 50 4 Z").toPath()
    val inner: Path = PathParser().parsePathString("M52 40 C60 56 75 66 75 87 C75 103 64 112 50 112 C36 112 25 103 25 88 C25 74 34 66 39 56 C42 64 46 67 49 67 C47 58 48 48 52 40 Z").toPath()
    val core: Path = PathParser().parsePathString("M50 72 C56 82 64 88 64 98 C64 106 58 110 50 110 C42 110 36 106 36 98 C36 90 44 84 50 72 Z").toPath()
}

/** Layered flame with noise-driven flicker and small eyes. */
@Composable
fun StreakFlame(state: FlameState, size: Dp = 64.dp, showsFace: Boolean = true, modifier: Modifier = Modifier) {
    val reduce = reduceMotionEnabled()
    val t by produceState(0f, state, reduce) {
        if (reduce || state == FlameState.ASH || state == FlameState.FROZEN) return@produceState
        val start = withFrameNanos { it }
        while (isActive) value = withFrameNanos { (it - start) / 1e9f } + 100f
    }
    Canvas(modifier.size(width = size * (100f / 122f), height = size)) {
        val s = this.size.height / 122f
        withTransform({ scale(s, s, Offset.Zero) }) { drawFlame(state, t, showsFace) }
    }
}

private fun DrawScope.drawFlame(state: FlameState, t: Float, face: Boolean) {
    val energy = when (state) { FlameState.LIT -> 1f; FlameState.DIM -> .45f; else -> 0f }
    val colors = when (state) {
        FlameState.LIT -> Triple(listOf(Palette.flameDeep, Palette.flame), listOf(Palette.flame, Palette.gold), Palette.flameCore)
        FlameState.DIM -> Triple(listOf(Color(0xFFC9733A), Color(0xFFE3A15F)), listOf(Color(0xFFE3A15F), Color(0xFFF0C987)), Color(0xFFF6E3B5))
        FlameState.ASH -> Triple(listOf(Color(0xFF9A9A9A), Palette.ash), listOf(Palette.ash, Color(0xFFCFCFCF)), Color(0xFFE5E5E5))
        FlameState.FROZEN -> Triple(listOf(Palette.iceDeep, Palette.ice), listOf(Palette.ice, Color(0xFFD3F1FF)), Color.White)
    }
    fun layer(path: Path, speed: Float, amount: Float, brush: Brush) {
        val sway = (sin(t * speed) * .6f + sin(t * speed * 2.3f + 1.7f) * .4f) * amount * energy
        val stretch = 1 + (sin(t * speed * 1.7f + .4f) * .5f + .5f) * .07f * amount * energy
        withTransform({
            translate(50f, 117f)
            transform(androidx.compose.ui.graphics.Matrix().apply { values[androidx.compose.ui.graphics.Matrix.SkewX] = sway * .18f })
            scale(1f, stretch, Offset.Zero)
            translate(-50f, -117f)
        }) { drawPath(path, brush) }
    }
    layer(FlamePaths.outer, 5.1f, 1f, Brush.verticalGradient(colors.first.reversed(), 4f, 117f))
    layer(FlamePaths.inner, 6.7f, 1.4f, Brush.verticalGradient(colors.second.reversed(), 40f, 112f))
    layer(FlamePaths.core, 8.3f, 1.8f, Brush.verticalGradient(listOf(colors.third, colors.third)))
    if (!face) return
    val blink = if (sin(t * .9f) > .985f) .15f else 1f
    listOf(41f, 59f).forEach { x ->
        when (state) {
            FlameState.ASH -> drawLine(Palette.ink.copy(alpha = .6f), Offset(x - 4, 86f), Offset(x + 4, 86f), 2.5f, StrokeCap.Round)
            FlameState.FROZEN -> { drawLine(Palette.iceDeep, Offset(x - 4, 82f), Offset(x + 4, 88f), 2.5f, StrokeCap.Round); drawLine(Palette.iceDeep, Offset(x + 4, 82f), Offset(x - 4, 88f), 2.5f, StrokeCap.Round) }
            else -> {
                drawOval(Palette.ink, Offset(x - 4, 84 - 5.5f * blink), Size(8f, 11f * blink))
                drawCircle(Color.White.copy(alpha = blink), 1.5f, Offset(x - 1, 82.5f))
            }
        }
    }
    if (state == FlameState.DIM) {
        drawLine(Palette.ink, Offset(35f, 74f), Offset(44f, 76f), 2.2f, StrokeCap.Round)
        drawLine(Palette.ink, Offset(65f, 74f), Offset(56f, 76f), 2.2f, StrokeCap.Round)
    }
}

/** Drawn checkmark day cell; pops and draws its check when it turns lit. */
@Composable
fun DayCell(state: StreakDayState, size: Dp = 34.dp, lit: Boolean = state == StreakDayState.DONE || state == StreakDayState.TODAY_DONE) {
    val empty = if (isDarkSurface()) Color.White.copy(alpha = .10f) else Color(0xFFE5E5E5)
    val draw = remember { Animatable(if (lit) 1f else 0f) }
    var pop by remember { mutableIntStateOf(0) }
    var wasLit by remember { mutableStateOf(lit) }
    LaunchedEffect(lit) { if (lit && !wasLit) { pop++; draw.snapTo(0f); draw.animateTo(1f, tween(220, 80)) }; wasLit = lit }
    val reduce = reduceMotionEnabled()
    val pulse by produceState(0f, state, reduce) {
        if (state != StreakDayState.TODAY || reduce) return@produceState
        val s = withFrameNanos { it }; while (isActive) value = sin(withFrameNanos { (it - s) / 1e9f } * 3.5f)
    }
    Box(Modifier.size(size).slam(pop, .2f), contentAlignment = Alignment.Center) {
        when {
            state == StreakDayState.FROZEN -> Box(Modifier.fillMaxSize().rotate(8f).clip(RoundedCornerShape(8.dp)).background(Palette.ice), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.AcUnit, null, tint = Color.White, modifier = Modifier.size(size * .45f))
            }
            lit -> Canvas(Modifier.fillMaxSize()) {
                drawCircle(Brush.verticalGradient(listOf(Palette.flame, Palette.flameDeep)))
                val p = Path().apply { moveTo(size.toPx() * .3f, size.toPx() * .52f); lineTo(size.toPx() * .44f, size.toPx() * .66f); lineTo(size.toPx() * .72f, size.toPx() * .36f) }
                val measure = androidx.compose.ui.graphics.PathMeasure().apply { setPath(p, false) }
                val partial = Path(); measure.getSegment(0f, measure.length * draw.value, partial, true)
                drawPath(partial, Color.White, style = Stroke(size.toPx() * .11f, cap = StrokeCap.Round))
            }
            state == StreakDayState.TODAY -> Canvas(Modifier.fillMaxSize().graphicsLayer { scaleX = 1 + .07f * pulse; scaleY = 1 + .07f * pulse }) {
                drawCircle(Palette.flame, radius = this.size.minDimension / 2 - 2.dp.toPx(), style = Stroke(3.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f))))
            }
            state == StreakDayState.MISSED -> Box(Modifier.fillMaxSize().clip(CircleShape).background(empty), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Close, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = .35f), modifier = Modifier.size(size * .35f))
            }
            else -> Box(Modifier.fillMaxSize().clip(CircleShape).background(empty))
        }
    }
}

@Composable
fun WeekStrip(days: List<StreakDay>, litOverride: Set<String>? = null, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        days.forEach { day ->
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
                val isToday = day.state == StreakDayState.TODAY || day.state == StreakDayState.TODAY_DONE
                Text(day.letter, style = playType(13, FontWeight.Bold), color = if (isToday) Palette.flame else MaterialTheme.colorScheme.onSurface.copy(alpha = .55f))
                val lit = litOverride?.contains(day.id) ?: (day.state == StreakDayState.DONE || day.state == StreakDayState.TODAY_DONE)
                DayCell(if (isToday && !lit) StreakDayState.TODAY else day.state, lit = lit)
            }
        }
    }
}

data class StreakInfo(val count: Int, val longest: Int, val freezes: Int, val protected: Boolean, val atRisk: Boolean,
                      val days: List<StreakDay>, val watchedMinutes: Int, val goalMinutes: Int, val goalProgress: Float) {
    val flame get() = when { protected -> FlameState.LIT; count == 0 -> FlameState.ASH; atRisk -> FlameState.DIM; else -> FlameState.LIT }
    val statusLine get() = when { protected -> "Safe today"; atRisk -> "Save it · ${(goalMinutes - watchedMinutes).coerceAtLeast(1)} min"; count == 0 -> "Light it today"; else -> "${(goalMinutes - watchedMinutes).coerceAtLeast(0)} min to go" }
}

fun AppSnapshot.streakInfo(): StreakInfo {
    val today = todayKey()
    val streak = habitLoop.streak(activities)
    val goalSeconds = habitLoop.goalSeconds(today, habitSettings.currentDailyGoalMinutes * 60)
    val learned = habitLoop.learnedSeconds(today)
    val protected = habitLoop.completedGoal(today)
    val atRisk = !protected && streak.count > 0 && java.time.LocalTime.now().hour >= 18
    return StreakInfo(streak.count, maxOf(stats.longestStreak, streak.count), streak.freezes, protected, atRisk, habitLoop.weekStrip(activities),
        (learned / 60).toInt(), (goalSeconds / 60).toInt(), (learned / goalSeconds.coerceAtLeast(60.0)).toFloat().coerceIn(0f, 1f))
}

/** Hero streak card: flame, rolling count, freezes, week strip and goal bar. */
@Composable
fun StreakHero(info: StreakInfo, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    var hop by remember { mutableIntStateOf(0) }
    LaunchedEffect(info.count) { if (info.count > 0) hop++ }
    ChunkyTile(onOpen, modifier.fillMaxWidth(), selected = info.atRisk, tint = if (info.atRisk) Palette.error else null, radius = 22.dp) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StreakFlame(info.flame, 66.dp, modifier = Modifier.hop(hop, 12f))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    RollingNumber(info.count, 40, if (info.flame == FlameState.ASH) Palette.ash else Palette.flame)
                    Text("day streak", style = playType(15, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                }
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        repeat(2) { i ->
                            val owned = i < info.freezes
                            Box(Modifier.size(24.dp).clip(RoundedCornerShape(7.dp)).background(if (owned) Palette.ice.copy(alpha = .3f) else Color.Gray.copy(alpha = .1f)), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.AcUnit, null, tint = if (owned) Palette.iceDeep else Color.Gray.copy(alpha = .35f), modifier = Modifier.size(14.dp))
                            }
                        }
                    }
                    Text(info.statusLine, style = playType(13, FontWeight.Bold), color = when { info.atRisk -> Palette.error; info.protected -> Palette.success; else -> MaterialTheme.colorScheme.onSurface.copy(alpha = .6f) })
                }
            }
            WeekStrip(info.days)
            PlayProgressBar(info.goalProgress, tint = if (info.protected) Palette.success else Palette.flame, height = 14.dp)
            Row {
                Text("${info.watchedMinutes} / ${info.goalMinutes} min today", Modifier.weight(1f), style = playType(12, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                val next = StreakMilestones.next(info.count)
                Text("${next - info.count} to $next-day badge", style = playType(12, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
            }
        }
    }
}

/** Level identity: badge ring, title, XP to the next title. */
@Composable
fun LevelCard(stats: UserStats, modifier: Modifier = Modifier) {
    val level = stats.level
    val progress = if (level.xpToNext > 0) ((stats.totalXp - level.minXp).toFloat() / level.xpToNext).coerceIn(0f, 1f) else 1f
    val ring = remember { Animatable(0f) }
    LaunchedEffect(progress) { ring.animateTo(progress, tween(900)) }
    Row(modifier.fillMaxWidth().chunkyCard().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(62.dp), contentAlignment = Alignment.Center) {
            val track = if (isDarkSurface()) Color.White.copy(alpha = .1f) else Color(0xFFE5E5E5)
            Canvas(Modifier.fillMaxSize()) {
                drawArc(track, 0f, 360f, false, style = Stroke(7.dp.toPx()))
                drawArc(Palette.gold, -90f, 360f * ring.value, false, style = Stroke(7.dp.toPx(), cap = StrokeCap.Round))
            }
            Icon(Icons.Rounded.MilitaryTech, null, tint = Palette.gold, modifier = Modifier.size(26.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text("LEVEL ${level.number}", style = playType(12), color = Palette.goldLip)
            Text(level.title, style = playType(20))
            val next = Level.values.getOrNull(level.number)
            Text(if (next != null) "${level.minXp + level.xpToNext - stats.totalXp} XP to ${next.title}" else "Top level reached", style = playType(13, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("${stats.totalXp}", style = playType(22), color = Palette.goldLip)
            Text("total XP", style = playType(12, FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
        }
    }
}

@Composable
fun LeagueCard(league: HabitLeague, modifier: Modifier = Modifier) {
    val color = listOf(Color(0xFFCD7F32), Color(0xFFA8B4C0), Palette.gold, Color(0xFF6ED8D0), Color(0xFF8FB8FF))[league.tier.coerceIn(0, 4)]
    val minutesLeft = (league.targetMinutes - league.minutes).toInt().coerceAtLeast(0)
    val daysLeft = (5 - league.activeDays).coerceAtLeast(0)
    Column(modifier.fillMaxWidth().chunkyCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(54.dp).clip(RoundedCornerShape(16.dp)).background(color), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.EmojiEvents, null, tint = Color.White, modifier = Modifier.size(28.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column {
                Text("${league.title.uppercase()} LEAGUE", style = playType(13), color = color)
                Text(when {
                    minutesLeft == 0 && daysLeft == 0 -> "Promotion locked in!"
                    minutesLeft == 0 -> "Minutes done · $daysLeft more active day${if (daysLeft == 1) "" else "s"}"
                    daysLeft == 0 -> "$minutesLeft min to promote"
                    else -> "$minutesLeft min · $daysLeft day${if (daysLeft == 1) "" else "s"} to promote"
                }, style = playType(17))
                Text("You vs. your last 4 weeks. Resets Monday.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
            }
        }
        PlayProgressBar((league.minutes / league.targetMinutes.coerceAtLeast(1.0)).toFloat(), tint = color, height = 12.dp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(5) { Box(Modifier.weight(1f).height(8.dp).clip(CircleShape).background(if (it < league.activeDays) color else Color.Gray.copy(alpha = .15f))) }
        }
    }
}

/** Compact streak + gems + XP readout for the sidebar. */
@Composable
fun StreakBadge(info: StreakInfo, gems: Int, xp: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StreakFlame(info.flame, 24.dp, showsFace = false)
            Text("${info.count}", style = playType(16), color = if (info.flame == FlameState.ASH) Palette.ash else Palette.flame)
        }
        StatPill(Icons.Rounded.Diamond, "$gems", Palette.gem)
        StatPill(Icons.Rounded.Bolt, "$xp", Palette.goldLip)
    }
}

