package com.littlesignals.capture

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

private const val DURATION_MIN = 10
private val DURATION_MS = DURATION_MIN * 60 * 1000L

class CaptureActivity : ComponentActivity() {

    private val requestPermissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            granted.forEach { (perm, ok) ->
                Timber.i("permission %s -> %s", perm, ok)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())

        // Keep the screen on for the entire capture so Wear OS doesn't recreate
        // the activity mid-run (which cancels the coroutine and creates a new
        // capture directory each time).
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        ensurePermissions()

        setContent {
            MaterialTheme {
                CaptureScreen(::startCapture)
            }
        }
    }

    private fun ensurePermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 36) {
            // Android 16+ per-tracker permissions:
            //   PPG/EDA  → READ_ADDITIONAL_HEALTH_DATA
            //   HR       → Health Connect READ_HEART_RATE
            //   ACCEL    → ACTIVITY_RECOGNITION
            needed += "com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA"
            needed += "android.permission.health.READ_HEART_RATE"
            needed += Manifest.permission.ACTIVITY_RECOGNITION
        } else {
            needed += Manifest.permission.BODY_SENSORS
        }
        val missing = needed.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) requestPermissions.launch(missing.toTypedArray())
    }

    private suspend fun startCapture(onProgress: (Int) -> Unit): String {
        val zip = withContext(Dispatchers.IO) {
            CaptureSession(this@CaptureActivity).run(DURATION_MS, onProgress)
        }
        return zip.absolutePath
    }
}

@Composable
private fun CaptureScreen(
    capture: suspend ((Int) -> Unit) -> String,
) {
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<Status>(Status.Idle) }

    Column(
        modifier = Modifier.fillMaxSize().padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        when (val s = status) {
            is Status.Idle -> {
                Button(onClick = {
                    scope.launch {
                        status = Status.Connecting
                        try {
                            val path = capture { remaining ->
                                status = Status.Capturing(remaining)
                            }
                            status = Status.Done(path)
                        } catch (t: Throwable) {
                            Timber.e(t, "capture failed")
                            status = Status.Error(t.message ?: t::class.java.simpleName)
                        }
                    }
                }) {
                    Text("Start ${DURATION_MIN} min")
                }
            }
            is Status.Connecting -> Text("Connecting…")
            is Status.Capturing -> Text("Capturing — ${s.remainingSec}s left")
            is Status.Done -> Text("Done\n${s.path.takeLast(40)}")
            is Status.Error -> Text("Error: ${s.message}")
        }
    }
}

private sealed class Status {
    data object Idle : Status()
    data object Connecting : Status()
    data class Capturing(val remainingSec: Int) : Status()
    data class Done(val path: String) : Status()
    data class Error(val message: String) : Status()
}
