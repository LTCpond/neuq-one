package org.neuqone.neuq_one.widgets

import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import org.neuqone.neuq_one.R
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

internal class WidgetAppearance(private val context: Context) {
    val dark = context.resources.configuration.uiMode and 0x30 == 0x20
    val fontScale = context.resources.configuration.fontScale
    fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).roundToInt()
    fun color(resource: Int) = context.getColor(resource)
}

internal class WidgetRenderer(private val context: Context) {
    private val look = WidgetAppearance(context)

    fun render(
        kind: WidgetKind, id: Int, size: WidgetSize, data: WidgetData,
        selectedWeek: Int?, link: String?, preview: Boolean = false
    ): RemoteViews = when (kind) {
        WidgetKind.TODAY -> today(id, size, data, link, preview)
        WidgetKind.WEEK -> week(id, size, data, selectedWeek, link)
        WidgetKind.EXAMS -> exams(id, size, data, link, preview)
    }

    private fun views(layout: Int) = RemoteViews(context.packageName, layout)

    private fun today(id: Int, size: WidgetSize, data: WidgetData, link: String?, preview: Boolean): RemoteViews {
        val teachingWeek = data.currentWeek()
        val day = data.today.dayOfWeek.value
        val wide = WidgetSizePolicy.wide(size)
        val courses = data.todayCourses
        val geometry = WidgetSizePolicy.list(WidgetKind.TODAY, size, look.fontScale)
        return views(R.layout.widget_today_list).apply {
            listInsets()
            val weekday = weekday(day)
            text(R.id.widget_trail, if (wide && teachingWeek != null) "第${teachingWeek}周 · $weekday" else weekday)
            open(R.id.widget_header, id, link, WidgetNavigation.TIMETABLE)
            if (courses.isEmpty() || data.todayCoursesEnded) {
                when {
                    data.term == null -> todayStatus("暂无课表", "点击打开课表", 0)
                    data.todayCoursesEnded -> todayStatus("今日课程已结束", "今天辛苦了", R.drawable.widget_day_done)
                    else -> todayStatus("今日无课", "好好享受今天", R.drawable.widget_day_free)
                }
                open(R.id.widget_empty, id, link, WidgetNavigation.TIMETABLE)
            } else {
                collection(WidgetKind.TODAY, id, size, geometry, courses.size, link, preview) { index ->
                    courseRow(courses[index], wide, geometry.rowHeight, id, link, preview || courses.size <= geometry.rows)
                }
            }
        }
    }

    internal fun collectionRows(kind: WidgetKind, size: WidgetSize, data: WidgetData): List<RemoteViews> {
        val height = WidgetSizePolicy.list(kind, size, look.fontScale).rowHeight
        return when (kind) {
            WidgetKind.TODAY -> if (data.todayCoursesEnded) emptyList() else data.todayCourses
                .map { courseRow(it, WidgetSizePolicy.wide(size), height, 0, null, false) }
            WidgetKind.EXAMS -> data.exams.map { examRow(it, data, R.layout.widget_exam_wide, height, fillIn = true) }
            else -> emptyList()
        }
    }

    private fun courseRow(course: JSONObject, wide: Boolean, height: Int, id: Int, link: String?, direct: Boolean) =
        views(if (wide) R.layout.widget_course_wide else R.layout.widget_course_small).apply {
            setInt(R.id.widget_row_height, "setHeight", look.dp(height))
            text(R.id.widget_course_name, course.getString("name"))
            text(R.id.widget_course_room, course.getString("room").ifBlank { "地点待定" })
            text(R.id.widget_course_time, "${clock(course.getInt("from"))}–${clock(course.getInt("to"))}")
            val colors = course.getJSONArray("colors")
            themedColor(R.id.widget_course_stripe, "setColorFilter", colors.getLong(0).toInt(), colors.getLong(2).toInt())
            val courseId = course.getString("id")
            if (direct) open(R.id.widget_row_click, id, link, WidgetNavigation.COURSE, courseId)
            else setOnClickFillInIntent(R.id.widget_row_click, Intent().putExtra(WidgetNavigation.COURSE_ID, courseId))
        }

