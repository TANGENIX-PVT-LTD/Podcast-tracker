package com.tangenix.podtrackio.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.tangenix.podtrackio.MainActivity
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.data.LocalStore
import com.tangenix.podtrackio.domain.AppSnapshot
import com.tangenix.podtrackio.domain.DistractionPatternEngine
import com.tangenix.podtrackio.domain.NotificationPreferences
import com.tangenix.podtrackio.domain.TimeOfDay
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

class ReminderScheduler(
    private val context: Context,
    private val localStore: LocalStore,
) {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    fun createChannels() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(LEARNING_CHANNEL, context.getString(R.string.notification_channel_learning), NotificationManager.IMPORTANCE_DEFAULT),
                NotificationChannel(SCHEDULED_CHANNEL, context.getString(R.string.notification_channel_scheduled), NotificationManager.IMPORTANCE_HIGH),
            ),
        )
    }

    suspend fun reschedule() = reschedule(localStore.load())

    suspend fun reschedule(snapshot: AppSnapshot) {
        cancelKnownAlarms()
        val prefs = snapshot.notificationPreferences
        if (prefs.isEnabled) {
            val next = snapshot.podcasts.filterNot { it.isCompleted }.minByOrNull { it.dateAdded }
            listOf(
                Triple("morning", prefs.morning, "Your learning block is ready"),
                Triple("afternoon", prefs.afternoon, "Protect five focused minutes"),
                Triple("evening", prefs.evening, "Close the day with one useful idea"),
            ).forEachIndexed { index, (name, time, title) ->
                nextSeven(time).filter { calendarWeekday(it) in prefs.enabledWeekdays && !isQuiet(time, prefs) }.forEach { date ->
                    schedule(
                        requestCode = 10_000 + index * 10 + date.dayOfWeek.value,
                        whenAt = date.toInstant(),
                        title = title,
                        body = next?.title ?: "Open PodTrackio and keep your learning streak moving.",
                        podcastId = next?.id,
                        channel = LEARNING_CHANNEL,
                        key = name,
                    )
                }
            }
            DistractionPatternEngine.leadingPattern(snapshot.focusCommitments)?.let { pattern ->
                val time = TimeOfDay(pattern.hour, pattern.minute)
                nextSeven(time).firstOrNull { calendarWeekday(it) == pattern.weekday && pattern.weekday in prefs.enabledWeekdays && !isQuiet(time, prefs) }
                    ?.let { date ->
                        schedule(
                            requestCode = 25_000 + pattern.weekday,
                            whenAt = date.toInstant(),
                            title = "Replace the pull before it starts",
                            body = "Your ${pattern.cue.name.lowercase()} window is near. Reclaim five minutes with PodTrackio.",
                            podcastId = next?.id,
                            channel = LEARNING_CHANNEL,
                            key = "adaptive-rescue",
                        )
                    }
            }
        }
        snapshot.podcasts.filter { !it.isCompleted && it.scheduledAt?.isAfter(Instant.now()) == true }.forEach { podcast ->
            schedule(
                requestCode = 30_000 + podcast.id.hashCode().and(0x3fff),
                whenAt = podcast.scheduledAt!!,
                title = "Scheduled learning time",
                body = podcast.title,
                podcastId = podcast.id,
                channel = SCHEDULED_CHANNEL,
                key = "episode",
            )
        }
    }

    private fun nextSeven(time: TimeOfDay): List<ZonedDateTime> {
        val now = ZonedDateTime.now()
        return (0..7).map { offset -> now.plusDays(offset.toLong()).withHour(time.hour).withMinute(time.minute).withSecond(0).withNano(0) }
            .filter { it.isAfter(now) }.take(7)
    }

    private fun calendarWeekday(date: ZonedDateTime): Int = date.dayOfWeek.value % 7 + 1

    private fun isQuiet(time: TimeOfDay, preferences: NotificationPreferences): Boolean {
        if (!preferences.quietHoursEnabled) return false
        val value = time.hour * 60 + time.minute
        val start = preferences.quietHoursStart.hour * 60 + preferences.quietHoursStart.minute
        val end = preferences.quietHoursEnd.hour * 60 + preferences.quietHoursEnd.minute
        return if (start <= end) value in start until end else value >= start || value < end
    }

    private fun schedule(requestCode: Int, whenAt: Instant, title: String, body: String, podcastId: String?, channel: String, key: String) {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            putExtra(EXTRA_TITLE, title); putExtra(EXTRA_BODY, body); putExtra(EXTRA_PODCAST_ID, podcastId)
            putExtra(EXTRA_CHANNEL, channel); putExtra(EXTRA_NOTIFICATION_ID, requestCode); putExtra("key", key)
        }
        val pending = PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenAt.toEpochMilli(), pending)
        context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE).edit().putBoolean(requestCode.toString(), true).apply()
    }

    private fun cancelKnownAlarms() {
        val prefs = context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE)
        prefs.all.keys.forEach { key ->
            val code = key.toIntOrNull() ?: return@forEach
            val pending = PendingIntent.getBroadcast(
                context, code, Intent(context, ReminderReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            pending?.let(alarms::cancel)
        }
        prefs.edit().clear().apply()
    }

    companion object {
        const val LEARNING_CHANNEL = "learning_reminders"
        const val SCHEDULED_CHANNEL = "scheduled_episodes"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_PODCAST_ID = "podcast_id"
        const val EXTRA_CHANNEL = "channel"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        private const val ALARM_PREFS = "scheduled_alarm_ids"
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val podcastId = intent.getStringExtra(ReminderScheduler.EXTRA_PODCAST_ID)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(ReminderScheduler.EXTRA_PODCAST_ID, podcastId)
        }
        val requestCode = intent.getIntExtra(ReminderScheduler.EXTRA_NOTIFICATION_ID, 1)
        val pending = PendingIntent.getActivity(context, requestCode, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, intent.getStringExtra(ReminderScheduler.EXTRA_CHANNEL) ?: ReminderScheduler.LEARNING_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(intent.getStringExtra(ReminderScheduler.EXTRA_TITLE) ?: "PodTrackio")
            .setContentText(intent.getStringExtra(ReminderScheduler.EXTRA_BODY))
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(ReminderScheduler.EXTRA_BODY)))
            .setContentIntent(pending).setAutoCancel(true).build()
        NotificationManagerCompat.from(context).notify(requestCode, notification)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val result = goAsync()
        val app = context.applicationContext as com.tangenix.podtrackio.PodTrackioApplication
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            runCatching { app.container.reminders.reschedule() }
            result.finish()
        }
    }
}
