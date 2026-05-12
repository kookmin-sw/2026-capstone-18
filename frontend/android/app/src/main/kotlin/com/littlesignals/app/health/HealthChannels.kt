package com.littlesignals.app.health

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.MenstruationPeriodRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

private const val CHANNEL = "littlesignals/health"

object HealthChannels {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLatestSleepData" -> handleInBackground(result) {
                        fetchLatestSleep(appContext)
                    }
                    "getLatestCycleData" -> handleInBackground(result) {
                        fetchLatestCycle(appContext)
                    }
                    else -> mainHandler.post { result.notImplemented() }
                }
            }
    }

    private fun handleInBackground(
        result: MethodChannel.Result,
        block: suspend () -> Map<String, Any?>?,
    ) {
        GlobalScope.launch(Dispatchers.IO) {
            runCatching { block() }
                .onSuccess { data -> mainHandler.post { result.success(data) } }
                .onFailure { e -> mainHandler.post { result.error("health_connect_error", e.message, null) } }
        }
    }

    private suspend fun fetchLatestSleep(context: Context): Map<String, Any?>? {
        val client = healthClient(context) ?: return null
        val now = Instant.now()
        val request = ReadRecordsRequest(
            SleepSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.between(now.minus(14, ChronoUnit.DAYS), now),
        )
        val records = client.readRecords(request).records
        val latest = records.maxByOrNull { it.endTime } ?: return null
        return mapOf(
            "fell_asleep_at_ms" to latest.startTime.toEpochMilli(),
            "woke_up_at_ms"     to latest.endTime.toEpochMilli(),
            "ended_on_ms"       to latest.endTime.toEpochMilli(),
            "source"            to "Galaxy Watch",
        )
    }

    private suspend fun fetchLatestCycle(context: Context): Map<String, Any?>? {
        val client = healthClient(context) ?: return null
        val now = Instant.now()
        val request = ReadRecordsRequest(
            MenstruationPeriodRecord::class,
            timeRangeFilter = TimeRangeFilter.between(now.minus(90, ChronoUnit.DAYS), now),
        )
        val records = client.readRecords(request).records
        val latest = records.maxByOrNull { it.startTime } ?: return null
        return mapOf(
            "period_start_ms"             to latest.startTime.toEpochMilli(),
            "period_end_ms"               to latest.endTime.toEpochMilli(),
            "estimated_cycle_length_days" to null,
            "source"                      to "Galaxy Watch / Samsung Health",
        )
    }

    private fun healthClient(context: Context): HealthConnectClient? {
        val status = HealthConnectClient.getSdkStatus(context)
        if (status != HealthConnectClient.SDK_AVAILABLE) return null
        return HealthConnectClient.getOrCreate(context)
    }
}
