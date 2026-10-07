package dev.rssimapper.rssi_mapper

import android.annotation.TargetApi
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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

/**
 * Native Wi-Fi bridge. Dart talks to it only through `WifiNativeApi`.
 *
 * Honesty rules applied here:
 * - Unavailable values are sent as null. Android's invalid-RSSI sentinel (-127),
 *   unknown frequency/link speed (-1) and "<unknown ssid>" are never forwarded
 *   as real values.
 * - Every scan broadcast is forwarded, including EXTRA_RESULTS_UPDATED == false
 *   (scan failed or was throttled), so Dart can refuse stale data.
 *
 * Legacy APIs, isolated on purpose:
 * - WifiManager.startScan() is deprecated since API 28 with no replacement; it is
 *   still the only way to request a scan. It returns false when the request is
 *   rejected (e.g. throttled).
 * - WifiManager.getConnectionInfo() is deprecated since API 31. It is used only
 *   when the NetworkCallback does not provide a WifiInfo (API < 31 devices).
 */
class WifiBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val wifi =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())

    private val methodChannel = MethodChannel(messenger, "rssi_mapper/wifi")
    private val scanEventChannel = EventChannel(messenger, "rssi_mapper/wifi/scan_events")
    private val connectedEventChannel = EventChannel(messenger, "rssi_mapper/wifi/connected")

    // Connected-network state, updated by the NetworkCallback (main thread).
    private val wifiNetworks = mutableSetOf<Network>()
    private var callbackInfo: WifiInfo? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var sequence = 0L

    private var scanReceiver: BroadcastReceiver? = null
    private var rssiReceiver: BroadcastReceiver? = null
    private var connectedSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        scanEventChannel.setStreamHandler(ScanEventsHandler())
        connectedEventChannel.setStreamHandler(ConnectedHandler())
        registerNetworkCallback()
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        scanEventChannel.setStreamHandler(null)
        connectedEventChannel.setStreamHandler(null)
        networkCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        networkCallback = null
        scanReceiver?.let { runCatching { context.unregisterReceiver(it) } }
        rssiReceiver?.let { runCatching { context.unregisterReceiver(it) } }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "environment" -> result.success(environment())
                "startScan" -> {
                    @Suppress("DEPRECATION")
                    result.success(wifi.startScan())
                }
                "scanResults" -> result.success(scanResults())
                "connectedInfo" -> result.success(connectedInfo(null))
                "openSettings" -> {
                    val action = when (call.argument<String>("page")) {
                        "wifi" -> Settings.ACTION_WIFI_SETTINGS
                        "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                        else -> return result.error("BAD_ARGS", "Unknown settings page", null)
                    }
                    context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION", e.message, null)
        } catch (e: Exception) {
            result.error("FAILED", e.toString(), null)
        }
    }

    private fun environment(): Map<String, Any?> = mapOf(
        "sdkInt" to Build.VERSION.SDK_INT,
        "wifiEnabled" to wifi.isWifiEnabled,
        "locationEnabled" to isLocationEnabled(),
        "scanThrottleEnabled" to
            if (Build.VERSION.SDK_INT >= 30) wifi.isScanThrottleEnabled else null,
        // Android 12+ lets users grant only approximate location, which is not
        // enough for scan results or the connected BSSID.
        "fineLocationGranted" to (
            context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ),
    )

    private fun isLocationEnabled(): Boolean =
        if (Build.VERSION.SDK_INT >= 28) {
            (context.getSystemService(Context.LOCATION_SERVICE) as LocationManager).isLocationEnabled
        } else {
            @Suppress("DEPRECATION")
            Settings.Secure.getInt(
                context.contentResolver, Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF,
            ) != Settings.Secure.LOCATION_MODE_OFF
        }

    private fun scanResults(): List<Map<String, Any?>> {
        val nowUs = SystemClock.elapsedRealtimeNanos() / 1000
        return wifi.scanResults.map { r -> scanResultMap(r, nowUs) }
    }

    private fun scanResultMap(r: ScanResult, nowUs: Long): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val ssid: String? = r.SSID
        return mapOf(
            "ssid" to ssid?.takeIf { it.isNotEmpty() },
            "bssid" to r.BSSID,
            "rssi" to r.level.takeIf { isPlausibleRssi(it) },
            "frequencyMhz" to r.frequency.takeIf { it > 0 },
            "capabilities" to r.capabilities,
            // ScanResult.timestamp: microseconds since boot when last seen.
            "ageMs" to ((nowUs - r.timestamp) / 1000).takeIf { r.timestamp > 0 && it >= 0 },
        )
    }

    /** Current connected-network observation, or null when not on Wi-Fi. */
    private fun connectedInfo(broadcastRssi: Int?): Map<String, Any?>? {
        val fromCallback = callbackInfo
        val info: WifiInfo
        val source: String
        if (fromCallback != null) {
            info = fromCallback
            source = "networkCallback"
        } else {
            @Suppress("DEPRECATION")
            val legacy = wifi.connectionInfo ?: return null
            // Legacy getter reports networkId -1 when not associated.
            @Suppress("DEPRECATION")
            if (legacy.networkId == -1 && legacy.bssid == null) return null
            info = legacy
            source = "legacyConnectionInfo"
        }
        if (fromCallback == null && wifiNetworks.isEmpty() && Build.VERSION.SDK_INT >= 31) {
            return null
        }
        val rssi = broadcastRssi ?: info.rssi
        sequence++
        return mapOf(
            "ssid" to cleanSsid(info.ssid),
            "bssid" to info.bssid,
            "rssi" to rssi.takeIf { isPlausibleRssi(it) },
            "frequencyMhz" to info.frequency.takeIf { it > 0 },
            "linkSpeedMbps" to info.linkSpeed.takeIf { it > 0 },
            "source" to source,
            "rssiFromBroadcast" to (broadcastRssi != null),
            "elapsedRealtimeMs" to SystemClock.elapsedRealtime(),
            "sequence" to sequence,
        )
    }

    private fun emitConnected(broadcastRssi: Int? = null) {
        val sink = connectedSink ?: return
        val info = try {
            connectedInfo(broadcastRssi)
        } catch (e: SecurityException) {
            sink.error("PERMISSION", e.message, null)
            return
        }
        sink.success(info ?: mapOf("connected" to false))
    }

    private fun registerNetworkCallback() {
        val emitOnMain: (() -> Unit) -> Unit = { block -> main.post(block) }
        val cb = if (Build.VERSION.SDK_INT >= 31) {
            WifiCallback(emitOnMain, ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO)
        } else {
            WifiCallback(emitOnMain)
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        try {
            connectivity.registerNetworkCallback(request, cb)
            networkCallback = cb
        } catch (e: Exception) {
            // Without the callback, connectedInfo() falls back to the legacy getter.
            networkCallback = null
        }
    }

    private inner class WifiCallback : ConnectivityManager.NetworkCallback {
        private val post: (() -> Unit) -> Unit

        constructor(post: (() -> Unit) -> Unit) : super() {
            this.post = post
        }

        /** NetworkCallback(int flags) exists only on API 31+. */
        @TargetApi(31)
        constructor(post: (() -> Unit) -> Unit, flags: Int) : super(flags) {
            this.post = post
        }

        override fun onAvailable(network: Network) = post {
            wifiNetworks.add(network)
        }

        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            val info = if (Build.VERSION.SDK_INT >= 29) caps.transportInfo as? WifiInfo else null
            post {
                wifiNetworks.add(network)
                callbackInfo = info
                emitConnected()
            }
        }

        override fun onLost(network: Network) = post {
            wifiNetworks.remove(network)
            if (wifiNetworks.isEmpty()) callbackInfo = null
            connectedSink?.success(mapOf("connected" to false))
        }
    }

    private fun registerSystemReceiver(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= 33) {
            // System broadcasts are still delivered to non-exported receivers.
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private inner class ScanEventsHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    events.success(
                        mapOf(
                            "updated" to intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false),
                            "elapsedRealtimeMs" to SystemClock.elapsedRealtime(),
                        )
                    )
                }
            }
            registerSystemReceiver(r, IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION))
            scanReceiver = r
        }

        override fun onCancel(arguments: Any?) {
            scanReceiver?.let { runCatching { context.unregisterReceiver(it) } }
            scanReceiver = null
        }
    }

    private inner class ConnectedHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            connectedSink = events
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    val raw = intent.getIntExtra(WifiManager.EXTRA_NEW_RSSI, INVALID_RSSI)
                    emitConnected(raw.takeIf { isPlausibleRssi(it) })
                }
            }
            @Suppress("DEPRECATION")
            registerSystemReceiver(r, IntentFilter(WifiManager.RSSI_CHANGED_ACTION))
            rssiReceiver = r
            emitConnected()
        }

        override fun onCancel(arguments: Any?) {
            connectedSink = null
            rssiReceiver?.let { runCatching { context.unregisterReceiver(it) } }
            rssiReceiver = null
        }
    }

    private companion object {
        const val INVALID_RSSI = -127

        fun isPlausibleRssi(dbm: Int) = dbm > INVALID_RSSI && dbm < 0

        /** WifiInfo.getSSID() quotes UTF-8 names and returns "<unknown ssid>" when hidden. */
        fun cleanSsid(raw: String?): String? {
            if (raw == null || raw == "<unknown ssid>" || raw.isEmpty()) return null
            return if (raw.length >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
                raw.substring(1, raw.length - 1)
            } else {
                raw
            }
        }
    }
}
