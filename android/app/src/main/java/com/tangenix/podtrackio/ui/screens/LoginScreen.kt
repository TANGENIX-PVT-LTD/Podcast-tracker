package com.tangenix.podtrackio.ui.screens

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tangenix.podtrackio.PodTrackioViewModel
import com.tangenix.podtrackio.BuildConfig
import com.tangenix.podtrackio.R
import com.tangenix.podtrackio.data.AuthState

@Composable
fun LoginScreen(viewModel: PodTrackioViewModel, auth: AuthState) {
    val context = LocalContext.current
    Box(Modifier.fillMaxSize().padding(36.dp), contentAlignment = Alignment.Center) {
        Card(shape = RoundedCornerShape(32.dp), modifier = Modifier.fillMaxWidth(.72f)) {
            Row(Modifier.padding(40.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Image(
                        painter = painterResource(R.drawable.podtrackio_logo),
                        contentDescription = "PodTrackio logo",
                        modifier = Modifier.height(88.dp),
                    )
                    Text(
                        "PodTrackio",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text("Turn watching into learning.", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
                    Text(
                        "Your library, playback position, notes, goals and learning briefs follow you between PodTrackio on macOS and Android.",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(44.dp))
                Column(Modifier.weight(.72f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Welcome to PodTrackio", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text("Sign into the same account you use on your Mac.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, viewModel.oauthUri("google"))) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                    ) { Text("Continue with Google") }
                    OutlinedButton(
                        onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, viewModel.oauthUri("apple"))) },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Continue with Apple") }
                    if (BuildConfig.DEBUG) {
                        TextButton(onClick = viewModel::enableDemoMode, modifier = Modifier.fillMaxWidth()) { Text("Preview tablet workspace") }
                    }
                    auth.error?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                        OutlinedButton(onClick = viewModel::clearAuthError) { Text("Dismiss") }
                    }
                }
            }
        }
        if (auth.restoring) CircularProgressIndicator()
    }
}
