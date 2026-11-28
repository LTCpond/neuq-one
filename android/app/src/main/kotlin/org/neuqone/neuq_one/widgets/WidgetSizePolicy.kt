package org.neuqone.neuq_one.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import kotlin.math.roundToInt

internal enum class WidgetKind(val key: String) {
    TODAY("today"), WEEK("week"), EXAMS("exams");

    val defaultSize: WidgetSize get() = when (this) {
        TODAY -> WidgetSize(150, 148)
        WEEK -> WidgetSize(300, 380)
        EXAMS -> WidgetSize(150, 72)
    }

    companion object {
        fun parse(value: String?) = entries.firstOrNull { it.key == value }
    }
}

internal data class WidgetSize(val width: Int, val height: Int) {
    val usableHeight get() = height.coerceAtMost(720)
}

internal data class WidgetListSize(val rows: Int, val rowHeight: Int)

internal object WidgetSizePolicy {
    const val LIST_VERTICAL_INSETS = 36

    fun wide(size: WidgetSize) = size.width >= 250
    fun tall(size: WidgetSize) = size.height >= 110
    fun weekFits(size: WidgetSize) = size.width >= 238 && size.height >= 350

    fun list(kind: WidgetKind, size: WidgetSize, fontScale: Float): WidgetListSize {
        val wide = wide(size)
        val available = (size.usableHeight - LIST_VERTICAL_INSETS).coerceAtLeast(1)
        val desired = if (kind == WidgetKind.TODAY && wide) 3 else 2
        val minimum = ((if (kind == WidgetKind.TODAY && wide) 31 else 45) *
            fontScale.coerceIn(1f, 1.35f)).roundToInt()
        val rows = (available / minimum).coerceIn(1, desired)
        return WidgetListSize(rows, available / rows)
    }

    fun choices(options: Bundle, fallback: WidgetSize): List<WidgetSize> {
        if (Build.VERSION.SDK_INT >= 31) {
            @Suppress("DEPRECATION")
            val sizes = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!sizes.isNullOrEmpty()) return sizes.asSequence()
                .filter { it.width.isFinite() && it.height.isFinite() && it.width >= 1 && it.height >= 1 }
                .map { WidgetSize(it.width.roundToInt(), it.height.roundToInt()) }
                .distinct().take(4).toList().ifEmpty { listOf(fallback) }
        }
        fun option(key: String, default: Int) = options.getInt(key).takeIf { it > 0 } ?: default
        val minWidth = option(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, fallback.width)
        val minHeight = option(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, fallback.height)
        val maxWidth = option(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth).coerceAtLeast(minWidth)
        val maxHeight = option(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight).coerceAtLeast(minHeight)
        return listOf(WidgetSize(minWidth, maxHeight), WidgetSize(maxWidth, minHeight)).distinct()
    }

    fun current(context: Context, choices: List<WidgetSize>): WidgetSize =
        if (context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE)
            choices.last() else choices.first()
}

internal class WidgetConfigStore(context: Context) {
    private val prefs = context.getSharedPreferences("desktop-widget-instances", Context.MODE_PRIVATE)

    fun week(id: Int, term: String): Int? = prefs.getInt("$id/week", 0)
        .takeIf { it > 0 && prefs.getString("$id/term", null) == term }

    fun select(id: Int, term: String, week: Int?) {
        prefs.edit().apply {
            if (week == null) remove("$id/week").remove("$id/term")
            else putString("$id/term", term).putInt("$id/week", week)
        }.apply()
    }

    fun size(id: Int): WidgetSize? {
        val width = prefs.getInt("$id/width", 0)
        val height = prefs.getInt("$id/height", 0)
        return WidgetSize(width, height).takeIf { width > 0 && height > 0 }
    }

    fun resize(id: Int, size: WidgetSize) {
        if (size(id) != size) prefs.edit().putInt("$id/width", size.width).putInt("$id/height", size.height).apply()
    }

    fun delete(id: Int) {
        prefs.edit().remove("$id/week").remove("$id/term").remove("$id/width").remove("$id/height").apply()
    }

    fun resetSelections() {
        prefs.edit().apply {
            prefs.all.keys.filter { it.endsWith("/week") || it.endsWith("/term") }.forEach(::remove)
        }.apply()
    }
}
