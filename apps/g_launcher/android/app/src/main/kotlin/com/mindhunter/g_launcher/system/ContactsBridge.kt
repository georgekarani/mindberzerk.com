package com.mindhunter.g_launcher.system

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.provider.ContactsContract
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Contacts in search. PHASE 9.
 *
 * ─── OFF UNTIL THE PERSON TURNS IT ON ───────────────────────────────────────
 *
 * Dart only calls [search] while the person's "Contacts in search" switch is
 * on, and turning that switch on is what asks for READ_CONTACTS. Nothing here
 * runs at start-up, nothing is cached, and nothing leaves the phone: a query
 * reads names and a primary number from the system provider and hands them
 * straight back to the search line that asked.
 *
 * ─── A PLAIN METHODCHANNEL, NOT PIGEON ──────────────────────────────────────
 *
 * The same reason the badge bridge gives: a new Pigeon class takes the next
 * codec id in a schema shipped APKs already agree on. Results cross as a list
 * of maps, which needs no schema at all.
 *
 * ─── WHY THE ACTIVITY REGISTERS IT ─────────────────────────────────────────
 *
 * `requestPermissions` needs an Activity, so this is set up from
 * LauncherActivity like the wallpaper channel, with the Activity resolved per
 * call through a lambda. The answer is not awaited: the dialog resumes the
 * activity when it closes and Dart reads [granted] again then, the reasoning
 * `GalleryReader` gives.
 */
object ContactsBridge {

    private const val TAG = "GLauncherContacts"
    private const val CHANNEL = "g_launcher/contacts"

    /** Hard ceiling on one query, whatever Dart asks for. */
    private const val MAX_RESULTS = 8

    private val workerThread by lazy {
        HandlerThread("g_launcher-contacts", Process.THREAD_PRIORITY_BACKGROUND).apply { start() }
    }
    private val worker by lazy { Handler(workerThread.looper) }
    private val main = Handler(Looper.getMainLooper())

    fun setUp(context: Context, messenger: BinaryMessenger, activity: () -> Activity?) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "granted" -> result.success(granted(app))

                "request" -> {
                    val host = activity()
                    if (host == null || granted(app)) {
                        result.success(granted(app))
                    } else {
                        try {
                            host.requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), 0)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.w(TAG, "could not open the permission dialog", e)
                            result.success(false)
                        }
                    }
                }

                "search" -> {
                    val query = (call.argument<String>("query") ?: "").trim()
                    val limit = (call.argument<Int>("limit") ?: MAX_RESULTS).coerceIn(1, MAX_RESULTS)
                    if (query.isEmpty() || !granted(app)) {
                        result.success(emptyList<Map<String, Any?>>())
                    } else {
                        worker.post {
                            val hits = runCatching { search(app, query, limit) }
                                .onFailure { Log.w(TAG, "search failed", it) }
                                .getOrDefault(emptyList())
                            main.post { result.success(hits) }
                        }
                    }
                }

                "open" -> {
                    val uri = call.argument<String>("uri")
                    result.success(uri != null && open(app, uri))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun granted(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Contacts whose display name matches [query], best first as the provider
     * ranks them, each with its primary number when it has one.
     *
     * The provider's FILTER uri, not a LIKE over the whole table: it matches
     * word starts the way the Contacts app does ("ann" finds "Mary Ann"), and it
     * is indexed, so a keystroke costs a lookup rather than a scan.
     */
    private fun search(context: Context, query: String, limit: Int): List<Map<String, Any?>> {
        val uri = ContactsContract.Contacts.CONTENT_FILTER_URI.buildUpon()
            .appendPath(query)
            .build()
        val projection = arrayOf(
            ContactsContract.Contacts._ID,
            ContactsContract.Contacts.LOOKUP_KEY,
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
            ContactsContract.Contacts.HAS_PHONE_NUMBER,
        )
        val out = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(uri, projection, null, null, null)?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                val id = c.getLong(0)
                val lookup = c.getString(1) ?: continue
                val name = c.getString(2)?.takeIf { it.isNotBlank() } ?: continue
                val phone = if (c.getInt(3) > 0) primaryNumber(context, id) else null
                out += mapOf(
                    "name" to name,
                    "phone" to phone,
                    "uri" to ContactsContract.Contacts.getLookupUri(id, lookup).toString(),
                )
            }
        }
        return out
    }

    private fun primaryNumber(context: Context, contactId: Long): String? {
        val projection = arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER)
        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection,
            "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
            arrayOf(contactId.toString()),
            "${ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY} DESC",
        )?.use { c ->
            if (c.moveToFirst()) return c.getString(0)
        }
        return null
    }

    /** Open the contact card in whatever app handles contacts. */
    private fun open(context: Context, uri: String): Boolean = try {
        val parsed = android.net.Uri.parse(uri)
        // A lookup uri survives the contact being merged or re-synced, which
        // an _ID alone does not, so it is what Dart holds on to.
        val target = ContactsContract.Contacts.lookupContact(context.contentResolver, parsed)
            ?: parsed
        context.startActivity(
            Intent(Intent.ACTION_VIEW, target).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        Log.w(TAG, "could not open contact", e)
        false
    }
}
