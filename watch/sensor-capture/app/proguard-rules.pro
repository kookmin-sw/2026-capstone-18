# Samsung Health Sensor SDK reflectively reaches into ValueKey + DataPoint.
# Keep its public surface untouched in release builds.
-keep class com.samsung.android.service.health.tracking.** { *; }