    private fun exams(id: Int, size: WidgetSize, data: WidgetData, link: String?, preview: Boolean): RemoteViews {
        val first = data.exams.firstOrNull()
        val wide = WidgetSizePolicy.wide(size) && WidgetSizePolicy.tall(size)
        if (!wide) {
            if (first == null) return views(R.layout.widget_exam_empty).apply {
                text(R.id.widget_empty_title, "暂无考试")
                text(R.id.widget_empty_hint, "点击添加考试")
                open(R.id.widget_root, id, link, WidgetNavigation.ADD_EXAM)
            }
            val layout = if (WidgetSizePolicy.tall(size)) R.layout.widget_exam_square else R.layout.widget_exam_small
            return examRow(first, data, layout).apply { open(R.id.widget_root, id, link, WidgetNavigation.EXAMS) }
        }
        return views(R.layout.widget_exams_list).apply {
            listInsets()
            open(R.id.widget_header, id, link, WidgetNavigation.EXAMS)
            if (first == null) {
                empty("暂无考试", "点击添加考试")
                open(R.id.widget_empty, id, link, WidgetNavigation.ADD_EXAM)
            } else {
                val geometry = WidgetSizePolicy.list(WidgetKind.EXAMS, size, look.fontScale)
                collection(WidgetKind.EXAMS, id, size, geometry, data.exams.size, link, preview) { index ->
                    examRow(data.exams[index], data, R.layout.widget_exam_wide, geometry.rowHeight).apply {
                        if (preview || data.exams.size <= geometry.rows) {
                            open(R.id.widget_row_click, id, link, WidgetNavigation.EXAMS)
                        }
                    }
                }
            }
        }
    }

    private fun examRow(exam: JSONObject, data: WidgetData, layout: Int, height: Int = 0, fillIn: Boolean = false) = views(layout).apply {
        if (height > 0) {
            setInt(R.id.widget_row_height, "setHeight", look.dp(height))
        }
        if (fillIn) setOnClickFillInIntent(R.id.widget_row_click, Intent())
        val status = data.examStatus(exam)
        text(R.id.widget_count, status.label)
        text(R.id.widget_unit, status.unit)
        setViewVisibility(R.id.widget_unit, if (status.unit.isEmpty()) View.GONE else View.VISIBLE)
        val square = layout == R.layout.widget_exam_square
        val numberSize = when {
            status.unit.isEmpty() -> if (square) 27f else 16f
            status.label.length >= 4 -> if (square) 29f else 17f
            status.label.length == 3 -> if (square) 34f else 22f
            square -> 38f
            else -> 28f
        }
        setTextViewTextSize(R.id.widget_count, TypedValue.COMPLEX_UNIT_SP, numberSize)
        colorResource(R.id.widget_count, "setTextColor", if (status.warning) R.color.widget_warning else R.color.widget_brand)
        val start = Instant.ofEpochMilli(exam.getLong("start")).atOffset(campusZone)
        val end = Instant.ofEpochMilli(exam.getLong("end")).atOffset(campusZone)
        val date = start.format(if (layout == R.layout.widget_exam_square) chineseDate else dottedDate)
        val startTime = start.format(time)
        val endDay = if (start.toLocalDate() == end.toLocalDate()) "" else "${end.format(dottedDate)} "
        val whenLabel = if (layout == R.layout.widget_exam_small && start.toLocalDate() != data.today) {
            "$date $startTime"
        } else {
            val prefix = if (layout == R.layout.widget_exam_small) "" else "$date "
            "$prefix$startTime–$endDay${end.format(time)}"
        }
        text(R.id.widget_exam_name, exam.getString("name"))
        text(R.id.widget_exam_time, whenLabel)
        text(R.id.widget_exam_room, exam.getString("room").ifBlank { "地点待定" })
    }

