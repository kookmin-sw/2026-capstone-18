package com.littlesignals.capture

import android.Manifest
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import timber.log.Timber

private val Lilac = Color(0xFFB89DDB)
private val Pink = Color(0xFFF8C4D7)
private val Background = Color(0xFFFAF6FB)
private val Plum = Color(0xFF2D2433)
private val PlumDim = Color(0x992D2433)
private val PlumGhost = Color(0x4D2D2433)
private val GreenOk = Color(0xFF66BB6A)
private val OrangeWarn = Color(0xFFFFB74D)

class CaptureActivity : ComponentActivity() {

    private val requestPermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        granted.forEach { (perm, ok) -> Timber.i("permission %s -> %s", perm, ok) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Timber.treeCount == 0) Timber.plant(Timber.DebugTree())
        ensurePermissions()
        setContent { MaterialTheme { CaptureScreen() } }
    }

    private fun ensurePermissions() {
        val needed = if (Build.VERSION.SDK_INT >= 36) listOf(
            "com.samsung.android.hardware.sensormanager.permission.READ_ADDITIONAL_HEALTH_DATA",
            "android.permission.health.READ_HEART_RATE",
            Manifest.permission.ACTIVITY_RECOGNITION,
        ) else listOf(Manifest.permission.BODY_SENSORS)
        val missing = needed.filter {
            ActivityCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) requestPermissions.launch(missing.toTypedArray())
    }

    @Composable
    private fun CaptureScreen() {
        val ui by CaptureState.flow.collectAsState()

        Box(
            modifier = Modifier.fillMaxSize().background(Background),
            contentAlignment = Alignment.Center,
        ) {
            when (ui.state) {
                State.IDLE -> IdleScreen()
                State.CAPTURING -> CapturingScreen(ui)
                State.DONE -> DoneScreen(ui)
                State.ERROR -> ErrorScreen(ui)
            }
        }
    }
}

@Composable
private fun IdleScreen() {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Luma",
            color = Plum,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.sp,
        )
        Spacer(modifier = Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(8.dp).clip(CircleShape).background(GreenOk),
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text("준비됨", color = Plum, fontSize = 11.sp, fontWeight = FontWeight.Medium)
        }
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "휴대폰에서\n캡처를 시작하세요",
            color = PlumDim,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
            lineHeight = 14.sp,
        )
    }
}

@Composable
private fun CapturingScreen(ui: CaptureUiState) {
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
            modifier = Modifier.fillMaxSize().padding(horizontal = 30.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PulsingDot(color = Pink, size = 5.dp)
                Spacer(modifier = Modifier.width(4.dp))
                Text("캡처 중", color = Pink, fontSize = 9.sp, fontWeight = FontWeight.Medium, letterSpacing = 1.sp)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(formatMmSs(ui.elapsedMs), color = Plum, fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
                if (total > 0f) {
                    Text("/ ${formatMmSs(ui.durationMs)}", color = PlumDim, fontSize = 10.sp)
                }
            }
            CountRow(ui)
        }
    }
}

@Composable
private fun DoneScreen(ui: CaptureUiState) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CheckBadge()
        Spacer(modifier = Modifier.height(8.dp))
        Text("완료", color = Plum, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(2.dp))
        Text(formatMmSs(ui.elapsedMs), color = PlumDim, fontSize = 11.sp)
        Spacer(modifier = Modifier.height(8.dp))
        CountRow(ui)
    }
}

@Composable
private fun ErrorScreen(ui: CaptureUiState) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(8.dp).clip(CircleShape).background(OrangeWarn),
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text("오류", color = Plum, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = ui.error ?: "알 수 없음",
            color = PlumDim,
            fontSize = 10.sp,
            textAlign = TextAlign.Center,
        )
    }
}

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
        Text(formatCount(count), color = Plum, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        Text(label, color = PlumGhost, fontSize = 7.sp, letterSpacing = 0.5.sp)
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
            modifier = Modifier.size(48.dp).clip(CircleShape).background(Lilac.copy(alpha = 0.25f)),
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

private fun formatMmSs(ms: Long): String {
    val s = (ms / 1000L).coerceAtLeast(0L)
    return "%d:%02d".format(s / 60L, s % 60L)
}

private fun formatCount(c: Long): String = when {
    c < 1000L -> c.toString()
    c < 10_000L -> "%.1fK".format(c / 1000.0)
    else -> "${c / 1000L}K"
}
