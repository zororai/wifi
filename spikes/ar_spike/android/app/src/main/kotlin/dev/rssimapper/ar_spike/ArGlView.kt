package dev.rssimapper.ar_spike

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.SystemClock
import android.view.Surface
import android.view.View
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class ArViewFactory(private val bridge: ArBridge) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ArGlView(context, bridge)
}

/**
 * Option A of Phase 0: ARCore camera feed rendered natively in a GLSurfaceView PlatformView.
 * Each rendered frame's pose/matrices are streamed to Dart, which paints markers on top.
 */
class ArGlView(context: Context, private val bridge: ArBridge) : PlatformView, GLSurfaceView.Renderer {

    private val glView = GLSurfaceView(context)
    private val background = BackgroundRenderer()
    private var viewW = 0
    private var viewH = 0

    init {
        glView.preserveEGLContextOnPause = true
        glView.setEGLContextClientVersion(2)
        glView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glView.setRenderer(this)
        glView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        bridge.attachView(this)
    }

    override fun getView(): View = glView

    override fun dispose() {
        glView.onPause()
        bridge.detachView(this)
    }

    fun onResume() = glView.onResume()
    fun onPause() = glView.onPause()

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        background.createOnGlThread()
        bridge.session?.setCameraTextureName(background.textureId)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        viewW = width
        viewH = height
        // Activity is locked to portrait in the manifest, so display rotation is ROTATION_0.
        bridge.session?.setDisplayGeometry(Surface.ROTATION_0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = bridge.session ?: return
        val t0 = SystemClock.elapsedRealtimeNanos()
        val frame = try {
            session.setCameraTextureName(background.textureId)
            session.update()
        } catch (e: CameraNotAvailableException) {
            bridge.emitError("Camera not available: $e")
            return
        } catch (e: Exception) {
            bridge.emitError("update() failed: $e")
            return
        }
        background.draw(frame)

        while (true) {
            val cmd = bridge.glCommands.poll() ?: break
            try {
                cmd(session, frame)
            } catch (e: Exception) {
                bridge.emitError("GL command failed: $e")
            }
        }

        val camera = frame.camera
        val view = FloatArray(16)
        val proj = FloatArray(16)
        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(proj, 0, 0.05f, 100f)
        val pose = camera.displayOrientedPose

        // Floor estimate: lowest tracked upward-facing plane that is below the camera.
        var floorY: Float? = null
        var planeCount = 0
        for (plane in session.getAllTrackables(Plane::class.java)) {
            if (plane.trackingState != TrackingState.TRACKING || plane.subsumedBy != null) continue
            if (plane.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue
            planeCount++
            val y = plane.centerPose.ty()
            if (y < pose.ty() && (floorY == null || y < floorY)) floorY = y
        }

        val anchor = bridge.anchor
        val anchorPos = anchor?.pose?.let { doubleArrayOf(it.tx().toDouble(), it.ty().toDouble(), it.tz().toDouble()) }

        bridge.emit(
            mutableMapOf(
                "frameTsNs" to frame.timestamp,
                "renderWallUs" to ArBridge.wallUs(),
                "nativeFrameMs" to (SystemClock.elapsedRealtimeNanos() - t0) / 1e6,
                "tracking" to camera.trackingState.name,
                "failure" to camera.trackingFailureReason.name,
                "pose" to doubleArrayOf(
                    pose.tx().toDouble(), pose.ty().toDouble(), pose.tz().toDouble(),
                    pose.qx().toDouble(), pose.qy().toDouble(), pose.qz().toDouble(), pose.qw().toDouble()
                ),
                "view" to view,
                "proj" to proj,
                "floorY" to floorY?.toDouble(),
                "planeCount" to planeCount,
                "anchor" to anchorPos,
                "anchorTracking" to anchor?.trackingState?.name,
                "viewW" to viewW,
                "viewH" to viewH,
            )
        )
    }
}
