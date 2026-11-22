package com.example.x.scanner

enum class FileType(val id: Int) {
    UNKNOWN(0),
    IMAGE(1),
    VIDEO(2),
    AUDIO(3),
    PDF(4),
    DOC(5),
    DOCX(6),
    TXT(7),
    CSV(8),
    JSON(9),
    XML(10),
    ARCHIVE(11);

    companion object {
        fun fromId(id: Int): FileType = values().firstOrNull { it.id == id } ?: UNKNOWN
    }
}
