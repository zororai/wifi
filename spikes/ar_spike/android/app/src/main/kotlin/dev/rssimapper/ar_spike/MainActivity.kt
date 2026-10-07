package dev.rssimapper.ar_spike

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: ArBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val b = ArBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        bridge = b
        flutterEngine.platformViewsController.registry
            .registerViewFactory("spike/ar_view", ArViewFactory(b))
    }

    override fun onResume() {
        super.onResume()
        bridge?.onActivityResume()
    }

    override fun onPause() {
        bridge?.onActivityPause()
        super.onPause()
    }
}
