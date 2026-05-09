package com.littlesignals.capture

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import timber.log.Timber

// Luma brand palette — keeps the watch UI visually consistent with the phone app.
private val Lilac = Color(0xFFB89DDB)
private val Pink = Color(0xFFF8C4D7)
private val Background = Color(0xFFFAF6FB)
private val Plum = Color(0xFF2D2433)
private val PlumDim = Color(0x992D2433)
private val PlumGhost = Color(0x4D2D2433)

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

        Box(
            modifier = Modifier.fillMaxSize().background(Background),
            contentAlignment = Alignment.Center,
        ) {
            when (ui.state) {
                State.IDLE -> IdleScreen(
                    selectedMs = selectedDurationMs,
                    onSelect = { selectedDurationMs = it },
                    onStart = { startCapture(selectedDurationMs) },
                )
                State.CAPTURING -> CapturingScreen(ui = ui, onStop = { stopCapture() })
                State.DONE -> DoneScreen(ui = ui, onReset = {
                    CaptureState.flow.value = CaptureUiState()
                })
                State.ERROR -> ErrorScreen(ui = ui, onReset = {
                    CaptureState.flow.value = CaptureUiState()
                })
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

// ─── Screens ─────────────────────────────────────────────────────────────────

@Composable
private fun IdleScreen(
    selectedMs: Long?,
    onSelect: (Long?) -> Unit,
    onStart: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Little Signals",
            color = Plum,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            letterSpacing = 1.sp,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "캡처",
            color = Plum,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(14.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            DurationChip("10분", selectedMs == 10L * 60_000L) { onSelect(10L * 60_000L) }
            DurationChip("30분", selectedMs == 30L * 60_000L) { onSelect(30L * 60_000L) }
            DurationChip("∞", selectedMs == null) { onSelect(null) }
        }
        Spacer(modifier = Modifier.height(14.dp))
        GradientPillButton(label = "캡처 시작", onClick = onStart)
    }
}

@Composable
private fun CapturingScreen(ui: CaptureUiState, onStop: () -> Unit) {
    val total = if (ui.durationMs > 0) ui.durationMs.toFloat() else -1f
    val progress = if (total > 0f) (ui.elapsedMs.toFloat() / total).coerceIn(0f, 1f) else 0f
    val animatedProgress by animateFloatAsState(
        targetValue = progress,
        animationSpec = tween(durationMillis = 600, easing = LinearEasing),
        label = "progress",
    )

    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize().padding(8.dp)) {
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
            val sweep = if (total > 0f) 360f * animatedProgress else 360f
            drawArc(
                brush = Brush.sweepGradient(listOf(Lilac, Pink, Lilac)),
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = false,
                style = Stroke(width = stroke, cap = StrokeCap.Round),
                topLeft = Offset(stroke / 2, stroke / 2),
                size = Size(size.width - stroke, size.height - stroke),
            )
        }

        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 26.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(
                modifier = Modifier.padding(top = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PulsingDot(color = Pink, size = 5.dp)
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "캡처 중",
                    color = Pink,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 1.sp,
                )
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = formatMmSs(ui.elapsedMs),
                    color = Plum,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                if (total > 0f) {
                    Text(
                        text = "/ ${formatMmSs(ui.durationMs)}",
                        color = PlumDim,
                        fontSize = 10.sp,
                    )
                }
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CountRow(ui)
                Spacer(modifier = Modifier.height(8.dp))
                StopPillButton(onClick = onStop)
            }
        }
    }
}

@Composable
private fun DoneScreen(ui: CaptureUiState, onReset: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CheckBadge()
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "완료",
            color = Plum,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(2.dp))
        Text(
            text = formatMmSs(ui.elapsedMs),
            color = PlumDim,
            fontSize = 11.sp,
        )
        Spacer(modifier = Modifier.height(8.dp))
        CountRow(ui)
        Spacer(modifier = Modifier.height(12.dp))
        GhostPillButton(label = "다시", onClick = onReset)
    }
}

@Composable
private fun ErrorScreen(ui: CaptureUiState, onReset: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "오류",
            color = Plum,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = ui.error ?: "알 수 없는 오류",
            color = PlumDim,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(12.dp))
        GhostPillButton(label = "다시 시도", onClick = onReset)
    }
}

// ─── Reusable bits ───────────────────────────────────────────────────────────

@Composable
private fun CountRow(ui: CaptureUiState) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        CountTile("HR", ui.hrCount)
        CountTile("PPG", ui.ppgCount)
        CountTile("EDA", ui.edaCount)
        CountTile("ACC", ui.accelCount)
    }
}

@Composable
private fun CountTile(label: String, count: Long) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = formatCount(count),
            color = Plum,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = label,
            color = PlumGhost,
            fontSize = 7.sp,
            letterSpacing = 0.5.sp,
        )
    }
}

@Composable
private fun DurationChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected)
        Brush.linearGradient(listOf(Lilac, Pink))
    else
        Brush.linearGradient(listOf(Color.Transparent, Color.Transparent))
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .border(1.dp, if (selected) Color.Transparent else Lilac.copy(alpha = 0.5f), RoundedCornerShape(50))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else Plum,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun GradientPillButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Brush.linearGradient(listOf(Lilac, Pink)))
            .clickable(onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = Color.White,
            fontSize = 13.sp,
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
            .padding(horizontal = 14.dp, vertical = 7.dp),
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
private fun StopPillButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color(0xFFE57373))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "중지",
            color = Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
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
    Box(modifier = Modifier.size(48.dp), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(Lilac.copy(alpha = 0.25f)),
        )
        Canvas(modifier = Modifier.size(48.dp)) {
            val stroke = 3.dp.toPx()
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

private fun formatMmSs(elapsedMs: Long): String {
    val totalSec = (elapsedMs / 1000L).coerceAtLeast(0L)
    val mm = totalSec / 60L
    val ss = totalSec % 60L
    return "%d:%02d".format(mm, ss)
}

private fun formatCount(count: Long): String = when {
    count < 1000L -> count.toString()
    count < 10_000L -> "%.1fK".format(count / 1000.0)
    else -> "${count / 1000L}K"
}
