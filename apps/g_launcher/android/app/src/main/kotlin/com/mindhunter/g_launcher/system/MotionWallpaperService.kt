package com.mindhunter.g_launcher.system

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaPlayer
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.SurfaceHolder
import java.io.File

/**
 * The user's own video, as a live wallpaper.
 *
 * ─── WHY A SERVICE AND NOT A LONGER setWallpaper ───────────────────────────
 *
 * A still wallpaper is a bitmap handed to `WallpaperManager`, which is what
 * [WallpaperController] does. An animated one shares none of that: Android
 * draws it by binding a service and giving it a surface, so motion means a
 * declared component with its own lifecycle rather than a different argument
 * to an existing call.
 *
 * ─── AND WHY IT CANNOT BE APPLIED SILENTLY ─────────────────────────────────
 *
 * `setWallpaperComponent` is signature-permission, so a third-party launcher
 * cannot switch to its own live wallpaper on the user's behalf. The only route
 * is `ACTION_CHANGE_LIVE_WALLPAPER`, which shows Android's own full-screen
 * preview with a Set wallpaper button. Picking a video therefore leaves this
 * app and comes back, and no amount of work here changes that.
 *
 * ─── ONE VIDEO, BOTH SCREENS ───────────────────────────────────────────────
 *
 * A live wallpaper is ONE component for the whole system, and the engine is
 * not reliably told whether it is being drawn behind the lock screen or the
 * home screen. Per-surface video exists on Samsung as an OEM feature, not
 * through any public API. So the separate-picture-per-screen behaviour this
 * app just gained is for STILLS only, and motion replaces both at once.
 *
 * ─── THE PATH IS FIXED, NOT PASSED ─────────────────────────────────────────
 *
 * Android constructs this service; nothing hands it an argument. Dart copies
 * the chosen video to [currentFile] before opening the chooser, so the engine
 * reads one known location. That also means switching videos is a copy plus a
 * restart rather than a second component.
 */
class MotionWallpaperService : WallpaperService() {

    companion object {
        private const val TAG = "GLauncherMotion"

        /** Where Dart puts the copy this service plays. */
        fun currentFile(context: android.content.Context): File =
            File(File(context.filesDir, "motion").apply { mkdirs() }, "current.mp4")

        /**
         * The lock screen's own video, when the user chose one. Written by Dart
         * straight into filesDir (path_provider's support directory), so no
         * bridge call is needed to set or clear it. Absent means the lock screen
         * plays the home video, which is what it always did.
         */
        fun lockFile(context: android.content.Context): File =
            File(File(context.filesDir, "motion").apply { mkdirs() }, "lock.mp4")
    }

    override fun onCreateEngine(): Engine = MotionEngine()

    private inner class MotionEngine : Engine() {
        private var player: MediaPlayer? = null
        private var holder: SurfaceHolder? = null

        /** The file playing now and its timestamp, so a replaced video reloads. */
        private var playing: File? = null
        private var playingStamp = 0L

        // ─── ONE ENGINE, TWO VIDEOS ─────────────────────────────────────────
        //
        // A third-party app cannot set a different live wallpaper on the lock
        // screen: the flags that would allow it are system APIs. What it can do
        // is draw something different while the phone is locked. So this
        // engine plays lock.mp4 from screen-off until the user unlocks, and
        // current.mp4 after. Switching on screen-off rather than screen-on
        // means the lock video is already playing when the screen lights.
        private val lockState = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                holder?.let { swapIfNeeded(it) }
            }
        }
        private var lockStateRegistered = false

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            if (isPreview) return
            registerReceiver(
                lockState,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_OFF)
                    addAction(Intent.ACTION_USER_PRESENT)
                },
            )
            lockStateRegistered = true
        }

        override fun onDestroy() {
            if (lockStateRegistered) {
                runCatching { unregisterReceiver(lockState) }
                lockStateRegistered = false
            }
            super.onDestroy()
        }

        /** The video this moment calls for: the lock one while locked, if set. */
        private fun wanted(): File {
            val ctx = this@MotionWallpaperService
            val lock = lockFile(ctx)
            val locked = (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
                .isKeyguardLocked
            return if (locked && lock.exists()) lock else currentFile(ctx)
        }

        private fun swapIfNeeded(holder: SurfaceHolder) {
            val next = wanted()
            if (next == playing && next.lastModified() == playingStamp) return
            stop()
            start(holder)
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            this.holder = holder
            start(holder)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            stop()
            this.holder = null
            super.onSurfaceDestroyed(holder)
        }

        /**
         * ─── THE WHOLE BATTERY STORY IS THIS METHOD ────────────────────────
         *
         * A wallpaper is behind everything, so it is invisible most of the time
         * the phone is on: any full-screen app, the lock screen on most
         * devices, the recents view. Decoding video through all of that is how
         * a launcher earns a one-star review about battery, on phones that are
         * mostly not flagships.
         *
         * Paused rather than released, because the home screen is returned to
         * constantly and re-preparing a MediaPlayer on every return would stall
         * the first frame each time.
         */
        override fun onVisibilityChanged(visible: Boolean) {
            // Coming into view is also when a replaced or newly chosen video
            // should take over, and when the lock state may have moved on.
            if (visible) holder?.let { swapIfNeeded(it) }
            val p = player ?: return
            try {
                if (visible) p.start() else p.pause()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "player rejected a visibility change", e)
            }
        }

        private fun start(holder: SurfaceHolder) {
            val file = wanted()
            if (!file.exists()) {
                // Nothing to play. Left as a black surface rather than crashing:
                // the user can reach the picker and choose again, and a wallpaper
                // service that dies takes the home screen with it.
                Log.w(TAG, "no motion wallpaper on disk")
                return
            }

            try {
                player = MediaPlayer().apply {
                    setSurface(holder.surface)
                    setDataSource(file.absolutePath)
                    isLooping = true
                    // Silent, always. A wallpaper that makes noise when the
                    // phone is unlocked is not a feature anybody asked for, and
                    // it would fight whatever the user is actually listening to.
                    setVolume(0f, 0f)
                    setOnPreparedListener { if (isVisible) it.start() }
                    setOnErrorListener { _, what, extra ->
                        Log.w(TAG, "playback failed what=$what extra=$extra")
                        // Handled, so MediaPlayer does not also call the
                        // completion listener on an already-broken player.
                        true
                    }
                    prepareAsync()
                }
                playing = file
                playingStamp = file.lastModified()
            } catch (e: Exception) {
                Log.w(TAG, "could not open the motion wallpaper", e)
                stop()
            }
        }

        private fun stop() {
            try {
                player?.stop()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "player was not running", e)
            }
            player?.release()
            player = null
            playing = null
        }
    }
}
