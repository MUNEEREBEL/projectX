package com.example.x.scanner

object MimeResolver {
    private val mimeMap = mapOf(
        "application/pdf" to FileType.PDF,
        "application/msword" to FileType.DOC,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" to FileType.DOCX,
        "text/plain" to FileType.TXT,
        "text/csv" to FileType.CSV,
        "application/csv" to FileType.CSV,
        "application/json" to FileType.JSON,
        "text/json" to FileType.JSON,
        "application/xml" to FileType.XML,
        "text/xml" to FileType.XML,
        "application/zip" to FileType.ARCHIVE,
        "application/x-rar-compressed" to FileType.ARCHIVE,
        "application/x-7z-compressed" to FileType.ARCHIVE
    )

    fun resolve(mimeType: String?, path: String): FileType {
        val mime = mimeType?.lowercase() ?: ""
        if (mimeMap.containsKey(mime)) {
            return mimeMap[mime]!!
        }

        if (mime.startsWith("image/")) return FileType.IMAGE
        if (mime.startsWith("video/")) return FileType.VIDEO
        if (mime.startsWith("audio/")) return FileType.AUDIO

        val ext = path.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "pdf" -> FileType.PDF
            "doc" -> FileType.DOC
            "docx" -> FileType.DOCX
            "txt" -> FileType.TXT
            "csv" -> FileType.CSV
            "json" -> FileType.JSON
            "xml" -> FileType.XML
            "jpg", "jpeg", "png", "webp", "heic" -> FileType.IMAGE
            "mp4", "mkv", "avi", "mov" -> FileType.VIDEO
            "mp3", "wav", "aac", "m4a", "flac" -> FileType.AUDIO
            "zip", "rar", "7z" -> FileType.ARCHIVE
            else -> FileType.UNKNOWN
        }
    }
}
