package com.littlesignals.app.health

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.MenstruationPeriodRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

private const val CHANNEL = "littlesignals/health"

object HealthChannels {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var permissionLauncher: ActivityResultLauncher<Set<String>>? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissions: Set<String> = emptySet()

    fun register(activity: ComponentActivity, engine: FlutterEngine) {
        scope.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        permissionLauncher = activity.registerForActivityResult(
            PermissionController.createRequestPermissionResultContract(),
        ) { granted ->
            val result = pendingPermissionResult
            val requested = pendingPermissions
            pendingPermissionResult = null
            pendingPermissions = emptySet()
            result?.success(mapOf("granted" to granted.containsAll(requested)))
        }

        val appContext = activity.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLatestSleepData" -> handleInBackground(result) {
                        fetchLatestSleep(appContext)
                    }
                    "getLatestCycleData" -> handleInBackground(result) {
                        fetchLatestCycle(appContext)
                    }
                    "requestHealthPermissions" -> requestHealthPermissions(
                        appContext,
                        call.argument<String>("kind"),
                        result,
                    )
                    else -> mainHandler.post { result.notImplemented() }
                }
            }
    }

    private fun handleInBackground(
        result: MethodChannel.Result,
        block: suspend () -> Map<String, Any?>?,
    ) {
        scope.launch {
            runCatching { block() }
                .onSuccess { data -> mainHandler.post { result.success(data) } }
                .onFailure { e ->
                    val code = if (e is HealthConnectFailure) e.code else "native_error"
                    mainHandler.post { result.error(code, e.message, null) }
                }
        }
    }

    private fun requestHealthPermissions(
        context: Context,
        kind: String?,
        result: MethodChannel.Result,
    ) {
        if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) {
            result.error("health_connect_unavailable", "Health Connect is not available.", null)
            return
        }

        val permissions = permissionsForKind(kind)
        if (permissions == null) {
            result.error("native_error", "Unknown Health Connect permission kind.", null)
            return
        }

        val launcher = permissionLauncher
        if (launcher == null) {
            result.error("native_error", "Health Connect permission launcher is unavailable.", null)
            return
        }

        if (pendingPermissionResult != null) {
            result.error("native_error", "Another Health Connect permission request is in progress.", null)
            return
        }

        pendingPermissionResult = result
        pendingPermissions = permissions
        launcher.launch(permissions)
    }

    private suspend fun fetchLatestSleep(context: Context): Map<String, Any?>? {
        val client = healthClient(context, sleepPermissions)
        val now = Instant.now()
        val request = ReadRecordsRequest(
            SleepSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.between(now.minus(14, ChronoUnit.DAYS), now),
        )
        val records = client.readRecords(request).records
        val latest = records.maxByOrNull { it.endTime }
            ?: throw HealthConnectFailure("no_data", "No sleep records were found.")
        return mapOf(
            "fell_asleep_at_ms" to latest.startTime.toEpochMilli(),
            "woke_up_at_ms"     to latest.endTime.toEpochMilli(),
            "ended_on_ms"       to latest.endTime.toEpochMilli(),
            "source"            to "Galaxy Watch",
        )
    }

    private suspend fun fetchLatestCycle(context: Context): Map<String, Any?>? {
        val client = healthClient(context, cyclePermissions)
        val now = Instant.now()
        val request = ReadRecordsRequest(
            MenstruationPeriodRecord::class,
            timeRangeFilter = TimeRangeFilter.between(now.minus(90, ChronoUnit.DAYS), now),
        )
        val records = client.readRecords(request).records
        val latest = records.maxByOrNull { it.startTime }
            ?: throw HealthConnectFailure("no_data", "No cycle records were found.")
        return mapOf(
            "period_start_ms"             to latest.startTime.toEpochMilli(),
            "period_end_ms"               to latest.endTime.toEpochMilli(),
            "estimated_cycle_length_days" to null,
            "source"                      to "Galaxy Watch / Samsung Health",
        )
    }

    private suspend fun healthClient(context: Context, requiredPermissions: Set<String>): HealthConnectClient {
        val status = HealthConnectClient.getSdkStatus(context)
        if (status != HealthConnectClient.SDK_AVAILABLE) {
            throw HealthConnectFailure(
                "health_connect_unavailable",
                "Health Connect is not available.",
            )
        }
        val client = HealthConnectClient.getOrCreate(context)
        val granted = client.permissionController.getGrantedPermissions()
        if (!granted.containsAll(requiredPermissions)) {
            throw HealthConnectFailure(
                "permission_denied",
                "Health Connect permissions are missing.",
            )
        }
        return client
    }

    private fun permissionsForKind(kind: String?): Set<String>? {
        return when (kind) {
            "sleep" -> sleepPermissions
            "cycle" -> cyclePermissions
            else -> null
        }
    }

    private val sleepPermissions: Set<String>
        get() = setOf(HealthPermission.getReadPermission(SleepSessionRecord::class))

    private val cyclePermissions: Set<String>
        get() = setOf(HealthPermission.getReadPermission(MenstruationPeriodRecord::class))
}

private class HealthConnectFailure(
    val code: String,
    message: String,
) : RuntimeException(message)
