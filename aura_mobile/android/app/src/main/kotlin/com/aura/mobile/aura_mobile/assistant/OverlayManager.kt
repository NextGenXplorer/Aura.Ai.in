package com.aura.mobile.aura_mobile.assistant

import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * OverlayManager draws a floating overlay using WindowManager.addView().
 * This works correctly from a Background Service with SYSTEM_ALERT_WINDOW permission,
 * avoiding Android 10+ BAL_BLOCK restrictions on startActivity().
 */
class OverlayManager(private val context: Context) {

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private val handler = Handler(Looper.getMainLooper())
    private val activeAnimators = mutableListOf<ObjectAnimator>()
    private var isShowing = false
    private var isTouchable = false

    // Floating mic bubble
    private var bubbleView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var removeRunnable: Runnable? = null

    fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else true
    }

    fun showOverlay(state: String) {
        if (!canDrawOverlays()) {
            Log.e("OverlayManager", "Cannot draw overlays - permission not granted")
            return
        }
        handler.post {
            removeRunnable?.let { handler.removeCallbacks(it) }
            if (overlayView == null) {
                createAndAddOverlayView()
            }
            // Always ensure the overlay is touchable when shown
            setTouchable(true)
            updateState(state)
        }
    }

    fun updateState(state: String) {
        handler.post {
            if (overlayView == null) return@post
            val statusText: TextView? = overlayView!!.findViewWithTag("status_text")
            val orbContainer: FrameLayout? = overlayView!!.findViewWithTag("orb_container")
            val centerButton: FrameLayout? = orbContainer?.findViewWithTag("center_button")
            val centerIcon: ImageView? = centerButton?.getChildAt(0) as? ImageView

            when (state) {
                "LISTENING" -> {
                    statusText?.text = "Hi there, I'm listening..."
                    showOverlayPanel()
                    startPulseAnimation(null)
                    centerIcon?.setImageResource(android.R.drawable.ic_btn_speak_now)
                }
                "PROCESSING" -> {
                    statusText?.text = "Thinking about that..."
                    showOverlayPanel()
                    startSpinAnimation(null)
                    centerIcon?.setImageResource(android.R.drawable.presence_audio_online)
                }
                "SPEAKING" -> {
                    statusText?.text = "Here's what I found..."
                    showOverlayPanel()
                    startPulseAnimation(null)
                    centerIcon?.setImageResource(android.R.drawable.presence_audio_online)
                }
                "IDLE" -> {
                    hideOverlay()
                }
            }
        }
    }

    fun updateListeningText(text: String) {
        handler.post {
            if (overlayView == null) return@post
            val statusText: TextView? = overlayView!!.findViewWithTag("status_text")
            statusText?.text = text
        }
    }

    fun hideOverlay() {
        handler.post {
            if (overlayView == null) return@post
            
            // Immediately let touches pass through to the app underneath
            setTouchable(false)
 
            // Animate out before removing
            val panel: View? = overlayView?.findViewWithTag("panel")
            val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

            stopAnimations()
            val duration = 300L
            
            panel?.let {
                ObjectAnimator.ofFloat(it, "translationY", it.translationY, dpToPx(320).toFloat())
                    .apply { this.duration = duration; start() }
            }
            dimBg?.let {
                ObjectAnimator.ofFloat(it, "alpha", it.alpha, 0f).apply { this.duration = duration; start() }
            }

            // Delay removal until animation completes
            removeRunnable?.let { handler.removeCallbacks(it) }
            removeRunnable = Runnable {
                try {
                    overlayView?.let { windowManager.removeViewImmediate(it) }
                } catch (e: Exception) {
                    Log.e("OverlayManager", "Error removing overlay: ${e.message}")
                }
                overlayView = null
                isShowing = false
            }
            handler.postDelayed(removeRunnable!!, duration + 50)
        }
    }

    /**
     * Show a small draggable floating mic bubble on the right edge of the screen.
     * Tapping it calls [onTap] to trigger the assistant.
     */
    fun showFloatingBubble(onTap: () -> Unit) {
        if (!canDrawOverlays()) return
        handler.post {
            if (bubbleView != null) return@post // already showing

            val size = dpToPx(56)
            val params = WindowManager.LayoutParams(
                size, size,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = dpToPx(8)
                y = dpToPx(200)
            }
            bubbleParams = params

            // Build the bubble view with 3D shadow and terracotta fill
            val bubble = FrameLayout(context).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    elevation = dpToPx(8).toFloat()
                }
            }
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#BC4B2E")) // Terracotta accent color
                setStroke(dpToPx(2), Color.parseColor("#FFF0EC")) // Soft rose outline
            }
            bubble.background = bg

            // Crisp white mic icon instead of raw emoji
            val micIcon = ImageView(context).apply {
                setImageResource(android.R.drawable.ic_btn_speak_now)
                setColorFilter(Color.WHITE)
                scaleType = ImageView.ScaleType.FIT_CENTER
                setPadding(dpToPx(13), dpToPx(13), dpToPx(13), dpToPx(13))
            }
            bubble.addView(micIcon, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))

            // Drag + tap logic
            var dragStartX = 0f
            var dragStartY = 0f
            var startParamsX = 0
            var startParamsY = 0
            var isDragging = false

            bubble.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartX = event.rawX
                        dragStartY = event.rawY
                        startParamsX = params.x
                        startParamsY = params.y
                        isDragging = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - dragStartX
                        val dy = event.rawY - dragStartY
                        if (Math.abs(dx) > 8 || Math.abs(dy) > 8) isDragging = true
                        if (isDragging) {
                            params.x = (startParamsX - dx).toInt().coerceAtLeast(0)
                            params.y = (startParamsY + dy).toInt().coerceAtLeast(0)
                            try { windowManager.updateViewLayout(bubble, params) } catch (e: Exception) { }
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            // It's a tap — pulse animation + trigger
                            ObjectAnimator.ofFloat(bubble, "scaleX", 1f, 1.25f, 1f)
                                .apply { duration = 200; start() }
                            ObjectAnimator.ofFloat(bubble, "scaleY", 1f, 1.25f, 1f)
                                .apply { duration = 200; start() }
                            handler.postDelayed({ onTap() }, 100)
                        }
                        true
                    }
                    else -> false
                }
            }

            bubbleView = bubble
            try {
                windowManager.addView(bubble, params)
                Log.d("OverlayManager", "Floating bubble shown")
            } catch (e: Exception) {
                Log.e("OverlayManager", "Failed to show bubble: ${e.message}")
                bubbleView = null
            }
        }
    }

    fun hideFloatingBubble() {
        handler.post {
            try {
                bubbleView?.let { windowManager.removeView(it) }
            } catch (e: Exception) { }
            bubbleView = null
        }
    }

    private fun createAndAddOverlayView() {
        windowParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM
        }

        val params = windowParams!!

        val rootFrame = object : FrameLayout(context) {
            override fun dispatchKeyEvent(event: android.view.KeyEvent?): Boolean {
                if (event?.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                    hideOverlay()
                    val cancelIntent = android.content.Intent("com.aura.mobile.assistant.CANCEL")
                    cancelIntent.setPackage(context.packageName)
                    context.sendBroadcast(cancelIntent)
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        rootFrame.setBackgroundColor(Color.TRANSPARENT)

        // Full-screen dim overlay
        val dimBackground = View(context)
        dimBackground.setBackgroundColor(Color.argb(90, 0, 0, 0))
        dimBackground.alpha = 0f
        dimBackground.tag = "dim_bg"
        dimBackground.setOnClickListener {
            // Dismiss assistant when tapping outside the panel
            hideOverlay()
            val cancelIntent = android.content.Intent("com.aura.mobile.assistant.CANCEL")
            cancelIntent.setPackage(context.packageName)
            context.sendBroadcast(cancelIntent)
        }
        rootFrame.addView(dimBackground, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Sliding panel container
        val panelLayout = FrameLayout(context)
        panelLayout.tag = "panel"
        panelLayout.translationY = dpToPx(320).toFloat()

        val innerPanel = FrameLayout(context)
        innerPanel.tag = "inner_panel"
        
        // Modern rounded top background matching warm-paper cream
        val panelBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(Color.parseColor("#F7F4EF")) // Warm paper background (ClayColors.obsidianBg)
            cornerRadii = floatArrayOf(
                dpToPx(24).toFloat(), dpToPx(24).toFloat(), // top left
                dpToPx(24).toFloat(), dpToPx(24).toFloat(), // top right
                0f, 0f, // bottom right
                0f, 0f  // bottom left
            )
            setStroke(dpToPx(2), Color.parseColor("#EAD5D0")) // subtle warm top border
        }
        innerPanel.background = panelBg
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            innerPanel.elevation = dpToPx(16).toFloat()
        }
        
        // Sleek Drag Handle Indicator
        val dragHandle = View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(4).toFloat()
                setColor(Color.parseColor("#C8C2B4")) // warm sepia-grey drag handle
            }
        }
        val handleParams = FrameLayout.LayoutParams(dpToPx(36), dpToPx(4)).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            setMargins(0, dpToPx(12), 0, 0)
        }
        innerPanel.addView(dragHandle, handleParams)

        val statusTextView = TextView(context)
        statusTextView.text = "Hi there, I'm listening..."
        statusTextView.setTextColor(Color.parseColor("#191816")) // deep warm ink text
        statusTextView.textSize = 22f
        statusTextView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL))
        statusTextView.gravity = Gravity.CENTER
        statusTextView.tag = "status_text"
        statusTextView.setPadding(40, dpToPx(32), 40, dpToPx(16))
        val statusParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        statusParams.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        innerPanel.addView(statusTextView, statusParams)

        // Orb Container
        val orbContainer = FrameLayout(context).apply {
            tag = "orb_container"
        }
        val orbContainerParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            dpToPx(200)
        ).apply {
            gravity = Gravity.CENTER
        }

        // Orb 1 (Sky Blue / Purple)
        val orb3 = View(context).apply {
            tag = "orb3"
            background = createGradientOrb("#54C5F8", "#7E6BCE", 60)
            alpha = 0.8f
        }
        val p3 = FrameLayout.LayoutParams(dpToPx(120), dpToPx(120)).apply { gravity = Gravity.CENTER }

        // Orb 2 (Terracotta Core)
        val orb1 = View(context).apply {
            tag = "orb1"
            background = createGradientOrb("#E25F4E", "#BC4B2E", 55)
            alpha = 0.85f
        }
        val p1 = FrameLayout.LayoutParams(dpToPx(110), dpToPx(110)).apply { gravity = Gravity.CENTER }

        // Orb 3 (Amber / Gold)
        val orb2 = View(context).apply {
            tag = "orb2"
            background = createGradientOrb("#FFF0EC", "#D1A153", 50)
            alpha = 0.8f
        }
        val p2 = FrameLayout.LayoutParams(dpToPx(95), dpToPx(95)).apply { gravity = Gravity.CENTER }

        orbContainer.addView(orb3, p3)
        orbContainer.addView(orb1, p1)
        orbContainer.addView(orb2, p2)

        // Central white button containing terracotta mic icon
        val centerButtonSize = dpToPx(52)
        val centerButton = FrameLayout(context).apply {
            tag = "center_button"
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dpToPx(4).toFloat()
            }
        }
        val centerIcon = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            setColorFilter(Color.parseColor("#BC4B2E"))
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(12))
        }
        centerButton.addView(centerIcon, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        
        val centerBtnParams = FrameLayout.LayoutParams(centerButtonSize, centerButtonSize).apply {
            gravity = Gravity.CENTER
        }
        orbContainer.addView(centerButton, centerBtnParams)
        innerPanel.addView(orbContainer, orbContainerParams)

        panelLayout.addView(innerPanel, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        val panelParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            dpToPx(320)
        )
        panelParams.gravity = Gravity.BOTTOM
        rootFrame.addView(panelLayout, panelParams)

        overlayView = rootFrame
        try {
            windowManager.addView(rootFrame, params)
            Log.d("OverlayManager", "Overlay view added to WindowManager successfully")
        } catch (e: Exception) {
            Log.e("OverlayManager", "Failed to add overlay: ${e.message}")
            overlayView = null
        }
    }

    /**
     * Show a contact disambiguation picker inside the overlay.
     * Creates tappable buttons for each matching contact, calls [onSelected] when tapped.
     */
    fun showContactPicker(
        contacts: List<DeviceControlService.ContactMatch>,
        onSelected: (DeviceControlService.ContactMatch) -> Unit
    ) {
        handler.post {
            if (!canDrawOverlays()) return@post
            if (overlayView == null) createAndAddOverlayView()

            // Enable touches on the overlay window
            setTouchable(true)

            val statusText: TextView? = overlayView!!.findViewWithTag("status_text")
            val orbContainer: View? = overlayView!!.findViewWithTag("orb_container")
            val innerPanel: FrameLayout? = overlayView!!.findViewWithTag("inner_panel")

            statusText?.text = "Who do you want to call?"

            // Hide orb, show contact list
            orbContainer?.visibility = View.GONE

            // Remove any existing contact list
            val existingList: View? = overlayView!!.findViewWithTag("contact_list")
            (existingList?.parent as? ViewGroup)?.removeView(existingList)

            val scrollView = ScrollView(context).apply { tag = "contact_list" }
            val listLayout = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(24))
            }

            contacts.forEachIndexed { index, contact ->
                val btn = TextView(context).apply {
                    text = "${index + 1}. ${contact.displayName}\n${contact.number}"
                    setTextColor(Color.parseColor("#191816")) // deep warm ink text
                    textSize = 15f
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                    setPadding(dpToPx(20), dpToPx(14), dpToPx(20), dpToPx(14))
                    background = createContactButtonBackground()
                    setOnClickListener {
                        setTouchable(false)
                        orbContainer?.visibility = View.VISIBLE
                        val contactList: View? = overlayView?.findViewWithTag("contact_list")
                        (contactList?.parent as? ViewGroup)?.removeView(contactList)
                        updateState("IDLE")
                        onSelected(contact)
                    }
                }
                val btnParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, 0, dpToPx(10)) }
                listLayout.addView(btn, btnParams)
            }

            scrollView.addView(listLayout)
            val scrollParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dpToPx(220)
            ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL }

            innerPanel?.addView(scrollView, scrollParams)
            showOverlayPanel()
        }
    }

    private fun setTouchable(enabled: Boolean) {
        if (isTouchable == enabled) return
        isTouchable = enabled
        val params = windowParams ?: return
        val root = overlayView ?: return
        if (enabled) {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        } else {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        try { windowManager.updateViewLayout(root, params) } catch (e: Exception) { }
    }

    private fun createContactButtonBackground(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(14).toFloat()
            setColor(Color.parseColor("#EFECE6")) // ClayColors.warmGrey base
            setStroke(dpToPx(1), Color.parseColor("#BC4B2E")) // Terracotta outline border
        }
    }

    private var panelAnimator: ObjectAnimator? = null
    private var dimAnimator: ObjectAnimator? = null

    private fun showOverlayPanel() {
        if (isShowing) return
        isShowing = true
        val panel: View = overlayView?.findViewWithTag("panel") ?: return
        val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

        panelAnimator?.cancel()
        dimAnimator?.cancel()

        panelAnimator = ObjectAnimator.ofFloat(panel, "translationY", panel.translationY, 0f)
            .apply { duration = 400; interpolator = android.view.animation.DecelerateInterpolator(); start() }
        
        dimBg?.let {
            dimAnimator = ObjectAnimator.ofFloat(it, "alpha", it.alpha, 1f)
                .apply { duration = 400; start() }
        }
    }

    private fun hideOverlayPanel() {
        if (!isShowing) return
        isShowing = false
        val panel: View = overlayView?.findViewWithTag("panel") ?: return
        val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

        panelAnimator?.cancel()
        dimAnimator?.cancel()

        panelAnimator = ObjectAnimator.ofFloat(panel, "translationY", panel.translationY, dpToPx(320).toFloat())
            .apply { duration = 300; interpolator = android.view.animation.AccelerateInterpolator(); start() }
            
        dimBg?.let {
            dimAnimator = ObjectAnimator.ofFloat(it, "alpha", it.alpha, 0f)
                .apply { duration = 300; start() }
        }
    }

    private fun startPulseAnimation(view: View?) {
        val container = overlayView?.findViewWithTag<FrameLayout>("orb_container") ?: return
        val orb1 = container.findViewWithTag<View>("orb1")
        val orb2 = container.findViewWithTag<View>("orb2")
        val orb3 = container.findViewWithTag<View>("orb3")

        stopAnimations()

        if (orb1 != null && orb2 != null && orb3 != null) {
            // Orb 1 (Terracotta): slow horizontal sway and gentle pulse
            val tx1 = ObjectAnimator.ofFloat(orb1, "translationX", -dpToPx(16).toFloat(), dpToPx(12).toFloat()).apply {
                duration = 2400
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sx1 = ObjectAnimator.ofFloat(orb1, "scaleX", 0.95f, 1.2f).apply {
                duration = 1800
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sy1 = ObjectAnimator.ofFloat(orb1, "scaleY", 0.95f, 1.2f).apply {
                duration = 1800
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }

            // Orb 2 (Amber/Gold): slow vertical sway and opposite pulse
            val ty2 = ObjectAnimator.ofFloat(orb2, "translationY", -dpToPx(12).toFloat(), dpToPx(16).toFloat()).apply {
                duration = 2000
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sx2 = ObjectAnimator.ofFloat(orb2, "scaleX", 1.15f, 0.85f).apply {
                duration = 2200
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sy2 = ObjectAnimator.ofFloat(orb2, "scaleY", 1.15f, 0.85f).apply {
                duration = 2200
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }

            // Orb 3 (Sky Blue / Purple): diagonal sway and moderate breathing pulse
            val tx3 = ObjectAnimator.ofFloat(orb3, "translationX", dpToPx(14).toFloat(), -dpToPx(14).toFloat()).apply {
                duration = 2700
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val ty3 = ObjectAnimator.ofFloat(orb3, "translationY", dpToPx(8).toFloat(), -dpToPx(12).toFloat()).apply {
                duration = 2700
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sx3 = ObjectAnimator.ofFloat(orb3, "scaleX", 0.88f, 1.16f).apply {
                duration = 2500
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }
            val sy3 = ObjectAnimator.ofFloat(orb3, "scaleY", 0.88f, 1.16f).apply {
                duration = 2500
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.REVERSE
                interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            }

            activeAnimators.addAll(listOf(tx1, sx1, sy1, ty2, sx2, sy2, tx3, ty3, sx3, sy3))
            activeAnimators.forEach { it.start() }
        }
    }

    private fun startSpinAnimation(view: View?) {
        val container = overlayView?.findViewWithTag<FrameLayout>("orb_container") ?: return
        val orb1 = container.findViewWithTag<View>("orb1")
        val orb2 = container.findViewWithTag<View>("orb2")
        val orb3 = container.findViewWithTag<View>("orb3")

        stopAnimations()

        if (orb1 != null && orb2 != null && orb3 != null) {
            // Spin/swirl the orbs relative to each other during processing
            val spin1 = ObjectAnimator.ofFloat(orb1, "rotation", 0f, 360f).apply {
                duration = 1800
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.RESTART
                interpolator = android.view.animation.LinearInterpolator()
            }
            val spin2 = ObjectAnimator.ofFloat(orb2, "rotation", 360f, 0f).apply {
                duration = 1500
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.RESTART
                interpolator = android.view.animation.LinearInterpolator()
            }
            val spin3 = ObjectAnimator.ofFloat(orb3, "rotation", 0f, 360f).apply {
                duration = 2200
                repeatCount = ObjectAnimator.INFINITE
                repeatMode = ObjectAnimator.RESTART
                interpolator = android.view.animation.LinearInterpolator()
            }
            activeAnimators.addAll(listOf(spin1, spin2, spin3))
            activeAnimators.forEach { it.start() }
        }
    }

    private fun stopAnimations() {
        activeAnimators.forEach { it.cancel() }
        activeAnimators.clear()
        
        val container = overlayView?.findViewWithTag<FrameLayout>("orb_container") ?: return
        val orb1 = container.findViewWithTag<View>("orb1")
        val orb2 = container.findViewWithTag<View>("orb2")
        val orb3 = container.findViewWithTag<View>("orb3")
        
        orb1?.apply { scaleX = 1f; scaleY = 1f; translationX = 0f; translationY = 0f; rotation = 0f }
        orb2?.apply { scaleX = 1f; scaleY = 1f; translationX = 0f; translationY = 0f; rotation = 0f }
        orb3?.apply { scaleX = 1f; scaleY = 1f; translationX = 0f; translationY = 0f; rotation = 0f }
    }

    private fun createGradientOrb(colorStart: String, colorEnd: String, radiusDp: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            gradientType = GradientDrawable.RADIAL_GRADIENT
            colors = intArrayOf(
                Color.parseColor(colorStart),
                Color.parseColor(colorEnd),
                Color.TRANSPARENT
            )
            setGradientRadius(dpToPx(radiusDp).toFloat())
        }
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}
