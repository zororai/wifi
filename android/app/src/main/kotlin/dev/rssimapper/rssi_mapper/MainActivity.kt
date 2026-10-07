package dev.rssimapper.rssi_mapper

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var wifiBridge: WifiBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiBridge = WifiBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wifiBridge?.dispose()
        wifiBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
