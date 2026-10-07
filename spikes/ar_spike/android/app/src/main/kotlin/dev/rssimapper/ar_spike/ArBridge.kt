package dev.rssimapper.ar_spike

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.time.Instant
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Phase 0 AR spike bridge: ARCore availability/install, session lifecycle and a
 * per-frame EventChannel carrying pose, tracking state and view/projection matrices.
 */
class ArBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    var session: Session? = null
        private set
    private var view: ArGlView? = null
    private var activityResumed = true

    /** Work that must run on the GL thread with the current frame (ARCore is not thread-safe). */
    val glCommands = ConcurrentLinkedQueue<(Session, Frame) -> Unit>()

    init {
        MethodChannel(messenger, "spike/ar").setMethodCallHandler(this)
        EventChannel(messenger, "spike/ar/frames").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> {
                val a = ArCoreApk.getInstance().checkAvailability(activity)
                result.success(
                    mapOf("name" to a.name, "transient" to a.isTransient, "supported" to a.isSupported)
                )
            }
            "requestInstall" -> {
                val userRequested = call.argument<Boolean>("userRequested") ?: true
                try {
                    result.success(ArCoreApk.getInstance().requestInstall(activity, userRequested).name)
                } catch (e: UnavailableDeviceNotCompatibleException) {
                    result.success("DEVICE_NOT_COMPATIBLE")
                } catch (e: UnavailableUserDeclinedInstallationException) {
                    result.success("USER_DECLINED")
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.toString(), null)
                }
            }
            "dropAnchor" -> {
                // Anchor at the current camera position (translation only).
                glCommands.add { s, frame ->
                    val p = frame.camera.pose
                    anchor?.detach()
                    anchor = s.createAnchor(
                        com.google.ar.core.Pose.makeTranslation(p.tx(), p.ty(), p.tz())
                    )
                }
                result.success(null)
            }
            "clearAnchor" -> {
                glCommands.add { _, _ -> anchor?.detach(); anchor = null }
                result.success(null)
            }
            "saveText" -> {
                try {
                    val dir = activity.getExternalFilesDir(null) ?: activity.filesDir
                    val file = File(dir, call.argument<String>("name")!!)
                    file.writeText(call.argument<String>("content")!!)
                    result.success(file.absolutePath)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.toString(), null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Accessed only from the GL thread. */
    var anchor: com.google.ar.core.Anchor? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** Called from the GL thread; delivers on the platform (main) thread. */
    fun emit(payload: MutableMap<String, Any?>) {
        main.post {
            payload["sendWallUs"] = wallUs()
            sink?.success(payload)
        }
    }

    fun emitError(message: String) = emit(mutableMapOf("error" to message))

    fun attachView(v: ArGlView): Session? {
        view = v
        val s = try {
            Session(activity).also { s ->
                val config = Config(s).apply {
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode = Config.FocusMode.AUTO
                    lightEstimationMode = Config.LightEstimationMode.DISABLED
                    depthMode = Config.DepthMode.DISABLED
                    cloudAnchorMode = Config.CloudAnchorMode.DISABLED
                }
                s.configure(config)
            }
        } catch (e: Exception) {
            emitError("Session creation failed: $e")
            null
        }
        session = s
        if (activityResumed) resumeSession()
        return s
    }

    fun detachView(v: ArGlView) {
        if (view !== v) return
        view = null
        session?.pause()
        session?.close()
        session = null
        anchor = null
        glCommands.clear()
    }

    fun onActivityResume() {
        activityResumed = true
        resumeSession()
        view?.onResume()
    }

    fun onActivityPause() {
        activityResumed = false
        view?.onPause()
        session?.pause()
    }

    private fun resumeSession() {
        try {
            session?.resume()
        } catch (e: CameraNotAvailableException) {
            emitError("Camera not available: $e")
        } catch (e: SecurityException) {
            emitError("Camera permission missing: $e")
        }
    }

    companion object {
        fun wallUs(): Long {
            val now = Instant.now()
            return now.epochSecond * 1_000_000L + now.nano / 1000
        }
    }
}
