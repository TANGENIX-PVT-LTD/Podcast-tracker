package com.tangenix.podtrackio.ui.play

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AcUnit
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Diamond
import androidx.compose.material.icons.rounded.MilitaryTech
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.TrackChanges
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.tangenix.podtrackio.Moment
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.domain.AppSnapshot
import com.tangenix.podtrackio.domain.StreakDayState
import com.tangenix.podtrackio.domain.StreakMilestones
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Shows the first queued moment full-screen over everything. */
@Composable
fun MomentHost(moment: Moment?, snapshot: AppSnapshot, onDone: () -> Unit) {
    AnimatedVisibility(moment != null, enter = fadeIn(tween(180)), exit = fadeOut(tween(180))) {
        BackHandler(onBack = onDone)
        when (moment) {
            Moment.StreakExtended -> StreakCelebration(snapshot, onDone)
            is Moment.Chest -> ChestReveal(moment.gems, onDone)
            Moment.LevelUp -> LevelUpMoment(snapshot, onDone)
            is Moment.Session -> SessionComplete(moment, onDone)
            is Moment.FreezeSaved -> FreezeSaved(moment.streak, onDone)
            null -> Unit
        }
    }
}

/** Shared stage: background glow, camera shake, flash, and a Continue button that lands last. */
@Composable
fun MomentScaffold(glow: Color, showsButton: Boolean, onContinue: () -> Unit, shake: Int = 0, flash: Int = 0, flashColor: Color = Color.White,
                   buttonKind: ChunkyKind = ChunkyKind.PRIMARY, overlay: @Composable BoxScope.() -> Unit = {}, content: @Composable ColumnScope.() -> Unit) {
    val dark = isDarkSurface()
    Box(Modifier.fillMaxSize().background(if (dark) Color(0xFF131722) else Color.White)
        .clickable(remember { MutableInteractionSource() }, null) {}) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Brush.radialGradient(listOf(glow.copy(alpha = if (dark) .34f else .24f), Color.Transparent), Offset(size.width / 2, size.height * .38f), size.minDimension * .75f))
        }
        Column(Modifier.fillMaxSize().padding(24.dp).impactShake(shake), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Column(Modifier.widthIn(max = 520.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
            Spacer(Modifier.weight(1f))
            val lift by animateFloatAsState(if (showsButton) 0f else 1f, spring(dampingRatio = .58f, stiffness = 300f), label = "button")
            Box(Modifier.widthIn(max = 520.dp).graphicsLayer { alpha = 1 - lift; translationY = lift * 40 * density }) {
                ChunkyButton("Continue", { if (showsButton) onContinue() }, kind = buttonKind, enabled = true)
            }
        }
        overlay()
        ImpactFlash(flash, flashColor)
    }
}

// MARK: - Streak extended

