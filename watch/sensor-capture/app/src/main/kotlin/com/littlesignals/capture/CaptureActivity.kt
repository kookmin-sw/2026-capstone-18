package com.littlesignals.capture

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import androidx.compose.runtime.collectAsState
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

private const val DURATION_MIN = 10
private val DURATION_MS = DURATION_MIN * 60 * 1000L

// Luma brand palette
private val Lilac = Color(0xFFB89DDB)
private val Pink = Color(0xFFF8C4D7)
private val Background = Color(0xFFFAF6FB)
private val Plum = Color(0xFF2D2433)
private val PlumDim = Color(0x992D2433) // 60%
private val PlumGhost = Color(0x4D2D2433) // 30%
private val LilacChip = Color(0xCCB89DDB) // 80%

class CaptureActivity : ComponentActivity() {

    private val live = MutableStateFlow(LiveSnapshot())

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
                CaptureScreen(live = live, capture = ::startCapture)
            }
        }
    }

    private fun ensurePermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 36) {
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
        live.value = LiveSnapshot()
        val zip = withContext(Dispatchers.IO) {
            CaptureSession(this@CaptureActivity, live).run(DURATION_MS, onProgress)
        }
        return zip.absolutePath
    }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

private sealed class Status {
    data object Idle : Status()
    data object Connecting : Status()
    data class Capturing(val remainingSec: Int) : Status()
    data class Done(val path: String) : Status()
    data class Error(val message: String) : Status()
}

// ---------------------------------------------------------------------------
// Top-level screen
// ---------------------------------------------------------------------------

@Composable
private fun CaptureScreen(
    live: StateFlow<LiveSnapshot>,
    capture: suspend ((Int) -> Unit) -> String,
) {
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<Status>(Status.Idle) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Background),
        contentAlignment = Alignment.Center,
    ) {
        when (val s = status) {
            is Status.Idle -> IdleScreen(onStart = {
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
            })
            is Status.Connecting -> ConnectingScreen()
            is Status.Capturing -> CapturingScreen(remainingSec = s.remainingSec, live = live)
            is Status.Done -> DoneScreen(onReset = { status = Status.Idle })
            is Status.Error -> ErrorScreen(message = s.message, onReset = { status = Status.Idle })
        }
    }
}

// ---------------------------------------------------------------------------
// Idle
// ---------------------------------------------------------------------------

@Composable
private fun IdleScreen(onStart: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Image(
            painter = painterResource(id = R.mipmap.ic_launcher),
            contentDescription = null,
            modifier = Modifier.size(36.dp),
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Little Signals",
            color = Plum,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = 1.sp,
        )
        Spacer(modifier = Modifier.height(18.dp))
        GradientPillButton(
            label = "Start ${DURATION_MIN} min",
            onClick = onStart,
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = "HR · PPG · EDA · Accel",
            color = PlumDim,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
        )
    }
}

// ---------------------------------------------------------------------------
// Connecting
// ---------------------------------------------------------------------------

@Composable
private fun ConnectingScreen() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        PulsingDot(color = Lilac, size = 10.dp)
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = "Connecting",
            color = Plum,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "Health Platform",
            color = PlumDim,
            fontSize = 10.sp,
        )
    }
}

// ---------------------------------------------------------------------------
// Capturing — live data hero screen
// ---------------------------------------------------------------------------

