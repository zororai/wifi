package dev.rssimapper.wifi_spike

import android.Manifest
import android.annotation.TargetApi
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.time.Instant

/**
 * Phase 0 spike: measures what Android actually exposes for Wi-Fi RSSI.
 *
 * Deliberately reports raw platform values. Unavailable values are sent as null,
 * never replaced with fake numbers (WifiInfo reports -127 when RSSI is invalid;
 * that sentinel is forwarded as null plus a flag).
 */
class WifiProbe(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val wifi =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, "spike/wifi").setMethodCallHandler(this)
        EventChannel(messenger, "spike/wifi/scanEvents").setStreamHandler(ScanEventsHandler())
        EventChannel(messenger, "spike/wifi/connected").setStreamHandler(ConnectedHandler())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "deviceInfo" -> result.success(deviceInfo())
                "startScan" -> result.success(startScan())
                "scanResults" -> result.success(scanResults())
                "legacyConnectionInfo" -> result.success(legacyConnectionInfo())
                "openLocationSettings" -> {
                    openSettings(Settings.ACTION_LOCATION_SOURCE_SETTINGS); result.success(null)
                }
                "openWifiSettings" -> {
                    openSettings(Settings.ACTION_WIFI_SETTINGS); result.success(null)
                }
                "saveText" -> {
                    val name = call.argument<String>("name")!!
                    val content = call.argument<String>("content")!!
                    val dir = context.getExternalFilesDir(null) ?: context.filesDir
                    val file = File(dir, name)
                    file.writeText(content)
                    result.success(file.absolutePath)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("SECURITY", e.message, null)
        } catch (e: Exception) {
            result.error("FAILED", e.toString(), null)
        }
    }

    private fun granted(p: String) =
        context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun deviceInfo(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "sdkInt" to Build.VERSION.SDK_INT,
        "release" to Build.VERSION.RELEASE,
        "targetSdk" to context.applicationInfo.targetSdkVersion,
        "wifiEnabled" to wifi.isWifiEnabled,
        "locationEnabled" to isLocationEnabled(),
        // API 30+: reflects Developer options > "Wi-Fi scan throttling".
        "scanThrottleEnabled" to
            if (Build.VERSION.SDK_INT >= 30) wifi.isScanThrottleEnabled else null,
        "perm.fineLocation" to granted(Manifest.permission.ACCESS_FINE_LOCATION),
        "perm.coarseLocation" to granted(Manifest.permission.ACCESS_COARSE_LOCATION),
        "perm.nearbyWifi" to
            if (Build.VERSION.SDK_INT >= 33) granted(Manifest.permission.NEARBY_WIFI_DEVICES)
            else null,
        "perm.wifiState" to granted(Manifest.permission.ACCESS_WIFI_STATE),
        "perm.changeWifiState" to granted(Manifest.permission.CHANGE_WIFI_STATE),
    )

    private fun isLocationEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= 28) {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            lm.isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(
                context.contentResolver, Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF
            ) != Settings.Secure.LOCATION_MODE_OFF
        }
    }

    /**
     * WifiManager.startScan() is deprecated since API 28 with no replacement.
     * It returns false when the request is rejected (e.g. throttled).
     */
    private fun startScan(): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val accepted = wifi.startScan()
        return mapOf(
            "accepted" to accepted,
            "elapsedMs" to SystemClock.elapsedRealtime(),
            "wallUs" to wallUs(),
        )
    }

    private fun scanResults(): List<Map<String, Any?>> {
        val nowUs = SystemClock.elapsedRealtimeNanos() / 1000
        return wifi.scanResults.map { r -> scanResultMap(r, nowUs) }
    }

    private fun scanResultMap(r: ScanResult, nowUs: Long): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val ssid = r.SSID
        return mapOf(
            "ssid" to ssid,
            "bssid" to r.BSSID,
            "rssi" to r.level,
            "frequencyMhz" to r.frequency,
            "capabilities" to r.capabilities,
            "channelWidth" to r.channelWidth,
            "wifiStandard" to if (Build.VERSION.SDK_INT >= 30) r.wifiStandard else null,
            // ScanResult.timestamp is microseconds since boot when the AP was last seen.
            "timestampUs" to r.timestamp,
            "ageMs" to (nowUs - r.timestamp) / 1000,
        )
    }

    /** Deprecated since API 31; isolated here only for comparison with the callback path. */
    private fun legacyConnectionInfo(): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val info: WifiInfo? = wifi.connectionInfo
        return if (info == null) mapOf("source" to "legacyPoll", "noInfo" to true)
        else wifiInfoMap(info, "legacyPoll")
    }

    private fun wifiInfoMap(info: WifiInfo, source: String): Map<String, Any?> {
        val rssi = info.rssi
        // -127 is WifiInfo's invalid-RSSI sentinel: forward as unavailable, never as a value.
        val rssiValid = rssi > -127 && rssi < 0
        return mapOf(
            "source" to source,
            "rssi" to if (rssiValid) rssi else null,
            "rssiRaw" to rssi,
            "rssiValid" to rssiValid,
            "bssid" to info.bssid,
            "ssid" to info.ssid,
            "frequencyMhz" to info.frequency,
            "linkSpeedMbps" to info.linkSpeed,
            "elapsedMs" to SystemClock.elapsedRealtime(),
            "wallUs" to wallUs(),
        )
    }

    private fun openSettings(action: String) {
        context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun registerSystemReceiver(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= 33) {
            // System broadcasts are still delivered to non-exported receivers.
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun wallUs(): Long {
        val now = Instant.now()
        return now.epochSecond * 1_000_000L + now.nano / 1000
    }

    /** Emits every SCAN_RESULTS_AVAILABLE broadcast, including updated=false (failed scan). */
    private inner class ScanEventsHandler : EventChannel.StreamHandler {
        private var receiver: BroadcastReceiver? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    val updated = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                    val payload = mutableMapOf<String, Any?>(
                        "updated" to updated,
                        "elapsedMs" to SystemClock.elapsedRealtime(),
                        "wallUs" to wallUs(),
                    )
                    try {
                        payload["results"] = scanResults()
                    } catch (e: SecurityException) {
                        payload["resultsError"] = e.message
                    }
                    events.success(payload)
                }
            }
            registerSystemReceiver(r, IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION))
            receiver = r
        }

        override fun onCancel(arguments: Any?) {
            receiver?.let { context.unregisterReceiver(it) }
            receiver = null
        }
    }

    /**
     * Streams connected-network observations from three independent sources so their
     * update cadence can be compared on a real device:
     *  - "callback": NetworkCallback.onCapabilitiesChanged -> transportInfo (API 29+),
     *    with FLAG_INCLUDE_LOCATION_INFO on API 31+ (otherwise BSSID/SSID are redacted).
     *  - "rssiBroadcast": WifiManager.RSSI_CHANGED_ACTION.
     *  - "legacyPoll": deprecated WifiManager.getConnectionInfo() polled at pollMs.
     */
    private inner class ConnectedHandler : EventChannel.StreamHandler {
        private var callback: ConnectivityManager.NetworkCallback? = null
        private var rssiReceiver: BroadcastReceiver? = null
        private var pollRunnable: Runnable? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val args = arguments as? Map<*, *>
            val pollMs = (args?.get("pollMs") as? Number)?.toLong() ?: 0L
            val emit: (Map<String, Any?>) -> Unit = { m -> main.post { events.success(m) } }

            val cb = newWifiCallback(emit)
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            try {
                connectivity.registerNetworkCallback(request, cb)
                callback = cb
            } catch (e: Exception) {
                emit(mapOf("source" to "callback", "error" to e.toString()))
            }

            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    val raw = intent.getIntExtra(WifiManager.EXTRA_NEW_RSSI, -127)
                    val valid = raw > -127 && raw < 0
                    emit(
                        mapOf(
                            "source" to "rssiBroadcast",
                            "rssi" to if (valid) raw else null,
                            "rssiRaw" to raw,
                            "rssiValid" to valid,
                            "elapsedMs" to SystemClock.elapsedRealtime(),
                            "wallUs" to wallUs(),
                        )
                    )
                }
            }
            @Suppress("DEPRECATION")
            registerSystemReceiver(r, IntentFilter(WifiManager.RSSI_CHANGED_ACTION))
            rssiReceiver = r

            if (pollMs > 0) {
                val runnable = object : Runnable {
                    override fun run() {
                        try {
                            events.success(legacyConnectionInfo())
                        } catch (e: Exception) {
                            events.success(mapOf("source" to "legacyPoll", "error" to e.toString()))
                        }
                        main.postDelayed(this, pollMs)
                    }
                }
                pollRunnable = runnable
                main.post(runnable)
            }
        }

        override fun onCancel(arguments: Any?) {
            callback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
            callback = null
            rssiReceiver?.let { runCatching { context.unregisterReceiver(it) } }
            rssiReceiver = null
            pollRunnable?.let { main.removeCallbacks(it) }
            pollRunnable = null
        }
    }

    private inner class WifiCallback : ConnectivityManager.NetworkCallback {
        private val emit: (Map<String, Any?>) -> Unit

        constructor(emit: (Map<String, Any?>) -> Unit) : super() {
            this.emit = emit
        }

        /** API 31+ only: NetworkCallback(int flags) does not exist on older releases. */
        @TargetApi(31)
        constructor(emit: (Map<String, Any?>) -> Unit, flags: Int) : super(flags) {
            this.emit = emit
        }

        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            if (Build.VERSION.SDK_INT < 29) {
                emit(mapOf("source" to "callback", "noTransportInfoApi" to true))
                return
            }
            val info = caps.transportInfo
            if (info is WifiInfo) {
                val m = wifiInfoMap(info, "callback").toMutableMap()
                m["capsSignalStrength"] = caps.signalStrength
                emit(m)
            } else {
                emit(mapOf("source" to "callback", "noWifiInfo" to true))
            }
        }

        override fun onLost(network: Network) {
            emit(
                mapOf(
                    "source" to "callback", "lost" to true,
                    "elapsedMs" to SystemClock.elapsedRealtime(), "wallUs" to wallUs(),
                )
            )
        }
    }

    /** API 31+: without FLAG_INCLUDE_LOCATION_INFO, callback WifiInfo has redacted BSSID/SSID. */
    private fun newWifiCallback(emit: (Map<String, Any?>) -> Unit): WifiCallback =
        if (Build.VERSION.SDK_INT >= 31) {
            WifiCallback(emit, ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO)
        } else {
            WifiCallback(emit)
        }
}