/** 0 ignite rumble · 0.45 IGNITION (flash, shock, shake) · 0.8 digits roll + cannons · 1.05 text · week fills · Echo · button. */
@Composable
private fun StreakCelebration(snapshot: AppSnapshot, onDone: () -> Unit) {
    val info = remember { snapshot.streakInfo() }
    val count = info.count
    val milestone = count in StreakMilestones.all
    var lit by remember { mutableStateOf(false) }
    val flameScale = remember { Animatable(.15f) }
    var shown by remember { mutableIntStateOf((count - 1).coerceAtLeast(0)) }
    var numberSlam by remember { mutableIntStateOf(0) }
    var textIn by remember { mutableIntStateOf(0) }
    var stripIn by remember { mutableStateOf(false) }
    var litDays by remember { mutableStateOf(emptySet<String>()) }
    var echoIn by remember { mutableStateOf(false) }
    var echoHop by remember { mutableIntStateOf(0) }
    var flameHop by remember { mutableIntStateOf(0) }
    var badge by remember { mutableIntStateOf(0) }
    var button by remember { mutableStateOf(false) }
    var shock by remember { mutableIntStateOf(0) }
    var shake by remember { mutableIntStateOf(0) }
    var flash by remember { mutableIntStateOf(0) }
    var confetti by remember { mutableIntStateOf(0) }
    var sparks by remember { mutableIntStateOf(0) }
    val reduce = reduceMotionEnabled()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        val earlier = info.days.filter { it.state == StreakDayState.DONE }.map { it.id }
        val todayId = info.days.firstOrNull { it.state == StreakDayState.TODAY || it.state == StreakDayState.TODAY_DONE }?.id
        val beats = mutableListOf(
            Beat(0.0, Cue.IGNITE) { scope.launch { flameScale.animateTo(1.3f, tween(450)) } },
            Beat(.45, Cue.IMPACT, sound = false) { lit = true; flash++; shock++; shake++; sparks++; scope.launch { flameScale.animateTo(1f, spring(dampingRatio = .42f, stiffness = 300f)) } },
            Beat(.8, Cue.STREAK_FLIP) { shown = count; numberSlam++; confetti++; shock++; flameHop++ },
            Beat(1.05, Cue.LAND, sound = false) { textIn++ },
            Beat(1.25, Cue.TAP, sound = false) { stripIn = true },
        )
        var t = 1.45
        earlier.forEachIndexed { i, id ->
            beats += Beat(t, Cue.TICK, sound = false) { litDays = litDays + id; PlayFeedback.sound(R.raw.tick, 1f + i * .1f) }
            t += .09
        }
        todayId?.let { id -> t += .12; beats += Beat(t, Cue.POP) { litDays = litDays + id; flameHop++; sparks++ } }
        t += .3
        beats += Beat(t, Cue.LAND, sound = false) { echoIn = true; echoHop++ }
        if (milestone) { t += .55; beats += Beat(t, Cue.LEVEL_UP) { badge++; shake++; confetti++ } }
        beats += Beat(t + .4, Cue.RELEASE, sound = false) { button = true }
        runBeats(beats, reduce)
    }
    MomentScaffold(Palette.flame, button, onDone, shake, flash, overlay = {
        ParticleBurst(confetti, Modifier.fillMaxSize(), BurstStyle.CANNONS, 110)
    }) {
        Box(Modifier.height(210.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (lit) Rays(Palette.flame, Modifier.size(360.dp))
            EmberField(lit, Modifier.size(220.dp, 260.dp).offset(y = (-40).dp))
            ShockwaveRing(shock, Palette.flame, Modifier.size(200.dp))
            StreakFlame(if (lit) FlameState.LIT else FlameState.ASH, 150.dp,
                modifier = Modifier.graphicsLayer { scaleX = flameScale.value; scaleY = flameScale.value; transformOrigin = TransformOrigin(.5f, 1f) }.hop(flameHop, 18f))
            ParticleBurst(sparks, Modifier.size(340.dp), BurstStyle.SPARKS, 30, listOf(Palette.flame, Palette.gold, Color.White))
        }
        RollingNumber(shown, 92, if (lit) Palette.flame else Palette.ash, Modifier.slam(numberSlam, 1.9f))
        Text("day streak!", style = playType(30), color = Palette.flame, modifier = Modifier.graphicsLayer { alpha = if (textIn > 0) 1f else 0f }.slam(textIn, 1.6f))
        val stripAlpha by animateFloatAsState(if (stripIn) 1f else 0f, spring(dampingRatio = .7f), label = "strip")
        WeekStrip(info.days.map { if (it.state == StreakDayState.TODAY_DONE && it.id !in litDays) it.copy(state = StreakDayState.TODAY) else it }, litDays,
            Modifier.graphicsLayer { alpha = stripAlpha; translationY = (1 - stripAlpha) * 30 * density }.chunkyCard().padding(14.dp))
        if (milestone && badge > 0) Row(Modifier.slam(badge, 2.2f).clip(CircleShape).background(Palette.gold).padding(horizontal = 18.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Rounded.WorkspacePremium, null, tint = Palette.ink); Text("$count-day milestone!", style = playType(17), color = Palette.ink)
        }
        AnimatedVisibility(echoIn, enter = slideInVertically { it } + fadeIn()) {
            EchoSays(EchoMood.CHEER, celebrationLine(count), Modifier.hop(echoHop, 30f), 78.dp)
        }
    }
}

