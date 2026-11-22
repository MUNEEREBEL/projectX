package com.example.x.scanner

import android.content.ContentResolver
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DiscoveryEngine(private val contentResolver: ContentResolver) {

    suspend fun discoverAll(): List<Map<String, Any>> = withContext(Dispatchers.IO) {
        val resultList = mutableListOf<Map<String, Any>>()
        discoverInBatches(batchSize = 500) { batch, _ ->
            resultList.addAll(batch)
        }
        return@withContext resultList
    }

    suspend fun discoverInBatches(
        batchSize: Int = 500,
        onBatchEmitted: (List<Map<String, Any>>, Boolean) -> Unit
    ) = withContext(Dispatchers.IO) {
        val mediaScanner = MediaStoreScanner(contentResolver)
        val docScanner = DocumentScanner(contentResolver)
        val deduplicatedKeys = hashSetOf<String>()
        val currentBatch = mutableListOf<Map<String, Any>>()

        fun emitBatchIfFull(force: Boolean = false) {
            if (currentBatch.isNotEmpty() && (currentBatch.size >= batchSize || force)) {
                onBatchEmitted(ArrayList(currentBatch), false)
                currentBatch.clear()
            }
        }

        // 1. Query Document Images (Collection 1) - Streamed
        mediaScanner.streamCollection(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, 1) { item ->
            val key = "1_${item.mediaStoreId}"
            if (deduplicatedKeys.add(key)) {
                currentBatch.add(item.toMap())
                emitBatchIfFull()
            }
        }

        // 2. Query Non-Media Documents (Collection 4) - Streamed
        docScanner.streamNonMediaFiles { item ->
            val key = item.path // Canonical path deduplication for documents
            if (deduplicatedKeys.add(key)) {
                currentBatch.add(item.toMap())
                emitBatchIfFull()
            }
        }

        // Final Batch Emission
        emitBatchIfFull(force = true)
        onBatchEmitted(emptyList(), true) // Stream completed
    }
}

