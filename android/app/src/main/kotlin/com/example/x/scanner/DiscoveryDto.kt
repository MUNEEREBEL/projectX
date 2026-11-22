package com.example.x.scanner

data class DiscoveryDto(
    val mediaStoreId: Long,
    val collection: Int, // 1=Images, 2=Video, 3=Audio, 4=Files
    val fileType: Int,    // FileType enum ID
    val mime: String,
    val size: Long,
    val modified: Long,
    val path: String
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "mediaStoreId" to mediaStoreId,
            "collection" to collection,
            "fileType" to fileType,
            "mimeType" to mime,
            "size" to size,
            "dateModified" to modified,
            "path" to path
        )
    }
}
