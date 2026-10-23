package com.tangenix.podtrackio.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.tangenix.podtrackio.MainActivity
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.data.LocalStore
import com.tangenix.podtrackio.domain.AppSnapshot
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class LearningWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try { updateAll(context, LocalStore(context).load()) } finally { pending.finish() }
        }
    }

    companion object {
        const val START_FIVE_MINUTES = "learning_five_minutes"
        fun updateAll(context: Context, snapshot: AppSnapshot) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, LearningWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val today = LocalDate.now().toString()
            val protected = today in snapshot.habitLoop.learningDays(snapshot.activities)
            val streak = snapshot.habitLoop.streak(snapshot.activities).count
            val next = snapshot.podcasts.firstOrNull { it.hasProgress } ?: snapshot.podcasts.firstOrNull { !it.isCompleted }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(START_FIVE_MINUTES, true)
                putExtra("podcast_id", next?.id)
            }
            val open = PendingIntent.getActivity(context, 51000, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val views = RemoteViews(context.packageName, R.layout.learning_widget).apply {
                setTextViewText(R.id.widget_streak, "$streak-day streak")
                setTextViewText(R.id.widget_status, if (protected) "Streak protected today" else "${snapshot.habitLoop.goalSeconds(today, snapshot.habitSettings.currentDailyGoalMinutes * 60).toInt() / 60} minutes protects today")
                setTextViewText(R.id.widget_gems, "${snapshot.habitLoop.gems} gems · ${snapshot.habitLoop.questCount(today)}/3 quests")
                setOnClickPendingIntent(R.id.widget_start, open)
                setOnClickPendingIntent(R.id.widget_root, open)
            }
            ids.forEach { manager.updateAppWidget(it, views) }
        }
    }
}
