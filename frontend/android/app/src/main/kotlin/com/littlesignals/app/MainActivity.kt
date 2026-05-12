package com.littlesignals.app

import com.littlesignals.app.capture.CaptureChannels
import com.littlesignals.app.health.HealthChannels
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CaptureChannels.register(this, flutterEngine)
        HealthChannels.register(this, flutterEngine)
    }
}