    private fun RemoteViews.collection(
        kind: WidgetKind, id: Int, size: WidgetSize, geometry: WidgetListSize, count: Int,
        link: String?, preview: Boolean, row: (Int) -> RemoteViews
    ) {
        setViewVisibility(R.id.widget_empty, View.GONE)
        if (preview || count <= geometry.rows) {
            setViewVisibility(R.id.widget_list, View.GONE)
            setViewVisibility(R.id.widget_static, View.VISIBLE)
            removeAllViews(R.id.widget_static)
            repeat(minOf(count, geometry.rows)) { addView(R.id.widget_static, row(it)) }
        } else {
            setViewVisibility(R.id.widget_list, View.VISIBLE)
            setViewVisibility(R.id.widget_static, View.GONE)
            removeAllViews(R.id.widget_static)
            // Keep the viewport a multiple of the item height. ListView is free to
            // stop between rows after a user's drag on launchers without snapping.
            val remainder = look.dp(size.usableHeight) - look.dp(20) - 2 * look.dp(8) -
                look.dp(geometry.rowHeight) * geometry.rows
            listInsets(remainder.coerceAtLeast(0))
            val adapter = Intent(context, WidgetListService::class.java)
                .setData(Uri.Builder().scheme("neuq-widget-list").authority(kind.key)
                    .appendPath(id.toString()).appendPath(size.width.toString()).appendPath(size.height.toString())
                    .appendPath(link ?: "none").build())
            @Suppress("DEPRECATION")
            setRemoteAdapter(R.id.widget_list, adapter)
            val target = if (kind == WidgetKind.TODAY) WidgetNavigation.COURSE else WidgetNavigation.EXAMS
            setPendingIntentTemplate(R.id.widget_list, WidgetNavigation.open(context, id, link, target, collection = true))
        }
    }

    private fun RemoteViews.listInsets(extraBottom: Int = 0) =
        setViewPadding(R.id.widget_root, look.dp(10), look.dp(8), look.dp(10), look.dp(8) + extraBottom)

    private fun week(id: Int, size: WidgetSize, data: WidgetData, selected: Int?, link: String?): RemoteViews =
        views(R.layout.widget_week).apply {
            val term = data.term
            val week = selected?.coerceIn(1, term?.getInt("weeks") ?: 1) ?: data.defaultWeek()
            text(R.id.widget_week_title, if (term == null) "周课表" else "第 $week 周")
            val fits = WidgetSizePolicy.weekFits(size)
            if (term == null || !fits) {
                setViewVisibility(R.id.widget_days, View.GONE)
                setViewVisibility(R.id.widget_week_grid, View.GONE)
                setViewVisibility(R.id.widget_previous, View.GONE)
                setViewVisibility(R.id.widget_next, View.GONE)
                text(R.id.widget_week_range, "")
                empty(if (!fits) "请拉高周课表" else "暂无课表", if (!fits) "周课表需要至少 4×5 的空间" else "点击打开课表")
                open(R.id.widget_week_reset, id, link, WidgetNavigation.TIMETABLE)
                open(R.id.widget_empty, id, link, WidgetNavigation.TIMETABLE)
                return@apply
            }

            val monday = with(data) { term.monday() }.plusWeeks(week - 1L)
            setViewVisibility(R.id.widget_empty, View.GONE)
            setViewVisibility(R.id.widget_days, View.VISIBLE)
            setViewVisibility(R.id.widget_week_grid, View.VISIBLE)
            setViewVisibility(R.id.widget_previous, View.VISIBLE)
            setViewVisibility(R.id.widget_next, View.VISIBLE)
            text(R.id.widget_week_range, "${monday.format(chineseDate)} – ${monday.plusDays(6).format(chineseDate)}")
            arrow(R.id.widget_previous, id, week > 1, "previous")
            arrow(R.id.widget_next, id, week < term.getInt("weeks"), "next")
            if (id > 0) {
                setContentDescription(R.id.widget_week_reset, "第 $week 周，点击返回当前教学周")
                setOnClickPendingIntent(R.id.widget_week_reset, WidgetNavigation.action(context, id, "current"))
            }

            removeAllViews(R.id.widget_days)
            removeAllViews(R.id.widget_week_grid)
            addView(R.id.widget_days, views(R.layout.widget_week_month).apply { text(R.id.widget_month, "${monday.monthValue}月") })
            val periods = data.timetable!!.getJSONArray("periods")
            addView(R.id.widget_week_grid, views(R.layout.widget_week_periods).apply {
                repeat(12) { index ->
                    addView(R.id.widget_periods, views(R.layout.widget_week_period).apply {
                        text(R.id.widget_period_number, (index + 1).toString())
                        text(R.id.widget_period_time, clock(periods.getJSONArray(index).getInt(0)))
                    })
                }
            })
            val height = size.height.coerceAtMost(720) - 120
            val columnWidth = (size.width - 48) / 7
            for (day in 1..7) {
                val date = monday.plusDays(day - 1L)
                val today = date == data.today
                addView(R.id.widget_days, weekDay(date, today))
                addView(R.id.widget_week_grid, weekColumn(data.courses(week, day), height, columnWidth, today, id, link))
            }
        }