fun celebrationLine(streak: Int) = when (streak) {
    1 -> "Day one! Every great streak starts here."
    3 -> "Three in a row. A habit is forming!"
    7 -> "A whole week! You're officially a regular."
    14 -> "Two weeks strong. This is who you are now."
    30 -> "Thirty days! Legendary consistency."
    50, 100, 365 -> "$streak days. I'm speechless. Well, almost."
    else -> listOf("Streak extended! Your brain thanks you.", "Another day, another flame. Nice!", "Consistency is your superpower.", "Keep stacking those days!")[streak % 4]
}

// MARK: - Chest

/** 0 drop · 0.32 thud · 0.8/1.15/1.5 rattles with glow · 1.8 burst · gems fly in one tick each · boost chip. */
@Composable
private fun ChestReveal(gems: Int, onDone: () -> Unit) {
    val drop = remember { Animatable(-520f) }
    val wobble = remember { Animatable(0f) }
    val squash = remember { Animatable(1f) }
    var glow by remember { mutableFloatStateOf(0f) }
    var open by remember { mutableStateOf(false) }
    var burst by remember { mutableIntStateOf(0) }
    var counted by remember { mutableIntStateOf(0) }
    var counterSlam by remember { mutableIntStateOf(0) }
    var boost by remember { mutableIntStateOf(0) }
    var button by remember { mutableStateOf(false) }
    var shock by remember { mutableIntStateOf(0) }
    var shake by remember { mutableIntStateOf(0) }
    var flash by remember { mutableIntStateOf(0) }
    val flights = remember { mutableStateListOf<Int>() }
    val visible = gems.coerceIn(3, 10)
    val reduce = reduceMotionEnabled()
    val scope = rememberCoroutineScope()
    fun rattle(angle: Float, power: Float): () -> Unit = {
        glow = power * .6f
        scope.launch { wobble.snapTo(angle); squash.snapTo(.9f); delay(60); launch { squash.animateTo(1f, spring(dampingRatio = .3f)) }; wobble.animateTo(0f, spring(dampingRatio = .25f, stiffness = 600f)) }
    }
    LaunchedEffect(Unit) {
        val beats = mutableListOf(
            Beat(0.0) { scope.launch { drop.animateTo(0f, tween(320)) } },
            Beat(.32, Cue.THUD) { shake++; scope.launch { squash.snapTo(.82f); squash.animateTo(1f, spring(dampingRatio = .4f)) } },
            Beat(.8, Cue.SWING, sound = false, intensity = .55f, action = rattle(-9f, .4f)),
            Beat(.8) { PlayFeedback.sound(R.raw.chest) },
            Beat(1.15, Cue.SWING, sound = false, intensity = .8f, action = rattle(12f, .7f)),
            Beat(1.5, Cue.SWING, sound = false, intensity = 1f, action = rattle(-15f, 1f)),
            Beat(1.8, Cue.IMPACT, sound = false) { open = true; glow = 1f; burst++; shock++; shake++; flash++ },
        )
        var t = 2.05
        repeat(visible) { i ->
            beats += Beat(t) { flights += i }
            beats += Beat(t + .6, Cue.TICK, sound = false, intensity = .6f + i * .04f) {
                counted = if (i == visible - 1) gems else (gems * (i + 1) / visible); counterSlam++
                PlayFeedback.sound(R.raw.tick, 1f + i * .09f)
            }
            t += .09
        }
        beats += Beat(t + .75, Cue.LEVEL_UP, sound = false) { boost++ }
        beats += Beat(t + 1.1) { button = true }
        runBeats(beats, reduce)
    }
    MomentScaffold(Palette.gold, button, onDone, shake, flash, Palette.gold.copy(alpha = .9f)) {
        Text(if (open) "Daily chest unlocked!" else "You earned a chest!", style = playType(28), textAlign = TextAlign.Center)
        Box(Modifier.height(240.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (open) Rays(Palette.gold, Modifier.size(320.dp))
            Box(Modifier.size(150.dp).graphicsLayer { alpha = glow }.background(Brush.radialGradient(listOf(Palette.gold, Color.Transparent)), CircleShape))
            ShockwaveRing(shock, Palette.gold, Modifier.size(180.dp))
            Chest(open, Modifier.size(150.dp, 130.dp).graphicsLayer {
                translationY = drop.value * density; rotationZ = wobble.value; scaleY = squash.value; scaleX = 2 - squash.value
                transformOrigin = TransformOrigin(.5f, 1f)
            })
            ParticleBurst(burst, Modifier.size(360.dp), BurstStyle.GEMS, 26)
            flights.forEach { i -> key(i) { GemFlightDot(i, visible) } }
        }
        Row(Modifier.graphicsLayer { alpha = if (open) 1f else 0f }.slam(counterSlam, 1.25f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Rounded.Diamond, null, tint = Palette.gem, modifier = Modifier.size(34.dp))
            Text("$counted", style = playType(52), color = Palette.gem)
        }
        if (boost > 0) Row(Modifier.slam(boost, 2f).clip(CircleShape).background(Palette.gold).padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Bolt, null, tint = Palette.ink); Text("15-minute double XP boost", style = playType(16), color = Palette.ink)
        }
    }
}

