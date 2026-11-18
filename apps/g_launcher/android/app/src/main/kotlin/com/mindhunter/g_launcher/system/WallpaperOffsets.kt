package com.mindhunter.g_launcher.system

import android.app.WallpaperManager
import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * The two things the launcher asks of its own WINDOW: pan the wallpaper, and
 * keep the edge handle's strip away from Android's back gesture. PHASE 8.
 *
 * ─── WHY THIS IS NOT ON THE PIGEON BRIDGE ───────────────────────────────────
 *
 * Both need the Activity's window. `setWallpaperOffsets` takes a window token,
 * and `setSystemGestureExclusionRects` is a method on an attached View.
 * `LauncherHostApiImpl` holds an application Context and nothing else, so this
 * is set up in `LauncherActivity.configureFlutterEngine`, the same reason
 * `StageBridge` lives there.
 *
 * ─── WHAT THE PAN DOES, AND WHERE IT DOES NOTHING ───────────────────────────
 *
 * The window is transparent with `windowShowWallpaper`, so the wallpaper is
 * drawn by WindowManager under Flutter and the only way to move it is to ask
 * the wallpaper service. A live wallpaper receives the offset and honours it.
 * A static one pans only if the stored bitmap is wider than the screen: the
 * launcher sets its own "cover" wallpapers at the surface's width, about twice
 * the screen, but One UI, recent Pixels and most Transsion ROMs crop to the
 * screen, and there the call is a correct no-op. There is no API that says
 * which in advance, so the setting is offered everywhere and costs nothing
 * where it cannot move anything.
 */
object WallpaperOffsets {

    private const val TAG = "GLauncherWindow"
    private const val CHANNEL = "g_launcher/wallpaper_offsets"

    /**
     * Android honours at most this much exclusion per edge, in dp. Anything
     * over is silently trimmed by the system, so it is clamped here instead and
     * the handle is drawn to match what is actually excluded.
     */
    private const val MAX_EXCLUSION_DP = 200f

    private var view: View? = null

    /**
     * [decorView] is a lambda rather than a View because this runs before the
     * window is necessarily laid out, and a token read now would be null. It is
     * resolved when a call arrives, by which point somebody is looking at it.
     *
     * `setMethodCallHandler` REPLACES rather than stacks, so re-registering on
     * an Activity recreate is harmless.
     */
    fun setUp(messenger: BinaryMessenger, decorView: () -> View?) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            view = decorView()
            when (call.method) {
                "setOffset" -> {
                    val x = (call.argument<Double>("x") ?: 0.5).toFloat()
                    result.success(setOffset(x))
                }
                "setExclusion" -> {
                    @Suppress("UNCHECKED_CAST")
                    val rects = call.argument<List<List<Double>>>("rects") ?: emptyList()
                    result.success(setExclusion(rects))
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Push one offset. [x] is 0 for the far left, 1 for the far right.
     *
     * The step is set every time, and it is the part everyone forgets: the
     * default assumes a two-page launcher, so a smooth drag lands on two
     * positions and reads as a jump. A tiny step makes the pan continuous.
     *
     * Returns false rather than throwing on a missing token: the window can be
     * gone between a scroll frame and this call, and a launcher that crashes
     * mid-swipe because the wallpaper could not be nudged is the worse outcome.
     */
    fun setOffset(x: Float): Boolean {
        val v = view ?: return false
        val token = v.windowToken ?: return false
        return try {
            val wm = WallpaperManager.getInstance(v.context)
            wm.setWallpaperOffsetSteps(0.0001f, 1f)
            wm.setWallpaperOffsets(token, x.coerceIn(0f, 1f), 0.5f)
            true
        } catch (e: Exception) {
            // An IllegalArgumentException here means the token is not one the
            // window manager recognises, which happens on a detached view.
            Log.w(TAG, "setWallpaperOffsets failed: ${e.javaClass.simpleName} ${e.message}")
            false
        }
    }

    /**
     * Replace the window's back-gesture exclusion with [rects], each
     * `[left, top, right, bottom]` in LOGICAL pixels, as Flutter measures.
     * An empty list gives every edge back to the system.
     *
     * Android 10 and later only; earlier versions had no edge back gesture, so
     * there is nothing to exclude and this reports success.
     */
    fun setExclusion(rects: List<List<Double>>): Boolean {
        val v = view ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        val density = v.resources.displayMetrics.density
        val cap = (MAX_EXCLUSION_DP * density).roundToInt()
        val out = rects.mapNotNull { r ->
            if (r.size != 4) return@mapNotNull null
            val left = (r[0] * density).roundToInt()
            val top = (r[1] * density).roundToInt()
            val right = (r[2] * density).roundToInt()
            // Clamped from the top, so an oversized request keeps its start.
            val bottom = minOf((r[3] * density).roundToInt(), top + cap)
            if (right > left && bottom > top) Rect(left, top, right, bottom) else null
        }
        return try {
            v.systemGestureExclusionRects = out
            true
        } catch (e: Exception) {
            Log.w(TAG, "setSystemGestureExclusionRects failed: ${e.message}")
            false
        }
    }
}
