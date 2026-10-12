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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeCallback(intent)
    }

    private fun consumeCallback(intent: Intent?) {
        intent?.data?.takeIf { it.scheme == "podtrackio" && it.host == "auth-callback" }
            ?.let(viewModel::handleAuthCallback)
    }
}
