package com.example.x.scanner

object DirectoryPolicy {
    var scanEverything: Boolean = false

    private val excludedNames = hashSetOf(
        ".thumbnail",
        ".thumbnails",
        ".cache",
        ".nomedia",
        "cache",
        "temp",
        "tmp",
        "screenshots",
        "screenshot",
        "memes",
        "meme",
        "wallpapers",
        "wallpaper",
        "stickers",
        "camera",
        "instagram",
        "facebook",
        "snapchat",
        "telegram",
        "reddit",
        "whatsapp animated gifs",
        "whatsapp video",
        "whatsapp voice notes",
        "whatsapp audio",
        "whatsapp stickers"
    )

    private val excludedPaths = arrayOf(
        "/Android/data/",
        "/Android/obb/",
        "/Android/media/com.google.android.gms/",
        "/DCIM/",
        "/Pictures/Screenshots/",
        "/Pictures/Camera/",
        "/Pictures/Instagram/",
        "/Pictures/Facebook/",
        "/Pictures/Telegram/",
        "/Pictures/Snapchat/",
        "/Pictures/Twitter/",
        "/WhatsApp/Media/WhatsApp Animated Gifs/",
        "/WhatsApp/Media/WhatsApp Stickers/",
        "/WhatsApp/Media/WhatsApp Video/",
        "/WhatsApp/Media/WhatsApp Voice Notes/",
        "/WhatsApp/Media/WhatsApp Images/"
    )

    fun isAllowed(path: String): Boolean {
        if (scanEverything) return true
        if (path.isEmpty()) return false

        for (excluded in excludedPaths) {
            if (path.contains(excluded, ignoreCase = true)) {
                return false
            }
        }

        // Fast string segment check without java.io.File object allocation
        var start = 0
        val len = path.length
        while (start < len) {
            var end = path.indexOf('/', start)
            if (end == -1) {
                end = path.indexOf('\\', start)
            }
            val segmentEnd = if (end == -1) len else end
            if (segmentEnd > start) {
                val segment = path.substring(start, segmentEnd).lowercase()
                if (segment.startsWith(".") || excludedNames.contains(segment)) {
                    return false
                }
            }
            if (end == -1) break
            start = end + 1
        }

        return true
    }
}

