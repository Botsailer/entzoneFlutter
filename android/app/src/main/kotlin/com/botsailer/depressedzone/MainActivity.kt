package com.botsailer.depressedzone

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Rational
import android.view.KeyEvent
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.URL
import kotlin.concurrent.thread

/**
 * The platform half of the app.
 *
 * Flutter cannot do four things this product needs, so they live here:
 *   - picture-in-picture, including the automatic kind on Android 12+;
 *   - a media session, so the lock screen, the notification shade, a headset,
 *     a TV remote and the PiP window's own buttons drive playback;
 *   - media and gamepad keys forwarded to the player;
 *   - the download foreground service's lifecycle.
 *
 * Nothing here decides policy. It reports and performs; Dart decides.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "depressedzone/native"
        private const val EVENTS = "depressedzone/events"
        private const val NOTIFICATION_REQUEST = 7301
    }

    private var events: EventChannel.EventSink? = null
    private var session: MediaSessionCompat? = null
    private var playerActive = false
    private var autoPipEnabled = false
    private var aspect = Rational(16, 9)
    private var permissionResult: MethodChannel.Result? = null
    private var lastArtworkUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        aspect = rationalFrom(call.argument("width"), call.argument("height"))
                        result.success(enterPip())
                    }

                    "setAutoPip" -> {
                        autoPipEnabled = call.argument<Boolean>("enabled") == true
                        aspect = rationalFrom(call.argument("width"), call.argument("height"))
                        applyAutoPip()
                        result.success(null)
                    }

                    "setNowPlaying" -> {
                        updateSession(
                            title = call.argument<String>("title").orEmpty(),
                            subtitle = call.argument<String>("subtitle").orEmpty(),
                            artwork = call.argument("artwork"),
                            playing = call.argument<Boolean>("playing") == true,
                            position = (call.argument<Int>("position") ?: 0).toLong(),
                            duration = (call.argument<Int>("duration") ?: 0).toLong(),
                            hasNext = call.argument<Boolean>("hasNext") == true,
                        )
                        result.success(null)
                    }

                    "clearNowPlaying" -> {
                        releaseSession()
                        result.success(null)
                    }

                    "setPlayerActive" -> {
                        playerActive = call.argument<Boolean>("active") == true
                        if (playerActive) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            ensureSession()
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            releaseSession()
                        }
                        applyAutoPip()
                        result.success(null)
                    }

                    "setImmersive" -> {
                        applyImmersive(call.argument<Boolean>("on") == true)
                        result.success(null)
                    }

                    "startDownloadService" -> {
                        DownloadService.start(
                            this,
                            call.argument<String>("title").orEmpty(),
                            call.argument<String>("subtitle").orEmpty(),
                        )
                        result.success(null)
                    }

                    "updateDownloadProgress" -> {
                        DownloadService.progress(
                            this,
                            call.argument<String>("title").orEmpty(),
                            call.argument<Int>("percent") ?: 0,
                        )
                        result.success(null)
                    }

                    "notifyDownloadComplete" -> {
                        DownloadService.complete(
                            this,
                            call.argument<String>("title").orEmpty(),
                            call.argument<String>("subtitle").orEmpty(),
                        )
                        result.success(null)
                    }

                    "stopDownloadService" -> {
                        DownloadService.stop(this)
                        result.success(null)
                    }

                    "ensureNotificationPermission" -> ensureNotificationPermission(result)

                    else -> result.notImplemented()
                }
            }
    }

    /** Android rejects aspect ratios outside roughly 1:2.39 .. 2.39:1. */
    private fun rationalFrom(w: Int?, h: Int?): Rational {
        val width = (w ?: 16).coerceIn(1, 2000)
        val height = (h ?: 9).coerceIn(1, 2000)
        val ratio = width.toFloat() / height.toFloat()
        return if (ratio < 0.42f || ratio > 2.39f) Rational(16, 9) else Rational(width, height)
    }

    // ───────────────────────── picture in picture ─────────────────────────

    private fun supportsPip(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    @RequiresApi(Build.VERSION_CODES.O)
    private fun pipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPipEnabled && playerActive)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (!supportsPip()) return false
        return try {
            enterPictureInPictureMode(pipParams())
        } catch (_: Throwable) {
            false
        }
    }

    private fun applyAutoPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !supportsPip()) return
        try {
            setPictureInPictureParams(pipParams())
        } catch (_: Throwable) {
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Below Android 12 there is no automatic PiP, so entering on the way
        // out is the only way to keep the picture.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && autoPipEnabled && playerActive) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        events?.success(mapOf("type" to "pip", "active" to inPip))
    }

    // ───────────────────────── immersive ─────────────────────────

    private fun applyImmersive(on: Boolean) {
        WindowCompat.setDecorFitsSystemWindows(window, !on)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        if (on) {
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // ───────────────────────── media session ─────────────────────────

    private fun ensureSession(): MediaSessionCompat {
        session?.let { return it }
        val s = MediaSessionCompat(this, "depressedzone").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onStop() = send("stop")
                override fun onSkipToNext() = send("next")
                override fun onSkipToPrevious() = send("previous")
                override fun onFastForward() = send("forward")
                override fun onRewind() = send("rewind")
            })
            isActive = true
        }
        session = s
        return s
    }

    private fun releaseSession() {
        session?.run {
            isActive = false
            release()
        }
        session = null
        lastArtworkUrl = null
    }

    private fun updateSession(
        title: String,
        subtitle: String,
        artwork: String?,
        playing: Boolean,
        position: Long,
        duration: Long,
        hasNext: Boolean,
    ) {
        val s = ensureSession()

        var actions = PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_STOP or
            PlaybackStateCompat.ACTION_FAST_FORWARD or
            PlaybackStateCompat.ACTION_REWIND
        if (hasNext) actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT

        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    position,
                    if (playing) 1f else 0f,
                )
                .build(),
        )

        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, subtitle)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)

        s.setMetadata(metadata.build())

        // Artwork is fetched off the main thread and applied when it lands; a
        // slow image must never hold up the transport controls.
        if (!artwork.isNullOrEmpty() && artwork != lastArtworkUrl) {
            lastArtworkUrl = artwork
            thread(isDaemon = true) {
                val bmp = loadBitmap(artwork)
                if (bmp != null) {
                    runOnUiThread {
                        session?.setMetadata(
                            metadata
                                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bmp)
                                .build(),
                        )
                    }
                }
            }
        }
    }

    private fun loadBitmap(url: String): Bitmap? = try {
        URL(url).openStream().use { BitmapFactory.decodeStream(it) }
    } catch (_: Throwable) {
        null
    }

    private fun send(action: String) {
        events?.success(mapOf("type" to "remote", "action" to action))
    }

    // ───────────────────────── keys ─────────────────────────

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (playerActive && event.action == KeyEvent.ACTION_DOWN) {
            val action = when (event.keyCode) {
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                KeyEvent.KEYCODE_HEADSETHOOK,
                KeyEvent.KEYCODE_BUTTON_X,
                -> "toggle"
                KeyEvent.KEYCODE_MEDIA_PLAY -> "play"
                KeyEvent.KEYCODE_MEDIA_PAUSE -> "pause"
                KeyEvent.KEYCODE_MEDIA_STOP -> "stop"
                KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "previous"
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.KEYCODE_BUTTON_R1 -> "forward"
                KeyEvent.KEYCODE_MEDIA_REWIND, KeyEvent.KEYCODE_BUTTON_L1 -> "rewind"
                else -> null
            }
            if (action != null) {
                send(action)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    // ───────────────────────── notifications ─────────────────────────

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) {
            val ok = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(ok)
            permissionResult = null
        }
    }

    override fun onDestroy() {
        releaseSession()
        super.onDestroy()
    }
}
