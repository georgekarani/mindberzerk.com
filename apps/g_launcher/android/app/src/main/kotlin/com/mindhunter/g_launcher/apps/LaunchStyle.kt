package com.mindhunter.g_launcher.apps

import android.app.Activity
import android.app.ActivityOptions
import android.content.Context
import android.graphics.Rect
import android.os.Bundle
import com.mindhunter.g_launcher.R

/**
 * How an app opens from the current distro. PHASE 6.
 *
 * Set once per theme resolve through `LauncherHostApi.setLaunchStyle`, the way
 * the icon pack is, so the launch call itself keeps its signature and every
 * caller (drawer, dock, search, desklets) gets the distro's style without
 * having to pass it.
 *
 * ─── WHAT EACH STYLE IS ─────────────────────────────────────────────────────
 *
 *  zoom    The system's own open-from-the-icon zoom, which is what a launch
 *          with a source rect and no options already does. The default.
 *  reveal  A circle-ish clip that grows from the icon (clip reveal), the
 *          Material launcher of the Pixel 2 era. Needs a source view, so it
 *          falls back to zoom when the launcher has no window.
 *  fade    A cross-fade, for the calm desktops.
 *  slide   The app rises a little as it fades in, over a launcher that stays
 *          put: the "window maps" feel of a tiling WM.
 *  none    No animation at all, for the terminal and anyone who wants speed.
 *
 * Every builder returns null for zoom so the platform default stays in charge
 * of it; nothing here re-implements the system animation.
 */
object LaunchStyle {
    const val ZOOM = "zoom"
    const val REVEAL = "reveal"
    const val FADE = "fade"
    const val SLIDE = "slide"
    const val NONE = "none"

    private val known = setOf(ZOOM, REVEAL, FADE, SLIDE, NONE)

    @Volatile
    var current: String = ZOOM
        private set

    /** Adopts [style], treating anything unknown as [ZOOM]. */
    fun set(style: String) {
        current = if (style in known) style else ZOOM
    }

    /**
     * The options for one launch from [bounds] (screen pixels), or null to
     * let the system animate as it always has.
     *
     * [activity] is the launcher's window when it has one: clip reveal must
     * name a view to grow from, and a custom animation is best resolved
     * against the activity. [context] is the fallback for the latter.
     */
    fun options(context: Context, activity: Activity?, bounds: Rect?): Bundle? {
        val ctx = activity ?: context
        return when (current) {
            REVEAL -> {
                val source = activity?.window?.decorView
                if (source == null || bounds == null) {
                    null
                } else {
                    ActivityOptions.makeClipRevealAnimation(
                        source,
                        bounds.left,
                        bounds.top,
                        bounds.width(),
                        bounds.height(),
                    ).toBundle()
                }
            }
            FADE -> ActivityOptions.makeCustomAnimation(
                ctx,
                android.R.anim.fade_in,
                android.R.anim.fade_out,
            ).toBundle()
            SLIDE -> ActivityOptions.makeCustomAnimation(
                ctx,
                R.anim.launch_slide_in,
                R.anim.launch_hold,
            ).toBundle()
            // Zero resources mean "no animation" to the window manager.
            NONE -> ActivityOptions.makeCustomAnimation(ctx, 0, 0).toBundle()
            else -> null
        }
    }
}