@Composable
private fun CapturingScreen(remainingSec: Int, live: StateFlow<LiveSnapshot>) {
    val total = DURATION_MIN * 60
    val elapsed = (total - remainingSec).coerceAtLeast(0)
    val targetProgress = (elapsed.toFloat() / total).coerceIn(0f, 1f)
    val progress by animateFloatAsState(
        targetValue = targetProgress,
        animationSpec = tween(durationMillis = 600, easing = LinearEasing),
        label = "progress",
    )

    val snapshot by live.collectAsState()

    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        // Outer thin progress arc — time remaining
        Canvas(modifier = Modifier.fillMaxSize().padding(10.dp)) {
            val stroke = 4.dp.toPx()
            drawArc(
                color = Color(0x22B89DDB),
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
                topLeft = Offset(stroke / 2, stroke / 2),
                size = Size(size.width - stroke, size.height - stroke),
            )
            drawArc(
                brush = Brush.sweepGradient(listOf(Lilac, Pink, Lilac)),
                startAngle = -90f,
                sweepAngle = 360f * progress,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
                topLeft = Offset(stroke / 2, stroke / 2),
                size = Size(size.width - stroke, size.height - stroke),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 30.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            // Top: status + countdown
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    PulsingDot(color = Pink, size = 5.dp)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Recording",
                        color = Pink,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Medium,
                        letterSpacing = 1.sp,
                    )
                }
                Text(
                    text = formatMmSs(remainingSec),
                    color = Plum,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            // Hero: PPG sparkline (the actual photoplethysmograph waveform)
            PpgSparkline(
                points = snapshot.ppgRecent,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
            )

            // Bottom: live HR + EDA + motion
            LiveStatsRow(snapshot = snapshot)
        }
    }
}

@Composable
private fun PpgSparkline(points: List<Int>, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier) {
        if (points.size < 2) return@Canvas
        val w = size.width
        val h = size.height
        val mn = points.min()
        val mx = points.max()
        val range = (mx - mn).coerceAtLeast(1)
        val stepX = w / (LiveSnapshot.PPG_WINDOW_SIZE - 1).toFloat()

        // Right-anchor the line so newer samples appear on the right
        val startIndex = LiveSnapshot.PPG_WINDOW_SIZE - points.size

        val path = Path()
        points.forEachIndexed { i, v ->
            val x = (startIndex + i) * stepX
            val norm = (v - mn).toFloat() / range
            val y = h - (norm * h * 0.85f) - h * 0.075f
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        // Subtle glow underlay
        drawPath(
            path = path,
            brush = Brush.linearGradient(listOf(Lilac.copy(alpha = 0.25f), Pink.copy(alpha = 0.25f))),
            style = Stroke(width = 6.dp.toPx(), cap = StrokeCap.Round),
        )
        drawPath(
            path = path,
            brush = Brush.linearGradient(listOf(Lilac, Pink)),
            style = Stroke(width = 2.5.dp.toPx(), cap = StrokeCap.Round),
        )
    }
}

@Composable
private fun LiveStatsRow(snapshot: LiveSnapshot) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HrTile(bpm = snapshot.hrBpm, tickMs = snapshot.hrTickMs)
        EdaTile(us = snapshot.edaUs)
        MotionTile(magnitude = snapshot.accelMag)
    }
}

@Composable
private fun HrTile(bpm: Int?, tickMs: Long) {
    // Spike scale on each new HR sample
    var pulse by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(tickMs) {
        if (tickMs > 0) {
            pulse = 1f
            delay(180)
            pulse = 0f
        }
    }
    val scale by animateFloatAsState(
        targetValue = 1f + pulse * 0.35f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "hr-pulse",
    )

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = "♥",
            color = Pink,
            fontSize = 14.sp,
            modifier = Modifier.scale(scale),
        )
        Text(
            text = bpm?.toString() ?: "—",
            color = Plum,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "BPM",
            color = PlumGhost,
            fontSize = 7.sp,
            letterSpacing = 0.5.sp,
        )
    }
}