/** One gem arcing from the chest down into the counter. */
@Composable
private fun GemFlightDot(index: Int, count: Int) {
    val p = remember { Animatable(0f) }
    LaunchedEffect(Unit) { p.animateTo(1f, tween(600)) }
    if (p.value >= 1f) return
    val spread = (index - count / 2) * 28f
    val x: Float; val y: Float
    if (p.value < .37f) { val k = p.value / .37f; x = spread * k; y = -(90 + kotlin.math.abs(spread) * .5f) * k }
    else { val k = (p.value - .37f) / .63f; x = spread * (1 - k); y = -(90 + kotlin.math.abs(spread) * .5f) * (1 - k) + 190 * k * k }
    Icon(Icons.Rounded.Diamond, null, tint = Palette.gem, modifier = Modifier.size(24.dp).graphicsLayer { translationX = x * density; translationY = y * density })
}

@Composable
private fun Chest(open: Boolean, modifier: Modifier) {
    val lid by animateFloatAsState(if (open) 1f else 0f, spring(dampingRatio = .5f, stiffness = 300f), label = "lid")
    Canvas(modifier) {
        val w = size.width; val h = size.height
        val brown = Color(0xFFA0612B); val dark = Color(0xFF6E3F17); val lidColor = Color(0xFFB8733A)
        drawRoundRect(dark, Offset(-2f, h * .45f - 2), Size(w + 4, h * .55f + 4), CornerRadius(30f))
        drawRoundRect(brown, Offset(0f, h * .45f), Size(w, h * .55f), CornerRadius(28f))
        drawRect(Palette.gold, Offset(w / 2 - 16, h * .45f), Size(32f, h * .55f))
        if (open) drawOval(Brush.radialGradient(listOf(Palette.gold, Color.Transparent)), Offset(w * .15f, h * .2f), Size(w * .7f, h * .4f))
        withTransform({ rotate(-28f * lid, Offset(0f, h * .45f)); translate(-8f * lid, -h * .1f * lid) }) {
            drawRoundRect(dark, Offset(-4f, h * .02f - 2), Size(w + 8, h * .45f + 4), CornerRadius(w * .3f))
            drawRoundRect(lidColor, Offset(-2f, h * .02f), Size(w + 4, h * .45f), CornerRadius(w * .3f))
            drawRect(Palette.gold, Offset(w / 2 - 16, h * .02f), Size(32f, h * .45f))
            drawRoundRect(Palette.gold, Offset(w / 2 - 28, h * .38f), Size(56f, 48f), CornerRadius(10f))
            drawCircle(dark, 8f, Offset(w / 2, h * .38f + 24))
        }
    }
}

// MARK: - Level up

