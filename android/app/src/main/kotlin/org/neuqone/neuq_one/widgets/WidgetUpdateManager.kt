package org.neuqone.neuq_one.widgets

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.util.SizeF
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.time.Instant
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class WidgetApplication : Application() {
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        WidgetUpdateManager.submit { WidgetUpdateManager.refresh(this) }
    }
}

abstract class NeuqWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        dispatch { WidgetUpdateManager.refresh(context) }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) =
        dispatch { WidgetUpdateManager.refresh(context, id) }

    override fun onDeleted(context: Context, ids: IntArray) = dispatch {
        val config = WidgetConfigStore(context)
        ids.forEach(config::delete)
        WidgetUpdateManager.refresh(context)
    }

    override fun onDisabled(context: Context) = dispatch { WidgetUpdateManager.refresh(context) }

    override fun onRestored(context: Context, oldIds: IntArray, newIds: IntArray) {
        // AppWidgetProvider calls onUpdate in the same broadcast after onRestored.
        WidgetUpdateManager.submit {
            val config = WidgetConfigStore(context)
            (oldIds + newIds).forEach(config::delete)
        }
    }
}

class TodayWidget : NeuqWidgetProvider()
class WeekWidget : NeuqWidgetProvider()
class ExamsWidget : NeuqWidgetProvider()

class WidgetEvents : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = dispatch {
        if (intent.action == USER_ACTION) {
            val parts = intent.data?.pathSegments
            if (parts?.size == 2) {
                parts[0].toIntOrNull()?.let { WidgetUpdateManager.action(context, it, parts[1]) }
            }
        } else {
            WidgetUpdateManager.refresh(context)
        }
    }

    companion object {
        const val USER_ACTION = "org.neuqone.neuq_one.widget.ACTION"
        const val CLOCK = "org.neuqone.neuq_one.widget.CLOCK"
    }
}

private fun BroadcastReceiver.dispatch(work: () -> Unit) {
    val pending = goAsync()
    val submitted = android.os.SystemClock.elapsedRealtime()
    WidgetUpdateManager.submit {
        try {
            if (android.os.SystemClock.elapsedRealtime() - submitted < 8_000) work()
        } catch (_: Exception) {
            // A bad host/options or temporarily unavailable storage must not crash the app.
        } finally {
            pending?.finish()
        }
    }
}

internal object WidgetUpdateManager {
    private val queue: ExecutorService = Executors.newSingleThreadExecutor()
    private var store: WidgetSnapshotStore? = null

    fun submit(work: () -> Unit) { queue.execute(work) }

    fun <T> await(default: T, work: () -> T): T {
        val task = queue.submit<T> { work() }
        return try {
            task.get(2, TimeUnit.SECONDS)
        } catch (_: TimeoutException) {
            task.cancel(false)
            default
        } catch (_: Exception) {
            default
        }
    }

    fun store(context: Context) = store ?: WidgetSnapshotStore(context.noBackupFilesDir).also { store = it }

    fun component(context: Context, kind: WidgetKind) = ComponentName(context, when (kind) {
        WidgetKind.TODAY -> TodayWidget::class.java
        WidgetKind.WEEK -> WeekWidget::class.java
        WidgetKind.EXAMS -> ExamsWidget::class.java
    })

    fun kind(context: Context, id: Int): WidgetKind? {
        val component = AppWidgetManager.getInstance(context).getAppWidgetInfo(id)?.provider ?: return null
        return WidgetKind.entries.firstOrNull { component == component(context, it) }
    }

