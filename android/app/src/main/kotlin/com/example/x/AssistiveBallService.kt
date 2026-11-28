package com.example.x

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.*
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.abs

data class VaultFieldItem(val name: String, val value: String)
data class VaultDocItem(
    val id: String,
    val title: String,
    val category: String,
    val owner: String,
    val idNumber: String?,
    val expiryDate: String? = null,
    val fields: List<VaultFieldItem>
)

class AssistiveBallService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingBallView: View? = null
    private var floatingPanelView: View? = null
    private val CHANNEL_ID = "privdoc_assistive_channel"
    private val NOTIFICATION_ID = 2001

    private var allVaultDocs: List<VaultDocItem> = emptyList()
    private var density: Float = 1.0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        density = resources.displayMetrics.density
        createNotificationChannel()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (e: Exception) {
            Log.e("AssistiveBallService", "startForeground failed: ${e.message}")
        }
        createFloatingBall()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Project X Assistive Ball",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows active status of the floating assistive ball."
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("OPEN_X", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Project X Vault Active")
            .setContentText("Tap floating ball for instant document fields")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createFloatingBall() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w("AssistiveBallService", "Overlay permission not granted, skipping createFloatingBall")
            return
        }

        try {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            val sizePx = (52 * density).toInt()

            val ballParams = WindowManager.LayoutParams(
                sizePx,
                sizePx,
                layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 20
                y = (200 * density).toInt()
            }

            // Dark obsidian circle with vibrant cyan glow border
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#0F172A"))
                setStroke((2.5f * density).toInt(), Color.parseColor("#00B4D8"))
            }

            val imageView = ImageView(this).apply {
                background = shape
                setImageResource(android.R.drawable.ic_menu_agenda)
                setColorFilter(Color.parseColor("#00F2FE"))
                val pad = (14 * density).toInt()
                setPadding(pad, pad, pad, pad)
            }

            imageView.setOnTouchListener(object : View.OnTouchListener {
                private var initialX = 0
                private var initialY = 0
                private var initialTouchX = 0f
                private var initialTouchY = 0f
                private var touchStartTime = 0L

                override fun onTouch(v: View, event: MotionEvent): Boolean {
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = ballParams.x
                            initialY = ballParams.y
                            initialTouchX = event.rawX
                            initialTouchY = event.rawY
                            touchStartTime = System.currentTimeMillis()
                            return true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            ballParams.x = initialX + (event.rawX - initialTouchX).toInt()
                            ballParams.y = initialY + (event.rawY - initialTouchY).toInt()
                            windowManager?.updateViewLayout(v, ballParams)
                            return true
                        }
                        MotionEvent.ACTION_UP -> {
                            val diffX = abs(event.rawX - initialTouchX)
                            val diffY = abs(event.rawY - initialTouchY)
                            val duration = System.currentTimeMillis() - touchStartTime

                            // Tap detection (<10dp movement and <350ms duration)
                            if (diffX < 10 * density && diffY < 10 * density && duration < 350) {
                                toggleFloatingVaultPanel(ballParams.x, ballParams.y)
                            }
                            return true
                        }
                    }
                    return false
                }
            })

            floatingBallView = imageView
            windowManager?.addView(floatingBallView, ballParams)
        } catch (e: Exception) {
            Log.e("AssistiveBallService", "Failed to add floating ball: ${e.message}")
        }
    }

    private fun toggleFloatingVaultPanel(anchorX: Int, anchorY: Int) {
        if (floatingPanelView != null) {
            closeFloatingVaultPanel()
        } else {
            openFloatingVaultPanel(anchorX, anchorY)
        }
    }

    private fun closeFloatingVaultPanel() {
        floatingPanelView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {}
            floatingPanelView = null
        }
    }

    private fun openFloatingVaultPanel(anchorX: Int, anchorY: Int) {
        if (floatingPanelView != null) closeFloatingVaultPanel()
        allVaultDocs = loadVaultDocuments()

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val panelWidth = (330 * density).toInt()
        val panelHeight = (450 * density).toInt()

        val displayMetrics = resources.displayMetrics
        val screenW = displayMetrics.widthPixels
        val screenH = displayMetrics.heightPixels

        val posX = anchorX.coerceIn(16, (screenW - panelWidth - 16).coerceAtLeast(16))
        val posY = anchorY.coerceIn((50 * density).toInt(), (screenH - panelHeight - (80 * density).toInt()).coerceAtLeast(50))

        val panelParams = WindowManager.LayoutParams(
            panelWidth,
            panelHeight,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = posX
            y = posY
        }

        // Build the entire floating vault panel programmatically
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                setColor(Color.parseColor("#0F172A"))
                cornerRadius = 20 * density
                setStroke((1.5f * density).toInt(), Color.parseColor("#334155"))
            }
            background = bg
            setPadding((14 * density).toInt(), (14 * density).toInt(), (14 * density).toInt(), (12 * density).toInt())
        }

        // 1. Header Row
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }

        val titleView = TextView(this).apply {
            text = "PROJECT X VAULT"
            setTextColor(Color.parseColor("#00B4D8"))
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeBtn = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#94A3B8"))
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            setPadding((8 * density).toInt(), (4 * density).toInt(), (8 * density).toInt(), (4 * density).toInt())
            setOnClickListener { closeFloatingVaultPanel() }
        }

        headerRow.addView(titleView)
        headerRow.addView(closeBtn)
        rootLayout.addView(headerRow)

        // 2. Search Input
        val searchBox = EditText(this).apply {
            hint = "Search cards, numbers, fields..."
            setHintTextColor(Color.parseColor("#64748B"))
            setTextColor(Color.WHITE)
            textSize = 12.5f
            setSingleLine(true)
            val searchBg = GradientDrawable().apply {
                setColor(Color.parseColor("#1E293B"))
                cornerRadius = 12 * density
                setStroke((1f * density).toInt(), Color.parseColor("#334155"))
            }
            background = searchBg
            setPadding((12 * density).toInt(), (8 * density).toInt(), (12 * density).toInt(), (8 * density).toInt())
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.topMargin = (10 * density).toInt()
            lp.bottomMargin = (6 * density).toInt()
            layoutParams = lp
        }
        rootLayout.addView(searchBox)

        // 2b. Context-Aware Quick Autofill Intent Strip
        val quickScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            lp.bottomMargin = (8 * density).toInt()
            layoutParams = lp
        }

        val quickContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val quickIntents = listOf("IFSC", "Aadhaar", "PAN", "Mobile", "Father", "Account", "Marks", "Roll No")
        for (intent in quickIntents) {
            val pill = TextView(this).apply {
                text = "⚡ $intent"
                setTextColor(Color.parseColor("#38BDF8"))
                textSize = 10f
                typeface = Typeface.DEFAULT_BOLD
                val pBg = GradientDrawable().apply {
                    setColor(Color.parseColor("#1E293B"))
                    cornerRadius = 8 * density
                    setStroke((1f * density).toInt(), Color.parseColor("#334155"))
                }
                background = pBg
                setPadding((8 * density).toInt(), (4 * density).toInt(), (8 * density).toInt(), (4 * density).toInt())
                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    rightMargin = (6 * density).toInt()
                }
                layoutParams = lp
                setOnClickListener {
                    searchBox.setText(intent)
                    searchBox.setSelection(intent.length)
                }
            }
            quickContainer.addView(pill)
        }
        quickScroll.addView(quickContainer)
        rootLayout.addView(quickScroll)

        // 3. Scrollable Documents & Fields Container
        val scrollView = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)
            isVerticalScrollBarEnabled = false
        }

        val docsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
        scrollView.addView(docsContainer)
        rootLayout.addView(scrollView)

        fun populateDocs(query: String = "") {
            docsContainer.removeAllViews()
            val q = query.trim().lowercase()

            val filtered = allVaultDocs.filter { doc ->
                if (q.isEmpty()) true
                else {
                    doc.title.lowercase().contains(q) ||
                    doc.category.lowercase().contains(q) ||
                    doc.owner.lowercase().contains(q) ||
                    (doc.idNumber != null && doc.idNumber.lowercase().contains(q)) ||
                    doc.fields.any { f -> f.name.lowercase().contains(q) || f.value.lowercase().contains(q) }
                }
            }

            if (filtered.isEmpty()) {
                val emptyTv = TextView(this).apply {
                    text = if (q.isEmpty()) "No verified documents in vault yet.\nOpen Project X to sync your folder." else "No matches found for \"$query\""
                    setTextColor(Color.parseColor("#64748B"))
                    textSize = 12f
                    gravity = Gravity.CENTER
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    lp.topMargin = (40 * density).toInt()
                    layoutParams = lp
                }
                docsContainer.addView(emptyTv)
                return
            }

            for (doc in filtered) {
                val docCard = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    val cardBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#1E293B"))
                        cornerRadius = 14 * density
                        setStroke((1f * density).toInt(), Color.parseColor("#334155"))
                    }
                    background = cardBg
                    setPadding((12 * density).toInt(), (10 * density).toInt(), (12 * density).toInt(), (10 * density).toInt())
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    lp.bottomMargin = (8 * density).toInt()
                    layoutParams = lp
                }

                // Header inside Document Card: Title + Owner Pill
                val cardHeader = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                }

                val docTitle = TextView(this).apply {
                    text = doc.title
                    setTextColor(Color.WHITE)
                    textSize = 12.5f
                    typeface = Typeface.DEFAULT_BOLD
                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                }

                val ownerPill = TextView(this).apply {
                    text = doc.owner
                    setTextColor(Color.parseColor("#38BDF8"))
                    textSize = 10f
                    typeface = Typeface.DEFAULT_BOLD
                    val pillBg = GradientDrawable().apply {
                        setColor(Color.parseColor("#0F172A"))
                        cornerRadius = 6 * density
                    }
                    background = pillBg
                    setPadding((6 * density).toInt(), (2 * density).toInt(), (6 * density).toInt(), (2 * density).toInt())
                }

                cardHeader.addView(docTitle)
                cardHeader.addView(ownerPill)

                // Attention / Expiry Badge
                if (!doc.expiryDate.isNullOrEmpty()) {
                    try {
                        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                        val datePart = doc.expiryDate.split("T")[0]
                        val expDate = sdf.parse(datePart)
                        if (expDate != null) {
                            val now = System.currentTimeMillis()
                            val diffDays = ((expDate.time - now) / (1000 * 60 * 60 * 24)).toInt()
                            val statusBadge = TextView(this).apply {
                                if (diffDays < 0) {
                                    text = "EXPIRED"
                                    setTextColor(Color.parseColor("#EF4444"))
                                    background = GradientDrawable().apply {
                                        setColor(Color.parseColor("#450A0A"))
                                        cornerRadius = 5 * density
                                    }
                                } else if (diffDays <= 45) {
                                    text = "Exp ${diffDays}d"
                                    setTextColor(Color.parseColor("#F59E0B"))
                                    background = GradientDrawable().apply {
                                        setColor(Color.parseColor("#451A03"))
                                        cornerRadius = 5 * density
                                    }
                                } else {
                                    text = "Valid"
                                    setTextColor(Color.parseColor("#10B981"))
                                    background = GradientDrawable().apply {
                                        setColor(Color.parseColor("#064E3B"))
                                        cornerRadius = 5 * density
                                    }
                                }
                                textSize = 9.5f
                                typeface = Typeface.DEFAULT_BOLD
                                setPadding((5 * density).toInt(), (1 * density).toInt(), (5 * density).toInt(), (1 * density).toInt())
                                val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                                lp.marginStart = (4 * density).toInt()
                                layoutParams = lp
                            }
                            cardHeader.addView(statusBadge)
                        }
                    } catch (e: Exception) {}
                }

                docCard.addView(cardHeader)

                // ID Number Row if present
                if (!doc.idNumber.isNullOrEmpty()) {
                    val idTv = TextView(this).apply {
                        text = "ID: ${doc.idNumber}"
                        setTextColor(Color.parseColor("#94A3B8"))
                        textSize = 11f
                        val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                        lp.topMargin = (3 * density).toInt()
                        layoutParams = lp
                    }
                    docCard.addView(idTv)
                }

                // Extracted Fields Section - Directly viewable like a real vault
                val fieldsLayout = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    lp.topMargin = (8 * density).toInt()
                    layoutParams = lp
                }

                // Show all extracted fields directly by default
                var isExpanded = true
                val toggleHint = TextView(this).apply {
                    text = "▼ Extracted Details (${doc.fields.size}):"
                    setTextColor(Color.parseColor("#38BDF8"))
                    textSize = 10.5f
                    typeface = Typeface.DEFAULT_BOLD
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    lp.topMargin = (6 * density).toInt()
                    layoutParams = lp
                }

                fun renderFields() {
                    fieldsLayout.removeAllViews()
                    if (!isExpanded) return

                    for (field in doc.fields) {
                        val fieldRow = LinearLayout(this).apply {
                            orientation = LinearLayout.HORIZONTAL
                            gravity = Gravity.CENTER_VERTICAL
                            val rowBg = GradientDrawable().apply {
                                setColor(Color.parseColor("#0F172A"))
                                cornerRadius = 8 * density
                            }
                            background = rowBg
                            setPadding((8 * density).toInt(), (6 * density).toInt(), (8 * density).toInt(), (6 * density).toInt())
                            val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                            lp.bottomMargin = (4 * density).toInt()
                            layoutParams = lp
                        }

                        val fieldTextCol = LinearLayout(this).apply {
                            orientation = LinearLayout.VERTICAL
                            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                        }

                        val fieldNameTv = TextView(this).apply {
                            text = field.name
                            setTextColor(Color.parseColor("#94A3B8"))
                            textSize = 10f
                        }

                        val fieldValueTv = TextView(this).apply {
                            text = field.value
                            setTextColor(Color.WHITE)
                            textSize = 11.5f
                            typeface = Typeface.DEFAULT_BOLD
                        }

                        fieldTextCol.addView(fieldNameTv)
                        fieldTextCol.addView(fieldValueTv)

                        val copyBtn = TextView(this).apply {
                            text = "COPY"
                            setTextColor(Color.parseColor("#00F2FE"))
                            textSize = 10.5f
                            typeface = Typeface.DEFAULT_BOLD
                            val copyBg = GradientDrawable().apply {
                                setColor(Color.parseColor("#1E293B"))
                                cornerRadius = 6 * density
                                setStroke((1f * density).toInt(), Color.parseColor("#00B4D8"))
                            }
                            background = copyBg
                            setPadding((8 * density).toInt(), (4 * density).toInt(), (8 * density).toInt(), (4 * density).toInt())
                            setOnClickListener {
                                copyToClipboard(field.name, field.value)
                            }
                        }

                        fieldRow.addView(fieldTextCol)
                        fieldRow.addView(copyBtn)
                        fieldsLayout.addView(fieldRow)
                    }
                }

                toggleHint.setOnClickListener {
                    isExpanded = !isExpanded
                    toggleHint.text = if (isExpanded) "▼ Extracted Details (${doc.fields.size}):" else "▶ Tap to view all ${doc.fields.size} extracted fields"
                    renderFields()
                }

                docCard.addView(toggleHint)
                renderFields()
                docCard.addView(fieldsLayout)
                docsContainer.addView(docCard)
            }
        }

        populateDocs()

        searchBox.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable?) { populateDocs(s?.toString() ?: "") }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        })

        // Tap outside handler to dismiss
        rootLayout.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_OUTSIDE) {
                closeFloatingVaultPanel()
                true
            } else false
        }

        floatingPanelView = rootLayout
        windowManager?.addView(floatingPanelView, panelParams)
    }

    private fun copyToClipboard(label: String, value: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText(label, value)
        clipboard.setPrimaryClip(clip)

        // Haptic feedback
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(30)
            }
        } catch (e: Exception) {}

        Toast.makeText(this, "Copied $label: $value", Toast.LENGTH_SHORT).show()
    }

    private fun loadVaultDocuments(): List<VaultDocItem> {
        val possibleCacheFiles = listOf(
            File(filesDir, "vault_cache.json"),
            File(filesDir.parentFile, "app_flutter/vault_cache.json"),
            File(filesDir.parentFile, "files/vault_cache.json")
        )

        for (f in possibleCacheFiles) {
            if (f.exists()) {
                try {
                    val jsonStr = f.readText()
                    val array = JSONArray(jsonStr)
                    val list = mutableListOf<VaultDocItem>()
                    for (i in 0 until array.length()) {
                        val obj = array.getJSONObject(i)
                        val fieldsArr = obj.optJSONArray("fields")
                        val fields = mutableListOf<VaultFieldItem>()
                        if (fieldsArr != null) {
                            for (j in 0 until fieldsArr.length()) {
                                val fObj = fieldsArr.getJSONObject(j)
                                val fName = fObj.optString("name")
                                val fVal = fObj.optString("value")
                                if (fVal.isNotEmpty() && fVal.lowercase() != "null") {
                                    fields.add(VaultFieldItem(name = fName, value = fVal))
                                }
                            }
                        }
                        val fnField = fields.find {
                            val n = it.name.lowercase()
                            n == "full name" || n == "name" || n == "holder name" ||
                            n == "cardholder name" || n == "student name" || n == "candidate name" ||
                            n == "policy holder" || n == "insured name"
                        }
                        val realOwner = if (!fnField?.value.isNullOrBlank() &&
                            !fnField?.value.equals("Unknown", ignoreCase = true) &&
                            !fnField?.value.equals("Primary User", ignoreCase = true) &&
                            !fnField?.value.equals("Primary Cardholder", ignoreCase = true)) {
                            fnField!!.value
                        } else {
                            obj.optString("owner", "Self")
                        }

                        list.add(
                            VaultDocItem(
                                id = obj.optString("id"),
                                title = obj.optString("title"),
                                category = obj.optString("category"),
                                owner = realOwner,
                                idNumber = if (obj.isNull("id_number")) null else obj.optString("id_number"),
                                expiryDate = if (obj.isNull("expiry_date")) null else obj.optString("expiry_date"),
                                fields = fields
                            )
                        )
                    }
                    if (list.isNotEmpty()) return list
                } catch (e: Exception) {
                    Log.e("AssistiveBallService", "Error reading vault_cache.json: ${e.message}")
                }
            }
        }
        return emptyList()
    }

    override fun onDestroy() {
        super.onDestroy()
        closeFloatingVaultPanel()
        try {
            floatingBallView?.let {
                windowManager?.removeView(it)
                floatingBallView = null
            }
        } catch (e: Exception) {
            Log.e("AssistiveBallService", "Failed to remove floating ball: ${e.message}")
        }
    }
}