@Composable
private fun LevelUpMoment(snapshot: AppSnapshot, onDone: () -> Unit) {
    val level = snapshot.stats.level
    val spin = remember { Animatable(0f) }
    val grow = remember { Animatable(.15f) }
    var landed by remember { mutableIntStateOf(0) }
    var title by remember { mutableIntStateOf(0) }
    var name by remember { mutableIntStateOf(0) }
    var echoIn by remember { mutableStateOf(false) }
    var echoHop by remember { mutableIntStateOf(0) }
    var button by remember { mutableStateOf(false) }
    var confetti by remember { mutableIntStateOf(0) }
    var shock by remember { mutableIntStateOf(0) }
    var shake by remember { mutableIntStateOf(0) }
    var flash by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val reduce = reduceMotionEnabled()
    LaunchedEffect(Unit) {
        runBeats(listOf(
            Beat(0.0, Cue.LEVEL_UP) { scope.launch { spin.animateTo(720f, tween(620)) }; scope.launch { grow.animateTo(1f, tween(620)) } },
            Beat(.62, Cue.IMPACT, sound = false) { landed++; shock++; shake++; flash++; confetti++ },
            Beat(.95, Cue.LAND, sound = false) { title++ },
            Beat(1.2, Cue.TAP, sound = false) { name++ },
            Beat(1.5, Cue.LAND, sound = false) { echoIn = true; echoHop++ },
            Beat(1.9) { button = true },
        ), reduce)
    }
    MomentScaffold(Palette.gold, button, onDone, shake, flash, overlay = { ParticleBurst(confetti, Modifier.fillMaxSize(), BurstStyle.CANNONS, 110) }) {
        Box(Modifier.height(250.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (landed > 0) Rays(Palette.gold, Modifier.size(340.dp))
            ShockwaveRing(shock, Palette.gold, Modifier.size(190.dp))
            Box(Modifier.size(150.dp).graphicsLayer { rotationY = spin.value; scaleX = grow.value; scaleY = grow.value; cameraDistance = 12 * density }.slam(landed, 1.3f)
                .clip(CircleShape).background(Brush.verticalGradient(listOf(Palette.gold, Palette.goldLip))), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.MilitaryTech, null, tint = Color.White, modifier = Modifier.size(70.dp))
            }
            ParticleBurst(landed, Modifier.size(360.dp), BurstStyle.SPARKS, 36, listOf(Palette.gold, Color.White, Palette.flame))
        }
        Text("Level ${level.number}!", style = playType(44), color = Palette.gold, modifier = Modifier.graphicsLayer { alpha = if (title > 0) 1f else 0f }.slam(title, 2.2f))
        Text("New title: ${level.title}", style = playType(22, FontWeight.ExtraBold), modifier = Modifier.graphicsLayer { alpha = if (name > 0) 1f else 0f }.slam(name, 1.6f))
        AnimatedVisibility(echoIn, enter = slideInVertically { it } + fadeIn()) {
            EchoSays(EchoMood.PROUD, "Level ${level.number}! I knew you had it in you.", Modifier.hop(echoHop), 74.dp)
        }
    }
}

// MARK: - Freeze saved