@Composable
private fun EdaTile(us: Float?) {
    // EDA values are typically 0.5–10 µS; animate the bar fill smoothly
    val target = us?.coerceIn(0f, 10f)?.div(10f) ?: 0f
    val fill by animateFloatAsState(
        targetValue = target,
        animationSpec = tween(durationMillis = 600, easing = LinearEasing),
        label = "eda-fill",
    )

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Canvas(modifier = Modifier.size(width = 28.dp, height = 4.dp)) {
            val r = size.height / 2
            // Track
            drawRoundRect(
                color = Lilac.copy(alpha = 0.2f),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(r, r),
            )
            // Fill
            if (fill > 0f) {
                drawRoundRect(
                    brush = Brush.horizontalGradient(listOf(Lilac, Pink)),
                    size = Size(size.width * fill, size.height),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(r, r),
                )
            }
        }
        Spacer(modifier = Modifier.height(3.dp))
        Text(
            text = us?.let { "%.2f".format(it) } ?: "—",
            color = Plum,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "µS EDA",
            color = PlumGhost,
            fontSize = 7.sp,
            letterSpacing = 0.5.sp,
        )
    }
}

@Composable
private fun MotionTile(magnitude: Float?) {
    // Map magnitude to a 0..1 motion level. Galaxy Watch reports raw integer
    // axes; resting magnitude is roughly 4000 (gravity), motion bumps that up.
    val level = magnitude?.let {
        ((it - 3500f) / 4000f).coerceIn(0f, 1f)
    } ?: 0f
    val animated by animateFloatAsState(
        targetValue = level,
        animationSpec = tween(durationMillis = 200, easing = LinearEasing),
        label = "motion-level",
    )

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Canvas(modifier = Modifier.size(14.dp)) {
            val r = (size.minDimension / 2f) * (0.4f + 0.6f * animated)
            drawCircle(
                brush = Brush.radialGradient(listOf(Pink, Lilac)),
                radius = r,
                center = center,
            )
        }
        Spacer(modifier = Modifier.height(3.dp))
        Text(
            text = magnitude?.let { "%.0f".format(it) } ?: "—",
            color = Plum,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "MOTION",
            color = PlumGhost,
            fontSize = 7.sp,
            letterSpacing = 0.5.sp,
        )
    }
}

// ---------------------------------------------------------------------------
// Done
// ---------------------------------------------------------------------------

@Composable
private fun DoneScreen(onReset: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CheckBadge()
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = "All done",
            color = Plum,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "${DURATION_MIN}:00 · 4 channels",
            color = PlumDim,
            fontSize = 10.sp,
        )
        Spacer(modifier = Modifier.height(14.dp))
        GhostPillButton(
            label = "New capture",
            onClick = onReset,
        )
    }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

@Composable
private fun ErrorScreen(message: String, onReset: () -> Unit) {
    Column(
        modifier = Modifier.padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Couldn't record",
            color = Plum,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = message,
            color = PlumDim,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(14.dp))
        GhostPillButton(label = "Try again", onClick = onReset)
    }
}

// ---------------------------------------------------------------------------
// Reusable components
// ---------------------------------------------------------------------------

@Composable
private fun GradientPillButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Brush.linearGradient(listOf(Lilac, Pink)))
            .clickable(onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun GhostPillButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .border(1.dp, Lilac, RoundedCornerShape(50))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = Lilac,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun PulsingDot(color: Color, size: Dp) {
    val transition = rememberInfiniteTransition(label = "pulse")
    val alpha by transition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse-alpha",
    )
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(color.copy(alpha = alpha)),
    )
}

@Composable
private fun CheckBadge() {
    Box(
        modifier = Modifier.size(64.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(Lilac.copy(alpha = 0.25f)),
        )
        Canvas(modifier = Modifier.size(64.dp)) {
            val stroke = 4.dp.toPx()
            val w = size.width
            val h = size.height
            val path = Path().apply {
                moveTo(w * 0.30f, h * 0.52f)
                lineTo(w * 0.45f, h * 0.66f)
                lineTo(w * 0.72f, h * 0.38f)
            }
            drawPath(
                path = path,
                brush = Brush.linearGradient(listOf(Lilac, Pink)),
                style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private fun formatMmSs(totalSeconds: Int): String {
    val s = totalSeconds.coerceAtLeast(0)
    val mm = s / 60
    val ss = s % 60
    return "%d:%02d".format(mm, ss)
}
