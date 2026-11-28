package org.neuqone.neuq_one.widgets

import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.UUID

internal val campusZone: ZoneOffset = ZoneOffset.ofHours(8)
internal fun campusDay(now: Instant): LocalDate = now.atOffset(campusZone).toLocalDate()

internal class WidgetSnapshotStore(directory: File) {
    private val file = AtomicFile(File(directory, "widget-snapshot.json"))

    // All callers use WidgetUpdateManager's serial executor, including collection reads.
    private var state: JSONObject = read()
    @Volatile
    var visibleLink: String? = state.takeIf { it.optBoolean("verified") }?.optString("link")
        private set

    init {
        // Remove the balance from snapshots left by earlier development builds.
        if (state.has("card")) {
            val migrated = copy().apply { remove("card") }
            runCatching { save(migrated) }.onFailure {
                // Keep schedules available in this process and retry the cleanup next time.
                state = migrated
            }
        }
    }

    private fun read(): JSONObject = runCatching {
        val bytes = file.readFully()
        require(bytes.size <= MAX_BYTES)
        JSONObject(bytes.toString(Charsets.UTF_8)).also {
            require(it.getInt("version") == VERSION)
            require(it.optString("owner").isEmpty() || ownerPattern.matches(it.getString("owner")))
            require(it.optString("lease").isEmpty() || tokenPattern.matches(it.getString("lease")))
            require(it.optString("link").isEmpty() || tokenPattern.matches(it.getString("link")))
            it.sections().forEach { key -> validate(key, it.getJSONObject(key)) }
        }
    }.getOrElse { empty() }

    fun snapshot(): JSONObject? = state.takeIf { it.optBoolean("verified") }
    fun link(): String? = state.optString("link").takeIf(tokenPattern::matches)

    fun confirm(owner: String): String {
        require(ownerPattern.matches(owner))
        if (state.optBoolean("verified") && state.optString("owner") == owner &&
            state.optString("lease").isNotEmpty()) return state.getString("lease")
        val next = if (state.optString("owner") == owner) copy() else empty()
        val lease = UUID.randomUUID().toString()
        next.put("owner", owner).put("lease", lease).put("verified", true)
        if (!next.has("link")) next.put("link", UUID.randomUUID().toString())
        save(next)
        return lease
    }

    fun suspendVerification() {
        if (!state.optBoolean("verified")) return
        val hidden = copy().put("verified", false).removeLease()
        try {
            save(hidden)
        } catch (_: Exception) {
            clear()
        }
    }

    fun clear() {
        // Fail closed in memory even if the storage volume is temporarily unwritable.
        state = empty()
        visibleLink = null
        file.delete()
    }

    fun update(lease: String, key: String, raw: String): Boolean {
        if (!state.optBoolean("verified") || state.optString("lease") != lease) return false
        require(raw.length <= MAX_BYTES)
        val section = JSONObject(raw)
        validate(key, section)
        if (state.optJSONObject(key)?.toString() == section.toString()) return false
        save(copy().put(key, section))
        return true
    }

    private fun copy() = JSONObject(state.toString())
    private fun JSONObject.removeLease() = apply { remove("lease") }
    private fun JSONObject.sections() = listOf("timetable", "exams").filter(::has)

    private fun save(next: JSONObject) {
        val bytes = next.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_BYTES)
        val output = file.startWrite()
        try {
            output.write(bytes)
            file.finishWrite(output)
            state = next
            visibleLink = next.takeIf { it.optBoolean("verified") }?.optString("link")
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
    }

    private fun validate(key: String, data: JSONObject) {
        when (key) {
            "timetable" -> {
                val periods = data.getJSONArray("periods")
                require(periods.length() == 12)
                var end = -1
                for (index in 0 until periods.length()) {
                    val pair = periods.getJSONArray(index)
                    require(pair.getInt(0) > end)
                    end = pair.getInt(1)
                    require(end in pair.getInt(0) + 1..1439)
                }
                val terms = data.getJSONArray("terms")
                val ids = mutableSetOf<String>()
                terms.objects().forEach { term ->
                    val weeks = term.getInt("weeks")
                    require(term.getString("id").length in 1..512 && ids.add(term.getString("id")))
                    require(LocalDate.parse(term.getString("start")).year in 1900..2200)
                    require(weeks in 1..60)
                    term.getJSONArray("courses").objects().forEach { course ->
                        course.validateRecord()
                        val from = course.getInt("from")
                        val to = course.getInt("to")
                        require(from in 0..1438 && to in from + 1..1439)
                        require(course.getInt("day") in 1..7)
                        require(course.getInt("first") in 0..11)
                        require(course.getInt("last") in course.getInt("first") + 1..12)
                        val schedule = course.getJSONArray("weeks")
                        require(schedule.length() in 1..weeks)
                        for (i in 0 until schedule.length()) require(schedule.getInt(i) in 1..weeks)
                        val colors = course.getJSONArray("colors")
                        require(colors.length() == 4)
                        for (i in 0..3) require(colors.getLong(i) in 0xff000000L..0xffffffffL)
                    }
                }
            }
            "exams" -> data.getJSONArray("items").objects().forEach {
                it.validateRecord()
                require(it.getLong("end") > it.getLong("start"))
                require(campusDay(Instant.ofEpochMilli(it.getLong("start"))).year in 1900..2200)
                require(campusDay(Instant.ofEpochMilli(it.getLong("end"))).year in 1900..2200)
            }
            else -> error("Unknown widget section")
        }
    }