    private fun weekDay(date: LocalDate, today: Boolean) = views(R.layout.widget_week_day).apply {
        text(R.id.widget_day_name, weekday(date.dayOfWeek.value))
        text(R.id.widget_day_number, date.dayOfMonth.toString())
        if (today) {
            highlight()
            colorResource(R.id.widget_day_name, "setTextColor", R.color.widget_brand)
            setInt(R.id.widget_day_number, "setBackgroundResource", R.drawable.widget_date_badge)
            colorResource(R.id.widget_day_number, "setTextColor", R.color.widget_on_brand)
        }
        setContentDescription(R.id.widget_column, "${date.format(chineseDate)} ${weekday(date.dayOfWeek.value)}${if (today) "，今天" else ""}")
    }

    private fun weekColumn(courses: List<JSONObject>, height: Int, width: Int, today: Boolean, id: Int, link: String?) =
        views(R.layout.widget_week_column).apply {
            if (today) highlight()
            repeat(12) { addView(R.id.widget_periods, views(R.layout.widget_week_cell)) }
            for (block in placeBlocks(courses)) {
                val course = block.course
                val left = width * block.lane / block.lanes + 1
                val right = width - width * (block.lane + 1) / block.lanes + 1
                val top = height * course.getInt("first") / 12 + 1
                val bottom = height - height * course.getInt("last") / 12 + 1
                addView(R.id.widget_courses, views(R.layout.widget_week_course).apply {
                    setViewPadding(R.id.widget_course_position, look.dp(left), look.dp(top), look.dp(right), look.dp(bottom))
                    val palette = course.getJSONArray("colors")
                    themedColor(R.id.widget_course_background, "setColorFilter", palette.getLong(0).toInt(), palette.getLong(2).toInt())
                    for (view in listOf(R.id.widget_course_name, R.id.widget_course_room)) {
                        themedColor(view, "setTextColor", palette.getLong(1).toInt(), palette.getLong(3).toInt())
                    }
                    val name = course.getString("name")
                    val room = course.getString("room")
                    val contentWidth = look.dp(width) - look.dp(left) - look.dp(right) - 2 * look.dp(1)
                    val contentHeight = look.dp(height) - look.dp(top) - look.dp(bottom) - look.dp(3)
                    val subjectText = measureBlockText(name, 10f, true, contentWidth)
                    val roomText = room.takeIf { it.isNotBlank() }?.let { measureBlockText(it, 9f, false, contentWidth) }
                    val reservedRoomHeight = roomText?.getLineBottom(0) ?: 0
                    val nameLines = fullLines(subjectText, contentHeight - reservedRoomHeight).coerceAtLeast(1)
                    val roomLines = roomText?.let {
                        fullLines(it, contentHeight - subjectText.getLineBottom(nameLines - 1))
                    } ?: 0
                    setInt(R.id.widget_course_name, "setMaxLines", nameLines)
                    if (roomLines > 0) setInt(R.id.widget_course_room, "setMaxLines", roomLines)
                    else setViewVisibility(R.id.widget_course_room, View.GONE)
                    text(R.id.widget_course_name, name)
                    text(R.id.widget_course_room, room)
                    setContentDescription(R.id.widget_week_course_click, listOf(name, room,
                        "${clock(course.getInt("from"))}–${clock(course.getInt("to"))}").filter { it.isNotBlank() }.joinToString("，"))
                    open(R.id.widget_week_course_click, id, link, WidgetNavigation.COURSE, course.getString("id"))
                })
            }
        }

