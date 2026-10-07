package dev.rssimapper.wifi_spike

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WifiProbe(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