@Composable
private fun FreezeSaved(streak: Int, onDone: () -> Unit) {
    var thawed by remember { mutableStateOf(false) }
    val ice = remember { Animatable(0f) }
    var shatter by remember { mutableIntStateOf(0) }
    var flameHop by remember { mutableIntStateOf(0) }
    var echoHop by remember { mutableIntStateOf(0) }
    var button by remember { mutableStateOf(false) }
    var shake by remember { mutableIntStateOf(0) }
    var flash by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val reduce = reduceMotionEnabled()
    fun shiver(angle: Float): () -> Unit = { scope.launch { ice.snapTo(angle); ice.animateTo(0f, spring(dampingRatio = .2f, stiffness = 700f)) } }
    LaunchedEffect(Unit) {
        runBeats(listOf(
            Beat(.4, Cue.SWING, sound = false, intensity = .6f, action = shiver(-5f)),
            Beat(.7, Cue.SWING, sound = false, intensity = .9f, action = shiver(6f)),
            Beat(1.0, Cue.FREEZE) { thawed = true; shatter++; shake++; flash++ },
            Beat(1.15, Cue.IGNITE, intensity = .7f) { flameHop++ },
            Beat(1.6, Cue.LAND, sound = false) { echoHop++ },
            Beat(2.0) { button = true },
        ), reduce)
    }
    MomentScaffold(Palette.ice, button, onDone, shake, flash, Palette.ice, ChunkyKind.GEM) {
        Box(Modifier.height(210.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
            EmberField(thawed, Modifier.size(200.dp, 240.dp).offset(y = (-30).dp))
            StreakFlame(if (thawed) FlameState.LIT else FlameState.FROZEN, 140.dp, modifier = Modifier.hop(flameHop, 22f))
            if (!thawed) Box(Modifier.size(160.dp, 172.dp).graphicsLayer { rotationZ = ice.value }.clip(RoundedCornerShape(26.dp)).background(Palette.ice.copy(alpha = .5f)))
            ParticleBurst(shatter, Modifier.size(360.dp), BurstStyle.ICE, 44)
        }
        Text("Streak freeze used", style = playType(30), color = Palette.iceDeep)
        Text("A freeze covered yesterday, so your $streak-day streak is still alive.", style = playType(18, FontWeight.Bold), textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
        EchoSays(if (thawed) EchoMood.HAPPY else EchoMood.FROZEN, if (thawed) "Phew! Let's keep it burning today." else "Brrr…", Modifier.hop(echoHop), 74.dp)
    }
}

// MARK: - Session complete

@Composable
private fun SessionComplete(summary: Moment.Session, onDone: () -> Unit) {
    var step by remember { mutableIntStateOf(0) }
    var title by remember { mutableIntStateOf(0) }
    var echoHop by remember { mutableIntStateOf(0) }
    var confetti by remember { mutableIntStateOf(0) }
    var shake by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        runBeats(listOf(
            Beat(0.0, Cue.SUCCESS, sound = false) { echoHop++; confetti++; PlayFeedback.sound(R.raw.complete) },
            Beat(.35, Cue.LAND, sound = false) { title++ },
            Beat(.75, Cue.THUD) { step = 1; shake++ },
            Beat(1.05, Cue.THUD, intensity = .85f) { step = 2 },
            Beat(1.35, Cue.THUD, intensity = .7f) { step = 3 },
            Beat(2.1, Cue.TAP, sound = false) { step = 4 },
            Beat(2.6) { step = 5 },
        ))
    }
    MomentScaffold(Palette.success, step >= 5, onDone, shake, overlay = { ParticleBurst(confetti, Modifier.fillMaxSize(), BurstStyle.CANNONS, 110) }) {
        Echo(EchoMood.CHEER, 140.dp, modifier = Modifier.hop(echoHop, 34f))
        Text("Session complete!", style = playType(34), color = Palette.gold, modifier = Modifier.graphicsLayer { alpha = if (title > 0) 1f else 0f }.slam(title, 2f))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile("TOTAL XP", Palette.gold, Icons.Rounded.Bolt, step >= 1, Modifier.weight(1f)) { CountUpText(summary.xp, 24, Palette.gold) }
            StatTile("TIME", Palette.gem, Icons.Rounded.Schedule, step >= 2, Modifier.weight(1f)) { CountUpText((summary.seconds / 60).toInt(), 24, Palette.gem, "m") }
            StatTile("GOAL", Palette.success, Icons.Rounded.TrackChanges, step >= 3, Modifier.weight(1f)) { CountUpText((summary.goalProgress * 100).toInt(), 24, Palette.success, "%") }
        }
        AnimatedVisibility(step >= 4, enter = slideInVertically { it } + fadeIn()) {
            Column(Modifier.fillMaxWidth().chunkyCard().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("DAILY QUESTS ${summary.quests}/3", style = playType(13), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f))
                PlayProgressBar(summary.quests / 3f, tint = Palette.gold)
            }
        }
    }
}

@Composable
private fun StatTile(title: String, color: Color, icon: androidx.compose.ui.graphics.vector.ImageVector, visible: Boolean, modifier: Modifier, value: @Composable () -> Unit) {
    val flip by animateFloatAsState(if (visible) 0f else 90f, spring(dampingRatio = .55f, stiffness = 300f), label = "flip")
    Column(modifier.graphicsLayer { rotationX = flip; alpha = if (visible) 1f else 0f; transformOrigin = TransformOrigin(.5f, 0f); cameraDistance = 12 * density }
        .clip(RoundedCornerShape(16.dp)).background(color).padding(2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(title, style = playType(12), color = Color.White, modifier = Modifier.padding(vertical = 5.dp))
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(cardSurface()).padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = color, modifier = Modifier.size(18.dp)); Spacer(Modifier.width(4.dp))
            if (visible) value() else Text("–", style = playType(24), color = color)
        }
    }
}
