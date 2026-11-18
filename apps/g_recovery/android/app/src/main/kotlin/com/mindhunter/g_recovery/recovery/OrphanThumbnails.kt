package com.mindhunter.g_recovery.recovery

import android.content.ContentResolver
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import java.io.File

/**
 * Decides whether a cached thumbnail is an orphan: a preview whose original is no
 * longer anywhere in the gallery index, trash included.
 *
 * MediaStore's own thumbnails are named after the media row they belong to, as in
 * `1234.jpg`. A numeric name whose row is gone is an orphan. Any other name cannot be
 * matched to an original, so it is not counted: showing no preview beats telling the
 * user a photo is gone while it is still in their gallery.
 */
internal class OrphanThumbnails(context: Context) {
    private val resolver: ContentResolver = context.applicationContext.contentResolver

    /**
     * A predicate for one scan. Builds the set of live media ids once.
     *
     * [trusted] must be true only when this app can see every media row (All files
     * access). Without it the query returns only this app's own rows, every thumbnail
     * would look orphaned, and the count would be exactly the overclaim this avoids.
     */
    fun filter(trusted: Boolean): (File) -> Boolean {
        if (!trusted) return { false }
        val live = liveMediaIds() ?: return { false }
        return { file ->
            val id = file.nameWithoutExtension.toLongOrNull()
            id != null && id !in live
        }
    }

    /** Every image and video row, trashed and pending included. Null if the query fails. */
    private fun liveMediaIds(): Set<Long>? = try {
        val uri = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(MediaStore.Files.FileColumns._ID)
        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN " +
            "(${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, " +
            "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val args = Bundle().apply {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                // A photo in the trash still has its original: its thumbnail is not
                // an orphan, and the full file is already offered from the trash.
                putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
                putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
            }
            resolver.query(uri, projection, args, null)
        } else {
            resolver.query(uri, projection, selection, null, null)
        }
        cursor?.use { c ->
            val column = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val ids = HashSet<Long>(c.count.coerceAtLeast(16))
            while (c.moveToNext()) ids.add(c.getLong(column))
            ids
        }
    } catch (_: Throwable) {
        null
    }
}
