package com.tangenix.podtrackio

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import com.tangenix.podtrackio.ui.PodTrackioApp
import com.tangenix.podtrackio.ui.theme.PodTrackioTheme

class MainActivity : ComponentActivity() {
    private val viewModel by viewModels<PodTrackioViewModel> {
        PodTrackioViewModel.Factory((application as PodTrackioApplication).container)
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        com.tangenix.podtrackio.ui.play.PlayFeedback.init(applicationContext)
        consumeCallback(intent)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            val ui by viewModel.ui.collectAsState()
            val auth by viewModel.auth.collectAsState()
            PodTrackioTheme(ui.snapshot.theme) {
                PodTrackioApp(viewModel = viewModel, ui = ui, auth = auth)
            }
        }
    }

    override fun onStop() { viewModel.checkpoint(); super.onStop() }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeCallback(intent)
    }

    private fun consumeCallback(intent: Intent?) {
        if (BuildConfig.DEBUG && intent?.getBooleanExtra("demo", false) == true) lifecycleScope.launch {
            viewModel.ui.first { it.loaded }
            kotlinx.coroutines.delay(300)
            viewModel.enableDemoMode()
            when (intent.getStringExtra("moment")) {
                "streak" -> viewModel.enqueue(Moment.StreakExtended)
                "chest" -> viewModel.enqueue(Moment.Chest(10))
                "level" -> viewModel.enqueue(Moment.LevelUp)
                "session" -> viewModel.enqueue(Moment.Session(840.0, 26, 2, 1f))
                "freeze" -> viewModel.enqueue(Moment.FreezeSaved(12))
            }
            intent.getStringExtra("section")?.let { name -> AppSection.entries.firstOrNull { it.name == name }?.let(viewModel::selectSection) }
        }
        if (intent?.hasExtra("podcast_id") == true || intent?.getBooleanExtra("learning_five_minutes", false) == true) {
            viewModel.openLearningIntent(intent.getStringExtra("podcast_id"), intent.getBooleanExtra("learning_five_minutes", false))
            intent.removeExtra("podcast_id"); intent.removeExtra("learning_five_minutes")
        }
        intent?.data?.takeIf { it.scheme == "podtrackio" && it.host == "auth-callback" }
            ?.let(viewModel::handleAuthCallback)
    }
}