    @Suppress("DEPRECATION")
    fun refresh(context: Context, only: Int? = null) {
        val manager = AppWidgetManager.getInstance(context)
        val all = WidgetKind.entries.associateWith { manager.getAppWidgetIds(component(context, it)) }
        val store = store(context)
        val data = WidgetData(store.snapshot())
        if (all.values.all { it.isEmpty() }) {
            schedule(context, null)
            return
        }
        val config = WidgetConfigStore(context)
        val renderer = WidgetRenderer(context)
        for ((kind, ids) in all) {
            for (id in ids) {
                if (only != null && only != id) continue
                // Each host instance can supply different bounds or omit them entirely.
                runCatching {
                    val choices = WidgetSizePolicy.choices(manager.getAppWidgetOptions(id), config.size(id) ?: kind.defaultSize)
                    config.resize(id, WidgetSizePolicy.current(context, choices))
                    val selected = data.term?.getString("id")?.let { config.week(id, it) }
                    val rendered = choices.map { renderer.render(kind, id, it, data, selected, store.link()) }
                    val views = when {
                        rendered.size == 1 -> rendered.first()
                        Build.VERSION.SDK_INT >= 31 -> RemoteViews(
                            choices.mapIndexed { index, size -> SizeF(size.width.toFloat(), size.height.toFloat()) to rendered[index] }.toMap()
                        )
                        else -> RemoteViews(rendered.last(), rendered.first())
                    }
                    manager.updateAppWidget(id, views)
                    if (kind == WidgetKind.EXAMS || kind == WidgetKind.TODAY) {
                        manager.notifyAppWidgetViewDataChanged(id, org.neuqone.neuq_one.R.id.widget_list)
                    }
                }
            }
        }
        schedule(context, data.nextUpdate(
            includeToday = all.getValue(WidgetKind.TODAY).isNotEmpty(),
            includeExams = all.getValue(WidgetKind.EXAMS).isNotEmpty(),
            includeWeek = all.getValue(WidgetKind.WEEK).isNotEmpty()
        ))
    }

    fun action(context: Context, id: Int, operation: String) {
        val store = store(context)
        when (kind(context, id)) {
            WidgetKind.WEEK -> {
                if (operation !in setOf("current", "previous", "next")) return
                val data = WidgetData(store.snapshot())
                val term = data.term ?: return
                val config = WidgetConfigStore(context)
                val termId = term.getString("id")
                val current = config.week(id, termId) ?: data.defaultWeek()
                val next = when (operation) {
                    "previous" -> (current - 1).coerceAtLeast(1)
                    "next" -> (current + 1).coerceAtMost(term.getInt("weeks"))
                    else -> null
                }
                config.select(id, termId, next?.takeUnless { it == data.currentWeek() })
                refresh(context, id)
            }
            else -> Unit
        }
    }

    private fun schedule(context: Context, at: Long?) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val intent = Intent(context, WidgetEvents::class.java).setAction(WidgetEvents.CLOCK)
        val pending = PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        if (at == null) alarm.cancel(pending)
        else alarm.set(AlarmManager.RTC, at, pending)
    }
}

class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = widgetListFactory(applicationContext, intent)
}

internal fun widgetListFactory(context: Context, intent: Intent): RemoteViewsService.RemoteViewsFactory {
    val uri = intent.data
    val type = WidgetKind.parse(uri?.host)
    val parts = uri?.pathSegments.orEmpty()
    val id = parts.getOrNull(0)?.toIntOrNull()
    val width = parts.getOrNull(1)?.toIntOrNull()
    val height = parts.getOrNull(2)?.toIntOrNull()
    val ownerLink = parts.getOrNull(3)
    return object : RemoteViewsService.RemoteViewsFactory {
        @Volatile private var rows = emptyList<RemoteViews>()
        @Volatile private var store: WidgetSnapshotStore? = null
        override fun onCreate() = Unit
        override fun onDataSetChanged() {
            if ((type != WidgetKind.TODAY && type != WidgetKind.EXAMS) || id == null ||
                width == null || height == null) return
            rows = WidgetUpdateManager.await(emptyList()) {
                val current = WidgetUpdateManager.store(context)
                store = current
                if (ownerLink != current.visibleLink || WidgetUpdateManager.kind(context, id) != type) emptyList()
                else WidgetRenderer(context).collectionRows(type, WidgetSize(width, height), WidgetData(current.snapshot()))
            }
        }
        override fun onDestroy() {
            rows = emptyList()
            store = null
        }
        private fun visibleRows() = if (ownerLink != null && store?.visibleLink == ownerLink) rows else emptyList()
        override fun getCount() = visibleRows().size
        override fun getViewAt(position: Int): RemoteViews? = visibleRows().getOrNull(position)
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
    }
}
