package org.neuqone.neuq_one.widgets

import android.app.Activity
import android.app.Instrumentation
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.neuqone.neuq_one.R
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.io.path.createTempDirectory

class WidgetInstrumentation : Instrumentation() {
    private var assertHost = false

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        assertHost = arguments?.getString("host") == "true"
        start()
    }

    override fun onStart() {
        val outcome = runCatching {
            snapshotLifecycle()
            timetableAndClock()
            legacyCardCleanup()
            todayCourseBoundaries()
            fusedSchedule()
            instanceOptions()
            providerRegistration()
            rendererPreviews()
            serialQueue()
            if (assertHost) hostBinding()
        }
        val report = Bundle().apply {
            putString("stream", outcome.fold(
                { "\nWidget checks passed (snapshot, timetable, exam and course clocks, sizing, launcher registration, Light/Dark RemoteViews, queue${if (assertHost) ", host binding and collection" else ""}).\n" },
                { error -> StringWriter().apply { error.printStackTrace(PrintWriter(this)) }.toString() }
            ))
        }
        finish(if (outcome.isSuccess) Activity.RESULT_OK else Activity.RESULT_CANCELED, report)
    }

    private fun snapshotLifecycle() = withTempStore { directory ->
        val first = WidgetSnapshotStore(directory)
        val owner = "a".repeat(64)
        val lease = first.confirm(owner)
        check(first.update(lease, "timetable", timetable.toString()))
        check(!first.update(lease, "timetable", timetable.toString()))
        check(runCatching { first.update(lease, "timetable", "{}") }.isFailure)
        check(first.snapshot()!!.has("timetable"))
        File(directory, "widget-snapshot.json.new").writeText("{")
        check(WidgetSnapshotStore(directory).snapshot()!!.has("timetable"))
        first.suspendVerification()
        check(first.snapshot() == null && WidgetSnapshotStore(directory).snapshot() == null)
        check(!first.update(lease, "exams", exams.toString()))
        val restored = first.confirm(owner)
        check(lease != restored && first.snapshot()!!.has("timetable"))
        val other = first.confirm("b".repeat(64))
        check(!first.snapshot()!!.has("timetable"))
        check(!first.update(restored, "exams", exams.toString()))
        check(first.update(other, "exams", exams.toString()))
        first.clear()
        check(first.snapshot() == null && WidgetSnapshotStore(directory).snapshot() == null)
        check(!first.update(other, "exams", exams.toString()))
    }

    private fun timetableAndClock() {
        val data = WidgetData(sample, now)
        check(data.today.toString() == "2026-11-30")
        check(data.currentWeek() == 14)
        check(data.courses(14, 1).map { it.getString("id") } == listOf("a", "b", "c", "d"))
        check(data.courses(13, 1).none { it.getString("id") == "b" })
        check(data.courses(14, 7).single().getInt("last") == 8)
        check(data.courses(14, 2).isEmpty())
        check(data.courses(1, 1).isEmpty())
        check(WidgetData(sample, Instant.parse("2026-08-30T16:00:00Z")).currentWeek() == null)
        check(WidgetData(sample, Instant.parse("2027-01-31T16:00:00Z")).currentWeek() == null)
        check(data.timetable!!.getJSONArray("periods").getJSONArray(11).getInt(0) == 1275)
        check(data.examStatus(data.exams.first()) == ExamStatus("3", "天"))
        val exam = data.exams.first()
        val examStart = Instant.ofEpochMilli(exam.getLong("start"))
        val examEnd = Instant.ofEpochMilli(exam.getLong("end"))
        check(WidgetData(sample, examStart.minusSeconds(86_400)).examStatus(exam).label == "明天")
        val before = WidgetData(sample, examStart.minusSeconds(60))
        check(before.examStatus(exam) == ExamStatus("今天", warning = true))
        check(before.nextUpdate(includeToday = false, includeExams = true) == examStart.toEpochMilli())
        val running = WidgetData(sample, examStart)
        check(running.examStatus(exam).label == "进行中")
        check(running.nextUpdate(includeToday = false, includeExams = true) == examEnd.toEpochMilli())
        check(WidgetData(sample, examEnd).exams.none { it.getString("id") == exam.getString("id") })
        val nextDay = WidgetData(sample, Instant.parse("2026-11-30T16:00:00Z"))
        check(nextDay.today.toString() == "2026-12-01" && nextDay.courses(14, 2).isEmpty())
    }

    private fun legacyCardCleanup() = withTempStore { folder ->
        val store = WidgetSnapshotStore(folder)
        val lease = store.confirm("c".repeat(64))
        check(store.update(lease, "timetable", timetable.toString()))
        check(store.update(lease, "exams", exams.toString()))
        val file = File(folder, "widget-snapshot.json")
        file.writeText(JSONObject(file.readText()).put("card", JSONObject().put("cents", 5340)).toString())
        val migrated = WidgetSnapshotStore(folder)
        check(migrated.snapshot()?.has("timetable") == true && migrated.snapshot()?.has("exams") == true)
        check(!JSONObject(file.readText()).has("card"))
        check(runCatching { migrated.update(lease, "card", "{}") }.isFailure)
    }

    private fun todayCourseBoundaries() {
        val before = WidgetData(sample, lastCourseEnd.minusSeconds(1))
        check(before.todayCourses.size == 4 && !before.todayCoursesEnded)
        check(before.nextUpdate(includeToday = true, includeExams = true) == lastCourseEnd.toEpochMilli())
        val finished = WidgetData(sample, lastCourseEnd)
        check(finished.todayCoursesEnded)
        val midnight = Instant.parse("2026-11-30T16:00:00Z")
        check(finished.nextUpdate(includeToday = true, includeExams = false) == midnight.toEpochMilli())
        val dayOff = WidgetData(sample, midnight)
        check(dayOff.todayCourses.isEmpty() && !dayOff.todayCoursesEnded)
        check(WidgetData(null, now).todayCourses.isEmpty())
    }

    private fun fusedSchedule() = withTempStore { directory ->
        val store = WidgetSnapshotStore(directory)
        val lease = store.confirm("e".repeat(64))
        val start = "2026-11-30T00:00:00Z"
        val end = "2026-11-30T01:40:00Z"
        val merged = exam("same-day", "考试样例", "考场 A", start, end)
            .put("conflicts", 1)
            .put("covered", JSONObject().put("2026-11-30", JSONArray(listOf("a"))))
        val colors = JSONArray(listOf(0xfffbe2df, 0xffa52d28, 0xff783934, 0xffffdad4))
        val finished = JSONArray(listOf(0xfff2e9e7, 0xff78605c, 0xff493c3b, 0xffe1c8c4))
        val examSection = JSONObject().put("items", JSONArray(listOf(merged)))
            .put("showOnTimetable", true).put("colors", colors).put("finishedColors", finished)
        val table = JSONObject(timetable.toString())
        table.getJSONArray("terms").getJSONObject(0).put("examDays",
            JSONObject().put("2026-11-30", JSONObject()
                .put("items", JSONArray(listOf(JSONObject(merged.toString())
                    .put("from", 480).put("to", 580).put("gridFrom", 0).put("gridTo", 2)
                    .put("examCount", 1).put("examEnd", Instant.parse(end).toEpochMilli()))))
                .put("supplement", true)))
        check(runCatching {
            store.updateAll(lease, mapOf("timetable" to table.toString(), "exams" to "{}"))
        }.isFailure)
        check(!store.snapshot()!!.has("timetable"))
        check(store.updateAll(lease, mapOf("timetable" to table.toString(), "exams" to examSection.toString())))
        val during = WidgetData(store.snapshot(), Instant.parse(start))
        check(during.todayCourses.map { it.getString("id") } == listOf("same-day", "b", "c", "d"))
        check(during.weekExamDay(during.today)?.optBoolean("supplement") == true)
        check(during.hasExam("same-day"))
        check(during.nextUpdate(includeToday = true, includeExams = false) == Instant.parse(end).toEpochMilli())
        val examOnly = WidgetData(JSONObject().put("exams", examSection), Instant.parse(start))
        check(!examOnly.timetableReady && examOnly.todayCourses.size == 1 && !examOnly.todayCoursesEnded)
        check(WidgetData(JSONObject().put("exams", examSection), Instant.parse(end)).todayCoursesEnded)
        check(store.update(lease, "exams", examSection.put("showOnTimetable", false).toString()))
        val disabled = WidgetData(store.snapshot(), Instant.parse(start))
        check(disabled.todayCourses.first().getString("id") == "a")
        check(disabled.weekExamDay(disabled.today) == null && disabled.exams.size == 1)

        val context = targetContext
        for (size in listOf(WidgetSize(150, 152), WidgetSize(304, 152))) {
            val views = WidgetRenderer(context).render(WidgetKind.TODAY, 0, size, during, null, null, preview = true)
            runOnMainSync {
                val view = views.apply(context, FrameLayout(context))
                check(view.findViewById<TextView>(R.id.widget_course_badge).text == "⚠ 考试")
                val image = WidgetPreview.draw(context, views, size)
                check(image.width > 0 && image.height > 0)
                image.recycle()
            }
        }
        for (size in listOf(WidgetSize(304, 380), WidgetSize(304, 456))) {
            val views = WidgetRenderer(context).render(WidgetKind.WEEK, 0, size, during, null, null, preview = true)
            runOnMainSync {
                val view = views.apply(context, FrameLayout(context))
                check(view.findViewById<TextView>(R.id.widget_day_name).text == "周一·")
                val image = WidgetPreview.draw(context, views, size)
                check(image.width > 0 && image.height > 0)
                image.recycle()
            }
        }
    }

    private fun instanceOptions() {
        val two = WidgetSize(150, 152)
        val four = WidgetSize(304, 152)
        check(WidgetSizePolicy.list(WidgetKind.TODAY, two, 1f).rows == 2)
        check(WidgetSizePolicy.list(WidgetKind.TODAY, four, 1f).rows == 3)
        check(WidgetSizePolicy.list(WidgetKind.EXAMS, four, 1f).rows == 2)
        check(WidgetSizePolicy.list(WidgetKind.TODAY, WidgetSize(140, 126), 1.4f).rows == 1)
        check(!WidgetSizePolicy.weekFits(WidgetSize(304, 320)))
        check(WidgetSizePolicy.weekFits(WidgetSize(304, 380)))
        val legacy = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 150)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 304)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 72)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 152)
        }
        check(WidgetSizePolicy.choices(legacy, WidgetKind.TODAY.defaultSize) == listOf(two, WidgetSize(304, 72)))
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            legacy.putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf(SizeF(304f, 152f)))
            check(WidgetSizePolicy.choices(legacy, WidgetKind.TODAY.defaultSize) == listOf(four))
        }
        val configs = WidgetConfigStore(targetContext)
        val a = 820_001
        val b = 820_002
        try {
            configs.select(a, "term", 9)
            configs.select(b, "term", 3)
            configs.resize(a, two)
            configs.resize(b, four)
            check(configs.week(a, "term") == 9 && configs.week(b, "term") == 3)
            check(configs.week(a, "new") == null)
            configs.delete(a)
            check(configs.size(a) == null && configs.week(a, "term") == null)
            check(configs.size(b) == four && configs.week(b, "term") == 3)
        } finally {
            configs.delete(a)
            configs.delete(b)
        }
    }

    private fun providerRegistration() {
        val manager = AppWidgetManager.getInstance(targetContext)
        val providers = manager.installedProviders.filter { it.provider.packageName == targetContext.packageName }
        check(providers.map { it.provider }.toSet() == WidgetKind.entries.map { WidgetUpdateManager.component(targetContext, it) }.toSet())
    }

    private fun rendererPreviews() {
        val output = File(targetContext.filesDir, "widget-test-previews").apply { mkdirs() }
        val configurations = listOf("light" to Configuration.UI_MODE_NIGHT_NO, "dark" to Configuration.UI_MODE_NIGHT_YES)
        val layouts = listOf(
            Triple("today-2x2", WidgetKind.TODAY, WidgetSize(150, 152)),
            Triple("today-4x2", WidgetKind.TODAY, WidgetSize(304, 152)),
            Triple("week-4x5", WidgetKind.WEEK, WidgetSize(304, 380)),
            Triple("week-4x6", WidgetKind.WEEK, WidgetSize(304, 456)),
            Triple("exams-2x1", WidgetKind.EXAMS, WidgetSize(150, 72)),
            Triple("exams-2x2", WidgetKind.EXAMS, WidgetSize(150, 152)),
            Triple("exams-4x2", WidgetKind.EXAMS, WidgetSize(304, 152)),
            Triple("today-free-2x2", WidgetKind.TODAY, WidgetSize(150, 152)),
            Triple("today-free-4x2", WidgetKind.TODAY, WidgetSize(304, 152)),
            Triple("today-done-2x2", WidgetKind.TODAY, WidgetSize(150, 152)),
            Triple("today-done-4x2", WidgetKind.TODAY, WidgetSize(304, 152))
        )
        for ((theme, mode) in configurations) {
            val context = targetContext.createConfigurationContext(Configuration(targetContext.resources.configuration).apply {
                uiMode = uiMode and Configuration.UI_MODE_NIGHT_MASK.inv() or mode
                fontScale = 1f
            })
            for ((label, kind, size) in layouts) {
                val instant = when {
                    label.startsWith("today-free") -> Instant.parse("2026-12-01T02:00:00Z")
                    label.startsWith("today-done") -> lastCourseEnd
                    else -> now
                }
                val data = WidgetData(sample, instant)
                val views = WidgetRenderer(context).render(kind, 0, size, data, null, null, preview = true)
                var bitmap: Bitmap? = null
                var error: Throwable? = null
                runOnMainSync {
                    runCatching {
                        val expected = when {
                            label.startsWith("today-free") -> "今日无课" to "好好享受今天"
                            label.startsWith("today-done") -> "今日日程已结束" to "今天辛苦了"
                            else -> null
                        }
                        if (expected != null) {
                            val view = views.apply(context, FrameLayout(context))
                            check(view.findViewById<TextView>(R.id.widget_empty_title).text == expected.first)
                            check(view.findViewById<TextView>(R.id.widget_empty_hint).text == expected.second)
                            check(view.findViewById<View>(R.id.widget_today_status_icon).visibility == View.VISIBLE)
                            check(view.findViewById<View>(R.id.widget_list).visibility == View.GONE)
                        }
                        WidgetPreview.draw(context, views, size)
                    }
                        .onSuccess { bitmap = it }.onFailure { error = it }
                }
                error?.let { throw IllegalStateException("$theme/$label", it) }
                val image = checkNotNull(bitmap)
                try {
                    check(image.getPixel(image.width / 2, 4) == context.getColor(R.color.widget_surface))
                    File(output, "$theme-$label.png").outputStream().use { check(image.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                } finally {
                    image.recycle()
                }
            }
        }
    }

    private fun serialQueue() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        WidgetUpdateManager.submit {
            entered.countDown()
            release.await(4, TimeUnit.SECONDS)
        }
        check(entered.await(1, TimeUnit.SECONDS))
        var ran = false
        try {
            check(!WidgetUpdateManager.await(false) { ran = true; true })
        } finally {
            release.countDown()
        }
        check(WidgetUpdateManager.await(false) { !ran })
    }

    private fun hostBinding() {
        val context = targetContext
        check(!File(context.noBackupFilesDir, "widget-snapshot.json").exists()) {
            "Host binding uses a disposable app installation."
        }
        val manager = AppWidgetManager.getInstance(context)
        val host = AppWidgetHost(context, 215)
        val id = host.allocateAppWidgetId()
        try {
            check(WidgetUpdateManager.await(false) {
                val widgetNow = campusDay(Instant.now())
                val todayTable = JSONObject(timetable.toString())
                val term = todayTable.getJSONArray("terms").getJSONObject(0)
                term.put("start", widgetNow.toString())
                term.getJSONArray("courses").objects().forEach { course ->
                    course.put("day", widgetNow.dayOfWeek.value).put("weeks", JSONArray(listOf(1)))
                    if (course.getString("id") == "d") course.put("to", 1439)
                }
                val store = WidgetUpdateManager.store(context)
                val lease = store.confirm("d".repeat(64))
                store.update(lease, "timetable", todayTable.toString())
            })
            check(manager.bindAppWidgetIdIfAllowed(id, WidgetUpdateManager.component(context, WidgetKind.TODAY)))
            val options = Bundle().apply {
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 150)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 150)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 152)
                putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 152)
            }
            manager.updateAppWidgetOptions(id, options)
            val contextLink = WidgetUpdateManager.await<String?>(null) { WidgetUpdateManager.store(context).link() }
            val open = Intent("org.neuqone.neuq_one.widget.OPEN", Uri.parse("neuq-widget://open/$id/$contextLink/course"))
                .putExtra(WidgetNavigation.COURSE_ID, "a")
            val parsed = WidgetUpdateManager.await<WidgetNavigation.Link?>(null) {
                WidgetNavigation.read(context, open, WidgetUpdateManager.store(context))
            }
            check(parsed?.course == "a")
            val forged = open.setData(Uri.parse("neuq-widget://open/$id/$contextLink/card"))
            check(WidgetUpdateManager.await<WidgetNavigation.Link?>(null) {
                WidgetNavigation.read(context, forged, WidgetUpdateManager.store(context))
            } == null)
            val adapter = Intent().setData(Uri.parse("neuq-widget-list://today/$id/150/152/$contextLink"))
            val factory = widgetListFactory(context, adapter)
            factory.onDataSetChanged()
            if (Instant.now().atOffset(campusZone).toLocalTime().hour != 23 ||
                Instant.now().atOffset(campusZone).toLocalTime().minute != 59) {
                check(factory.count == 8 && factory.getViewAt(2) != null)
            }
            check(WidgetUpdateManager.await(false) {
                WidgetUpdateManager.refresh(context)
                WidgetUpdateManager.store(context).suspendVerification()
                true
            })
            check(factory.count == 0 && factory.getViewAt(0) == null)
            factory.onDestroy()
        } finally {
            host.deleteAppWidgetId(id)
            WidgetUpdateManager.await(Unit) {
                WidgetUpdateManager.store(context).clear()
                WidgetUpdateManager.refresh(context)
            }
        }
        check(manager.getAppWidgetInfo(id) == null)
    }

    private inline fun withTempStore(block: (File) -> Unit) {
        val directory = createTempDirectory(targetContext.cacheDir.toPath(), "widget-check-").toFile()
        try { block(directory) } finally { directory.deleteRecursively() }
    }

    companion object {
        private val now = Instant.parse("2026-11-30T02:00:00Z")
        private val lastCourseEnd = Instant.parse("2026-11-30T12:15:00Z")
        private val palette = listOf(
            longArrayOf(0xffb6cdff, 0xff204696, 0xff3459ce, 0xffe4ecff),
            longArrayOf(0xffddc6fa, 0xff69419f, 0xff6d509d, 0xfff0e7ff),
            longArrayOf(0xffb5e5d2, 0xff216c51, 0xff235e50, 0xffc8f3e2),
            longArrayOf(0xffffda9d, 0xff75470f, 0xff775428, 0xffffe5bb),
            longArrayOf(0xffbae4ef, 0xff236c84, 0xff245a71, 0xffc6eefa)
        )
        private val periods = listOf(
            480 to 525, 530 to 575, 605 to 650, 655 to 700, 840 to 885, 890 to 935,
            965 to 1010, 1015 to 1060, 1120 to 1165, 1170 to 1215, 1225 to 1270, 1275 to 1320
        )
        private fun course(id: String, name: String, room: String, day: Int, first: Int, last: Int, color: Int, weeks: List<Int> = (1..18).toList()) =
            JSONObject().put("id", id).put("name", name).put("room", room).put("day", day).put("first", first - 1).put("last", last)
                .put("from", periods[first - 1].first).put("to", periods[last - 1].second).put("weeks", JSONArray(weeks))
                .put("colors", JSONArray(palette[color].toList()))
        private val timetable = JSONObject()
            .put("periods", JSONArray(periods.map { JSONArray(listOf(it.first, it.second)) }))
            .put("terms", JSONArray(listOf(JSONObject().put("id", "term").put("weeks", 18).put("start", "2026-09-02").put("courses", JSONArray(listOf(
                course("a", "数据结构", "实验楼 301", 1, 1, 2, 1),
                course("b", "计算机网络", "信息楼 205", 1, 3, 4, 0, (2..18 step 2).toList()),
                course("c", "编译技术", "教学楼 204", 1, 5, 6, 2),
                course("d", "离散数学", "教学楼 202", 1, 9, 10, 3),
                course("e", "软件设计", "实验楼 315", 3, 1, 2, 1),
                course("f", "计算机组成", "信息楼 231", 4, 3, 6, 4),
                course("g", "数据库系统", "教学楼 105", 5, 5, 6, 1),
                course("h", "数学建模", "实验楼 118", 7, 5, 8, 3),
            ))))))
        private fun exam(id: String, name: String, room: String, start: String, end: String) =
            JSONObject().put("id", id).put("name", name).put("room", room)
                .put("start", Instant.parse(start).toEpochMilli()).put("end", Instant.parse(end).toEpochMilli())
        private val exams = JSONObject().put("items", JSONArray(listOf(
            exam("e1", "数据结构", "实验楼 301", "2026-12-03T01:00:00Z", "2026-12-03T03:00:00Z"),
            exam("e2", "计算机组成", "信息楼 231", "2026-12-06T06:00:00Z", "2026-12-06T08:00:00Z"),
            exam("e3", "数学建模", "实验楼 118", "2026-12-08T06:00:00Z", "2026-12-08T08:00:00Z"),
        )))
        private val sample = JSONObject().put("timetable", timetable).put("exams", exams)
    }
}