    private fun measureBlockText(value: String, sp: Float, bold: Boolean, width: Int): StaticLayout {
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, context.resources.displayMetrics)
            typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        return StaticLayout.Builder.obtain(value, 0, value.length, paint, width.coerceAtLeast(1))
            .setIncludePad(false)
            .setBreakStrategy(Layout.BREAK_STRATEGY_SIMPLE)
            .build()
    }

    private fun fullLines(layout: StaticLayout, height: Int): Int =
        (0 until minOf(layout.lineCount, 3)).count { layout.getLineBottom(it) <= height }

    private fun RemoteViews.highlight() = colorResource(R.id.widget_column, "setBackgroundColor", R.color.widget_highlight)

    private fun RemoteViews.themedColor(view: Int, method: String, light: Int, dark: Int) {
        if (Build.VERSION.SDK_INT >= 31) setColorInt(view, method, light, dark)
        else setInt(view, method, if (look.dark) dark else light)
    }

    private fun RemoteViews.colorResource(view: Int, method: String, resource: Int) {
        if (Build.VERSION.SDK_INT >= 31) setColor(view, method, resource)
        else setInt(view, method, look.color(resource))
    }

    private fun RemoteViews.arrow(view: Int, id: Int, enabled: Boolean, action: String) {
        setInt(view, "setImageAlpha", if (enabled) 255 else 80)
        if (enabled && id > 0) setOnClickPendingIntent(view, WidgetNavigation.action(context, id, action))
        else setOnClickPendingIntent(view, null)
    }

    private fun RemoteViews.empty(title: String, hint: String) {
        setViewVisibility(R.id.widget_empty, View.VISIBLE)
        setViewVisibility(R.id.widget_list, View.GONE)
        setViewVisibility(R.id.widget_static, View.GONE)
        text(R.id.widget_empty_title, title)
        text(R.id.widget_empty_hint, hint)
    }

    private fun RemoteViews.todayStatus(title: String, hint: String, icon: Int) {
        empty(title, hint)
        setImageViewResource(R.id.widget_today_status_icon, icon)
        setViewVisibility(R.id.widget_today_status_icon, if (icon == 0) View.GONE else View.VISIBLE)
    }

    private fun RemoteViews.text(view: Int, value: CharSequence) = setTextViewText(view, value)

    private fun RemoteViews.open(view: Int, id: Int, link: String?, target: String, course: String? = null) {
        if (id > 0) setOnClickPendingIntent(view, WidgetNavigation.open(context, id, link, target, course))
    }

    private fun weekday(day: Int) = "周${"一二三四五六日"[day - 1]}"

    companion object {
        private val time = DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT)
        private val dottedDate = DateTimeFormatter.ofPattern("MM.dd", Locale.ROOT)
        private val chineseDate = DateTimeFormatter.ofPattern("M月d日", Locale.CHINA)
        private fun clock(minute: Int) = "%02d:%02d".format(Locale.ROOT, minute / 60, minute % 60)
    }
}

internal data class CourseBlock(val course: JSONObject, val lane: Int, val lanes: Int)

internal fun placeBlocks(courses: List<JSONObject>): List<CourseBlock> {
    val result = mutableListOf<CourseBlock>()
    val group = mutableListOf<Pair<JSONObject, Int>>()
    val ends = mutableListOf<Int>()
    fun flush() {
        group.forEach { (course, lane) -> result.add(CourseBlock(course, lane, ends.size)) }
        group.clear()
        ends.clear()
    }
    for (course in courses.sortedBy { it.getInt("first") }) {
        val first = course.getInt("first")
        if (ends.all { it <= first }) flush()
        val lane = ends.indexOfFirst { it <= first }.let { if (it < 0) ends.size else it }
        val end = course.getInt("last")
        if (lane == ends.size) ends.add(end) else ends[lane] = end
        group.add(course to lane)
    }
    flush()
    return result
}