    private fun JSONObject.validateRecord() {
        require(getString("id").length in 1..512)
        require(getString("name").isNotBlank() && getString("name").length <= 500)
        require(getString("room").length <= 500)
    }

    companion object {
        private const val VERSION = 1
        private const val MAX_BYTES = 2 * 1024 * 1024
        private val ownerPattern = Regex("[0-9a-f]{64}")
        private val tokenPattern = Regex("[0-9a-f-]{36}")
        private fun empty() = JSONObject().put("version", VERSION)
    }
}

internal fun JSONArray.objects(): List<JSONObject> = List(length(), ::getJSONObject)

internal class WidgetData(snapshot: JSONObject?, val now: Instant = Instant.now()) {
    val today: LocalDate = campusDay(now)
    val timetable = snapshot?.optJSONObject("timetable")
    val terms = timetable?.getJSONArray("terms")?.objects().orEmpty()
    val term = terms.firstOrNull { !today.isBefore(it.start()) } ?: terms.firstOrNull()
    val exams = snapshot?.optJSONObject("exams")?.getJSONArray("items")?.objects().orEmpty()
        .filter { it.getLong("end") > now.toEpochMilli() }
        .sortedBy { it.getLong("start") }
    val todayCourses = currentWeek()?.let { courses(it, today.dayOfWeek.value) }.orEmpty()
    private val lastCourseEnd = todayCourses.maxOfOrNull { it.getInt("to") }?.let {
        today.atStartOfDay().plusMinutes(it.toLong()).toInstant(campusZone)
    }
    val todayCoursesEnded = lastCourseEnd?.let { now >= it } ?: false

    fun JSONObject.start(): LocalDate = LocalDate.parse(getString("start"))
    fun JSONObject.monday(): LocalDate = start().let { it.minusDays(it.dayOfWeek.value - 1L) }
    fun currentWeek(): Int? = term?.let { current ->
        val week = (ChronoUnit.DAYS.between(current.monday(), today) / 7 + 1).toInt()
        week.takeIf { week in 1..current.getInt("weeks") && today >= current.start() }
    }
    fun defaultWeek(): Int = currentWeek() ?: if (term?.let { today > it.start() } == true) {
        term.getInt("weeks")
    } else 1

    fun courses(week: Int, day: Int): List<JSONObject> {
        val current = term ?: return emptyList()
        if (week !in 1..current.getInt("weeks") ||
            current.monday().plusDays((week - 1) * 7L + day - 1) < current.start()) return emptyList()
        return current.getJSONArray("courses").objects().filter { course ->
            val weeks = course.getJSONArray("weeks")
            course.getInt("day") == day && (0 until weeks.length()).any { weeks.getInt(it) == week }
        }.sortedBy { it.getInt("from") }
    }

    fun hasCourse(id: String) = terms.any { term ->
        term.getJSONArray("courses").objects().any { it.getString("id") == id }
    }

    fun nextUpdate(includeToday: Boolean, includeExams: Boolean): Long {
        val midnight = today.plusDays(1).atStartOfDay().toInstant(campusZone).toEpochMilli()
        val courseEnd = lastCourseEnd?.takeIf { includeToday && !todayCoursesEnded }?.toEpochMilli()
        val examBoundary = if (includeExams) exams.asSequence()
            .flatMap { sequenceOf(it.getLong("start"), it.getLong("end")) }
            .filter { it > now.toEpochMilli() }.minOrNull() else null
        return listOfNotNull(midnight, courseEnd, examBoundary).min()
    }

    fun examStatus(exam: JSONObject): ExamStatus {
        val start = Instant.ofEpochMilli(exam.getLong("start"))
        val days = ChronoUnit.DAYS.between(today, campusDay(start))
        return when {
            !now.isBefore(start) -> ExamStatus("进行中")
            days == 0L -> ExamStatus("今天", warning = true)
            days == 1L -> ExamStatus("明天")
            else -> ExamStatus(days.toString(), unit = "天")
        }
    }
}

internal data class ExamStatus(val label: String, val unit: String = "", val warning: Boolean = false)
