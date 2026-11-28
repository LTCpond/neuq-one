package org.neuqone.neuq_one.widgets

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class WidgetDataBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "org.neuqone.neuq_one/widgets")
    // Accessed exclusively on the widget executor.
    private var navigation: WidgetNavigation.Link? = null
    @Volatile private var closed = false

    init {
        WidgetUpdateManager.submit {
            val store = WidgetUpdateManager.store(context)
            navigation = runCatching { WidgetNavigation.read(context, activity.intent, store) }.getOrNull()
            store.suspendVerification()
            WidgetUpdateManager.refresh(context)
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "verify" -> perform(result) {
                    val owner = call.argument<String>("owner")
                    val discard = call.argument<Boolean>("discard") == true
                    val store = WidgetUpdateManager.store(context)
                    val previous = store.link()
                    val lease = when {
                        owner != null -> store.confirm(owner)
                        discard -> { store.clear(); null }
                        else -> { store.suspendVerification(); null }
                    }
                    if (discard || (previous != null && previous != store.link())) {
                        navigation = null
                        WidgetConfigStore(context).resetSelections()
                    }
                    WidgetUpdateManager.refresh(context)
                    if (lease != null && navigation != null) announceNavigation()
                    lease.orEmpty()
                }
                "publish" -> perform(result, cancellable = true) {
                    val lease = requireNotNull(call.argument<String>("lease"))
                    val section = requireNotNull(call.argument<String>("section"))
                    val json = requireNotNull(call.argument<String>("json"))
                    val changed = WidgetUpdateManager.store(context).update(lease, section, json)
                    if (changed) WidgetUpdateManager.refresh(context)
                    changed
                }
                "publishBatch" -> perform(result, cancellable = true) {
                    val lease = requireNotNull(call.argument<String>("lease"))
                    val sections = requireNotNull(call.argument<Map<String, String>>("sections"))
                    val changed = WidgetUpdateManager.store(context).updateAll(lease, sections)
                    if (changed) WidgetUpdateManager.refresh(context)
                    changed
                }
                "takeNavigation" -> perform(result, cancellable = true) {
                    val store = WidgetUpdateManager.store(context)
                    if (store.snapshot() == null) null
                    else navigation?.also { navigation = null }
                        ?.takeIf { it.ownerLink == null || it.ownerLink == store.link() }?.arguments()
                }
                "preview" -> {
                    val kind = WidgetKind.parse(call.argument("kind"))
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    if (kind == null || width == null || height == null || width !in 120..460 || height !in 60..560) {
                        result.error("widget_preview", null, null)
                    } else {
                        preview(kind, WidgetSize(width, height), result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun perform(result: MethodChannel.Result, cancellable: Boolean = false, task: () -> Any?) {
        val start = SystemClock.elapsedRealtime()
        WidgetUpdateManager.submit {
            if (cancellable && (closed || SystemClock.elapsedRealtime() - start > 3_000)) {
                activity.runOnUiThread { result.error("widget_cancelled", null, null) }
            } else {
                val outcome = runCatching(task)
                activity.runOnUiThread {
                    outcome.fold(result::success) { result.error("widget_storage", null, null) }
                }
            }
        }
    }

    fun accept(intent: Intent) {
        WidgetUpdateManager.submit {
            val store = WidgetUpdateManager.store(context)
            runCatching { WidgetNavigation.read(context, intent, store) }.getOrNull()?.let {
                navigation = it
                announceNavigation()
            }
        }
    }

    private fun announceNavigation() {
        activity.runOnUiThread { if (!closed) channel.invokeMethod("navigationAvailable", null) }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
    }

    private fun preview(kind: WidgetKind, size: WidgetSize, result: MethodChannel.Result) {
        val start = SystemClock.elapsedRealtime()
        WidgetUpdateManager.submit {
            if (closed || SystemClock.elapsedRealtime() - start > 3_000) {
                activity.runOnUiThread { result.error("widget_cancelled", null, null) }
                return@submit
            }
            val views = runCatching {
                WidgetRenderer(activity).render(kind, 0, size,
                    WidgetData(WidgetUpdateManager.store(context).snapshot()), null, null, preview = true)
            }.getOrElse {
                activity.runOnUiThread { result.error("widget_preview", null, null) }
                return@submit
            }
            activity.runOnUiThread {
                if (closed) {
                    result.error("widget_cancelled", null, null)
                    return@runOnUiThread
                }
                val bitmap = runCatching { WidgetPreview.draw(activity, views, size) }.getOrElse {
                    result.error("widget_preview", null, null)
                    return@runOnUiThread
                }
                perform(result) {
                    try {
                        ByteArrayOutputStream().use {
                            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                            it.toByteArray()
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
        }
    }
}

internal object WidgetPreview {
    fun draw(context: android.content.Context, views: android.widget.RemoteViews, size: WidgetSize): Bitmap {
        val look = WidgetAppearance(context)
        val width = look.dp(size.width)
        val height = look.dp(size.height)
        val host = FrameLayout(context)
        val view = views.apply(context, host)
        host.addView(view)
        host.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        host.layout(0, 0, width, height)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        host.draw(Canvas(bitmap))
        return bitmap
    }
}
