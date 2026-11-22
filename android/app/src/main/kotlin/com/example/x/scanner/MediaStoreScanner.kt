package com.example.x.scanner

import android.content.ContentResolver
import android.net.Uri
import android.provider.MediaStore

class MediaStoreScanner(private val contentResolver: ContentResolver) {

    fun streamCollection(
        collectionUri: Uri,
        collectionId: Int,
        onFileDiscovered: (DiscoveryDto) -> Unit
    ) {
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.MIME_TYPE
        )

        try {
            contentResolver.query(collectionUri, projection, null, null, null)?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
                val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATA)
                val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE)
                val dateModifiedIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_MODIFIED)
                val mimeIndex = cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idIndex)
                    val path = cursor.getString(dataIndex) ?: ""
                    val size = cursor.getLong(sizeIndex)
                    val dateModified = cursor.getLong(dateModifiedIndex)
                    val mimeType = cursor.getString(mimeIndex) ?: "application/octet-stream"

                    if (path.isNotEmpty() && size > 0 && DirectoryPolicy.isAllowed(path)) {
                        val fileType = MimeResolver.resolve(mimeType, path)
                        onFileDiscovered(
                            DiscoveryDto(
                                mediaStoreId = id,
                                collection = collectionId,
                                fileType = fileType.id,
                                mime = mimeType,
                                size = size,
                                modified = dateModified,
                                path = path
                            )
                        )
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}

