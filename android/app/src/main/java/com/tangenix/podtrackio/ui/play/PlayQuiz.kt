package com.tangenix.podtrackio.ui.play

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.domain.RecallQuestion
import kotlinx.coroutines.launch

/** One question at a time: pick, Check, then a green or red sheet with the source. Haptics land on every swing. */
@Composable
fun PlayQuiz(title: String, questions: List<RecallQuestion>, onFinish: (Int) -> Unit, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        var index by remember { mutableIntStateOf(0) }
        var selected by remember { mutableStateOf<Int?>(null) }
        var checked by remember { mutableStateOf(false) }
        var correct by remember { mutableIntStateOf(0) }
        var combo by remember { mutableIntStateOf(0) }
        var tilePop by remember { mutableIntStateOf(0) }
        var echoHop by remember { mutableIntStateOf(0) }
        var sparks by remember { mutableIntStateOf(0) }
        var finished by remember { mutableStateOf(false) }
        val shake = remember { Animatable(0f) }
        val scope = rememberCoroutineScope()
        val reduce = reduceMotionEnabled()
        val dark = isDarkSurface()
        val question = questions.getOrNull(index)
        val isCorrect = question != null && selected == question.answer

        Box(Modifier.fillMaxSize().background(if (dark) Color(0xFF131722) else Color.White).systemBarsPadding()) {
            if (finished) {
                val accuracy = (correct * 100f / questions.size.coerceAtLeast(1)).toInt()
                var confetti by remember { mutableIntStateOf(0) }
                LaunchedEffect(Unit) { PlayFeedback.sound(R.raw.complete); PlayFeedback.play(Cue.SUCCESS, sound = false); if (accuracy >= 66) confetti++ }
                MomentScaffold(Palette.success, true, { onFinish(correct) }, overlay = { ParticleBurst(confetti, Modifier.fillMaxSize(), BurstStyle.CANNONS, 90) }) {
                    Echo(if (accuracy >= 66) EchoMood.CHEER else EchoMood.HAPPY, 140.dp)
                    Text(when { accuracy == 100 -> "Perfect recall!"; accuracy >= 66 -> "Nicely remembered!"; else -> "Practice makes permanent" }, style = playType(30))
                    Row(horizontalArrangement = Arrangement.spacedBy(30.dp)) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { CountUpText(accuracy, 40, Palette.success, "%"); Text("ACCURACY", style = playType(12)) }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) { CountUpText(correct, 40, Palette.gold, "/${questions.size}"); Text("CORRECT", style = playType(12)) }
                    }
                }
            } else if (question != null) Column(Modifier.fillMaxSize()) {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconButton(onClose) { Icon(Icons.Rounded.Close, "Close quiz") }
                    PlayProgressBar((index + if (checked) 1 else 0).toFloat() / questions.size, Modifier.weight(1f))
                    if (combo >= 2) Row(Modifier.slam(combo, 1.8f), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.LocalFireDepartment, null, tint = Palette.flame); Text("$combo", style = playType(16), color = Palette.flame)
                    }
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Text(title.uppercase(), style = playType(13), color = MaterialTheme.colorScheme.primary)
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Echo(if (checked) (if (isCorrect) EchoMood.CHEER else EchoMood.WORRIED) else EchoMood.THINKING, 74.dp, modifier = Modifier.hop(echoHop, 16f))
                        Text(question.question, style = playType(21, FontWeight.ExtraBold), modifier = Modifier.padding(top = 8.dp))
                    }
                    Column(Modifier.graphicsLayer { translationX = shake.value * density }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        question.choices.forEachIndexed { i, choice ->
                            val tint = when { !checked -> null; i == question.answer -> Palette.success; i == selected -> Palette.error; else -> null }
                            val isSelected = if (checked) i == question.answer || i == selected else i == selected
                            Box {
                                ChunkyTile({ if (!checked) { selected = i; PlayFeedback.play(Cue.SELECT, sound = false) } }, Modifier.fillMaxWidth().slam(if (i == question.answer) tilePop else 0, 1.1f),
                                    selected = isSelected, tint = tint, radius = 16.dp, enabled = !checked) {
                                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Text("${i + 1}", style = playType(14), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .5f),
                                            modifier = Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .25f), RoundedCornerShape(8.dp)).padding(horizontal = 9.dp, vertical = 3.dp))
                                        Text(choice, style = playType(17, FontWeight.SemiBold))
                                    }
                                }
                                if (i == question.answer) ParticleBurst(tilePop, Modifier.matchParentSize(), BurstStyle.SPARKS, 16, listOf(Palette.success, Palette.gold, Color.White))
                            }
                        }
                    }
                }
                if (!checked) Box(Modifier.padding(20.dp)) {
                    ChunkyButton("Check", {
                        val pick = selected ?: return@ChunkyButton
                        if (pick == question.answer) {
                            correct++; combo++
                            scope.launch { runBeats(listOf(Beat(0.0, Cue.CORRECT) { checked = true; tilePop++; echoHop++ }, Beat(.12) { sparks++ }, Beat(.3, if (combo >= 2) Cue.POP else null, sound = combo >= 3)), reduce) }
                        } else {
                            combo = 0
                            val swings = listOf(Triple(0.0, -14f, 1f), Triple(.07, 12f, .85f), Triple(.14, -9f, .7f), Triple(.21, 6f, .5f), Triple(.28, -3f, .3f), Triple(.35, 0f, 0f))
                            scope.launch {
                                runBeats(listOf(Beat(0.0, Cue.WRONG) { checked = true }) + swings.map { (t, x, p) ->
                                    Beat(t, if (p > 0) Cue.SWING else null, sound = false, intensity = p) { scope.launch { shake.animateTo(x, tween(60)) } }
                                }, reduce)
                            }
                        }
                    }, kind = ChunkyKind.SUCCESS, enabled = selected != null)
                }
                AnimatedVisibility(checked, enter = slideInVertically { it } + fadeIn()) {
                    val tint = if (isCorrect) Palette.success else Palette.error
                    Column(Modifier.fillMaxWidth().background(tint.copy(alpha = if (dark) .18f else .14f)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(if (isCorrect) Icons.Rounded.CheckCircle else Icons.Rounded.Cancel, null, tint = if (isCorrect) Palette.successLip else Palette.errorLip, modifier = Modifier.size(30.dp))
                            Text(if (isCorrect) (if (combo >= 3) "$combo in a row! Unstoppable." else listOf("Nice!", "Correct!", "You remembered!", "Exactly right!")[combo % 4])
                                else listOf("Not quite. Here's the source.", "Close! Check the evidence.")[index % 2],
                                style = playType(22), color = if (isCorrect) Palette.successLip else Palette.errorLip)
                        }
                        if (!isCorrect) Text("Answer: ${question.choices[question.answer]}", style = playType(16, FontWeight.Bold), color = Palette.errorLip)
                        Text(question.explanation, style = MaterialTheme.typography.bodyMedium)
                        Text("“${question.evidence}”", style = MaterialTheme.typography.bodySmall.copy(fontStyle = FontStyle.Italic), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .6f), maxLines = 4)
                        ChunkyButton(if (index + 1 < questions.size) "Continue" else "See results", {
                            if (index + 1 < questions.size) { index++; selected = null; checked = false; scope.launch { shake.snapTo(0f) } } else finished = true
                        }, kind = if (isCorrect) ChunkyKind.SUCCESS else ChunkyKind.DANGER)
                    }
                }
            }
        }
    }
}
