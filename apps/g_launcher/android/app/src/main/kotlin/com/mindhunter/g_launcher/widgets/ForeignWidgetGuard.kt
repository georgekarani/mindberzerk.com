package com.mindhunter.g_launcher.widgets

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Keeps another app's widget code from taking the launcher down with it.
 *
 * ─── WHY A HOSTED WIDGET CAN CRASH THIS PROCESS ─────────────────────────────
 *
 * RemoteViews normally inflate framework views only, but OEM system widgets
 * (Honor's calendar, some MIUI and One UI clocks) ship custom view classes
 * that the host loads from the provider's APK and runs on OUR main thread,
 * with OUR permissions. Honor's `CalendarSwitchView` queries the calendar
 * provider from a Handler; this launcher has no READ_CALENDAR, so it throws
 * SecurityException and the process dies: the
 * `CalendarSwitchView$c$b.handleMessage` crash. Nothing in this app is on
 * that stack, so no try/catch of ours can reach it.
 *
 * ─── WHAT THIS DOES ─────────────────────────────────────────────────────────
 *
 * Runs the main Looper inside a catch. A throwable is swallowed ONLY when the
 * first non-platform frame on its stack belongs to a class this app's
 * ClassLoader cannot load, which is the exact signature of code that came
 * from another APK. Anything thrown from our code, Flutter, or a bundled
 * library is rethrown untouched and crashes exactly as before.
 *
 * The widget is left to show whatever it last drew. That is the same outcome
 * the stock launcher gives on these devices, minus the restart.
 */
object ForeignWidgetGuard {

    private const val TAG = "ForeignWidgetGuard"

    /** Packages that are the platform, not this app and not a widget. */
    private val PLATFORM_PREFIXES = arrayOf(
        "android.", "androidx.", "com.android.", "java.", "javax.",
        "kotlin.", "kotlinx.", "dalvik.", "libcore.", "sun.", "jdk.",
    )

    @Volatile
    private var installed = false

    /** Call once, from Application.onCreate. Safe to call again. */
    fun install(appClassLoader: ClassLoader) {
        if (installed) return
        installed = true

        // Posted, so it starts as the first message of the real main loop and
        // every later message is dispatched by the guarded loop below.
        Handler(Looper.getMainLooper()).post {
            while (true) {
                try {
                    Looper.loop()
                    // loop() returns only when the main looper quits, which
                    // happens at process death. Nothing left to guard.
                    return@post
                } catch (t: Throwable) {
                    if (!isForeign(t, appClassLoader)) throw t
                    Log.w(TAG, "Swallowed a hosted widget fault", t)
                }
            }
        }
    }

    /**
     * True when this APK was built with `-renamesourcefileattribute SourceFile`
     * (release, see proguard-crashlytics.pro). Read off this class's own frame,
     * so a debug build, whose frames carry real file names, answers false.
     */
    private val ownSourceRenamed: Boolean by lazy {
        Throwable().stackTrace.firstOrNull()?.fileName == RENAMED_SOURCE
    }

    private const val RENAMED_SOURCE = "SourceFile"

    /**
     * True when the top of [t]'s stack, past platform frames, is code that
     * did not come from this APK.
     *
     * ─── WHY LOADABILITY ALONE WAS NOT ENOUGH ───────────────────────────────
     *
     * Honor's calendar APK is R8-obfuscated too, so its frames arrive as short
     * names like `n.j` (the `n.j` / `Utils.java:34` crash on 6.0.15). This APK
     * almost certainly has its own `n.j`, so the name loaded, the frame was
     * judged ours, and the fault was rethrown. The source file attribute
     * breaks the tie: every class R8 processed for this release is stamped
     * `SourceFile`, so a loadable frame naming a real file (`Utils.java`) can
     * only be another APK's class that happens to share an obfuscated name.
     */
    private fun isForeign(t: Throwable, loader: ClassLoader): Boolean {
        for (frame in t.stackTrace) {
            val name = frame.className
            // Loadability first: an OEM class under a platform-looking package
            // (`com.android.calendar...`) is still foreign when we lack it.
            if (!isLoadable(name, loader)) return true
            if (PLATFORM_PREFIXES.any { name.startsWith(it) }) continue
            return ownSourceRenamed && !isOwnSourceFile(frame.fileName)
        }
        return false
    }

    /** Null is how R8 can also emit a stripped attribute; both mean ours. */
    private fun isOwnSourceFile(fileName: String?): Boolean =
        fileName == null || fileName == RENAMED_SOURCE

    private fun isLoadable(className: String, loader: ClassLoader): Boolean =
        try {
            Class.forName(className, false, loader)
            true
        } catch (_: ClassNotFoundException) {
            false
        } catch (_: LinkageError) {
            // Present but broken to link is still ours to answer for.
            true
        }
}
