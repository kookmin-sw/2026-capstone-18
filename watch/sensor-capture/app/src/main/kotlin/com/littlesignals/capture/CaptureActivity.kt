package com.littlesignals.capture

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import timber.log.Timber

class CaptureActivity : ComponentActivity() {

    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        granted.forEach { (perm, ok) -> Timber.i("permission %s -> %s", perm, ok) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
        setContent { MaterialTheme { CaptureScreen() } }
    }

    @Composable
    private fun CaptureScreen() {
        val ui by CaptureState.flow.collectAsState()
        var selectedDurationMs by remember { mutableStateOf<Long?>(10L * 60_000L) }

        Column(
            modifier = Modifier.fillMaxSize().padding(8.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val mm = (ui.elapsedMs / 60_000L).toInt().toString().padStart(2, '0')
            val ss = ((ui.elapsedMs / 1000L) % 60L).toInt().toString().padStart(2, '0')
            Text("${ui.state} $mm:$ss")
            Text("HR ${ui.hrCount} · PPG ${ui.ppgCount} · EDA ${ui.edaCount} · ACC ${ui.accelCount}")

            if (ui.state != State.CAPTURING) {
                Text("지속 시간")
                Button(onClick = { selectedDurationMs = 10L * 60_000L }) {
                    Text(if (selectedDurationMs == 10L * 60_000L) "[10분]" else "10분")
                }
                Button(onClick = { selectedDurationMs = 30L * 60_000L }) {
                    Text(if (selectedDurationMs == 30L * 60_000L) "[30분]" else "30분")
                }
                Button(onClick = { selectedDurationMs = null }) {
                    Text(if (selectedDurationMs == null) "[무제한]" else "무제한")
                }
                Button(onClick = { startCapture(selectedDurationMs) }) { Text("Start") }
            } else {
                Button(onClick = { stopCapture() }) { Text("Stop") }
            }
        }
    }

    private fun startCapture(durationMs: Long?) {
        if (!checkPermissions()) {
            requestMissingPermissions()
            return
        }
        val intent = Intent(this, BiosignalCaptureService::class.java).apply {
            action = BiosignalCaptureService.ACTION_START
            putExtra(BiosignalCaptureService.EXTRA_DURATION_MS, durationMs ?: -1L)
        }
        startForegroundService(intent)
    }

    private fun stopCapture() {
        val intent = Intent(this, BiosignalCaptureService::class.java).apply {
            action = BiosignalCaptureService.ACTION_STOP
        }
        startService(intent)
    }

    private fun requiredPermissions(): List<String> = if (Build.VERSION.SDK_INT >= 36) listOf(
        "com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA",
        "android.permission.health.READ_HEART_RATE",
        Manifest.permission.ACTIVITY_RECOGNITION,
    ) else listOf(Manifest.permission.BODY_SENSORS)

    private fun checkPermissions(): Boolean = requiredPermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestMissingPermissions() {
        val missing = requiredPermissions().filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) requestPermissions.launch(missing.toTypedArray())
    }
}
