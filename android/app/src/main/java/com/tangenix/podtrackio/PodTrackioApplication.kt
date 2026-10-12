package com.tangenix.podtrackio

import android.app.Application
import com.tangenix.podtrackio.data.AIRepository
import com.tangenix.podtrackio.data.AuthRepository
import com.tangenix.podtrackio.data.LocalStore
import com.tangenix.podtrackio.data.SecureStore
import com.tangenix.podtrackio.data.SupabaseApi
import com.tangenix.podtrackio.media.DownloadRepository
import com.tangenix.podtrackio.media.PlatformMediaTools
import com.tangenix.podtrackio.notifications.ReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class PodTrackioApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.reminders.createChannels()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            runCatching { container.mediaTools.initialize() }
        }
    }
}

class AppContainer(application: Application) {
    val secureStore = SecureStore(application)
    val localStore = LocalStore(application)
    val auth = AuthRepository(secureStore)
    val supabase = SupabaseApi(auth)
    val ai = AIRepository(secureStore)
    val mediaTools = PlatformMediaTools(application)
    val downloads = DownloadRepository(application, mediaTools)
    val reminders = ReminderScheduler(application, localStore)
}
