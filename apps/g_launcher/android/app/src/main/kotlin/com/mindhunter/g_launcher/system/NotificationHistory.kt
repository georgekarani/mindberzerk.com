package com.mindhunter.g_launcher.system

import android.app.Notification
import android.content.Context
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Notification history, on the phone only. PHASE 9.
 *
 * ─── OPT-IN, AND OFF MEANS GONE ─────────────────────────────────────────────
 *
 * Nothing is recorded until the person turns the switch on, and turning it off
 * deletes the file in the same call. The badge service already listens to
 * every post for counts; this only keeps a copy when [enabled] says so.
 *
 * ─── WHAT IS KEPT ───────────────────────────────────────────────────────────
 *
 * Package, title, text and time, for the most recent [MAX_ENTRIES] posts that
 * are at most [MAX_AGE_MS] old. No images, no actions, no extras, and never a
 * copy anywhere but this app's private files dir, which Android excludes from
 * other apps and which `backup_rules` keeps out of cloud backup.
 *
 * ─── A FILE, NOT A DATABASE ─────────────────────────────────────────────────
 *
 * Two hundred small records rewritten on a background thread are cheaper than
 * a schema, and a JSON array is trivial to wipe whole, which is the one
 * operation that must never half-succeed.
 */
object NotificationHistory {

    private const val PREFS = "g_launcher_notification_history"
    private const val KEY_ON = "on"
    private const val FILE = "notification_history.json"
    private const val MAX_ENTRIES = 200
    private const val MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000

    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ON, false)

    /** Turn recording on or off. Off deletes everything kept so far. */
    @Synchronized
    fun setEnabled(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ON, on).apply()
        if (!on) file(context).delete()
    }

    @Synchronized
    fun clear(context: Context) {
        file(context).delete()
    }

    /**
     * Keep [sbn] when recording is on and it says something. An update to a
     * notification already kept (same key, same text) replaces nothing and
     * adds nothing, so a progress bar or a chat that re-posts does not fill
     * the list with copies.
     */
    @Synchronized
    fun record(context: Context, sbn: StatusBarNotification) {
        if (!enabled(context)) return
        if (sbn.packageName == context.packageName) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = n.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = (
            extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras?.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        val now = System.currentTimeMillis()
        val kept = read(context).filter { now - it.optLong("at") <= MAX_AGE_MS }
        val last = kept.lastOrNull { it.optString("key") == sbn.key }
        if (last != null && last.optString("title") == title && last.optString("text") == text) return

        val entry = JSONObject()
            .put("key", sbn.key)
            .put("package", sbn.packageName)
            .put("title", title)
            .put("text", text)
            .put("at", sbn.postTime.takeIf { it > 0 } ?: now)
        write(context, (kept + entry).takeLast(MAX_ENTRIES))
    }

    /** Newest first, at most [limit]. */
    @Synchronized
    fun list(context: Context, limit: Int): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        return read(context)
            .filter { now - it.optLong("at") <= MAX_AGE_MS }
            .asReversed()
            .take(limit.coerceIn(1, MAX_ENTRIES))
            .map {
                mapOf(
                    "package" to it.optString("package"),
                    "title" to it.optString("title"),
                    "text" to it.optString("text"),
                    "at" to it.optLong("at"),
                )
            }
    }

    private fun file(context: Context) = File(context.filesDir, FILE)

    private fun read(context: Context): List<JSONObject> {
        val f = file(context)
        if (!f.isFile) return emptyList()
        return runCatching {
            val array = JSONArray(f.readText())
            List(array.length()) { array.getJSONObject(it) }
        }.getOrDefault(emptyList())
    }

    /** Temp file and rename, so a crash mid-write cannot leave half a list. */
    private fun write(context: Context, entries: List<JSONObject>) {
        val f = file(context)
        val tmp = File(f.parentFile, "$FILE.tmp")
        tmp.writeText(JSONArray(entries).toString())
        tmp.renameTo(f)
    }
}
