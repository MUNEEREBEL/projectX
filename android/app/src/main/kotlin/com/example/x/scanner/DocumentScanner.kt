package com.example.x.scanner

import android.content.ContentResolver
import android.provider.MediaStore

class DocumentScanner(private val contentResolver: ContentResolver) {

    fun streamNonMediaFiles(onFileDiscovered: (DiscoveryDto) -> Unit) {
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DATA,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.MIME_TYPE
        )

        // Filter out media types (already collected by Images/Video/Audio collections)
        val selection = "${MediaStore.Files.FileColumns.MIME_TYPE} NOT LIKE 'image/%' AND " +
                "${MediaStore.Files.FileColumns.MIME_TYPE} NOT LIKE 'video/%' AND " +
                "${MediaStore.Files.FileColumns.MIME_TYPE} NOT LIKE 'audio/%'"

        val filesUri = MediaStore.Files.getContentUri("external")

        try {
            contentResolver.query(filesUri, projection, selection, null, null)?.use { cursor ->
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
                                collection = 4, // 4 = Files / Documents
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

