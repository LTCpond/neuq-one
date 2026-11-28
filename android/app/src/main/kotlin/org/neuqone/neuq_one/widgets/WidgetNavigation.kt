package org.neuqone.neuq_one.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.neuqone.neuq_one.MainActivity
import java.security.MessageDigest
import java.util.UUID

internal object WidgetNavigation {
    const val COURSE_ID = "neuqWidgetCourse"
    const val COURSE = "course"
    const val TIMETABLE = "timetable"
    const val EXAMS = "exams"
    const val ADD_EXAM = "add-exam"
    private const val OPEN = "org.neuqone.neuq_one.widget.OPEN"
    private val targets = setOf(COURSE, TIMETABLE, EXAMS, ADD_EXAM)

    private fun installToken(context: Context): String {
        val prefs = context.getSharedPreferences("desktop-widget-links", Context.MODE_PRIVATE)
        return prefs.getString("token", null) ?: UUID.randomUUID().toString().also {
            check(prefs.edit().putString("token", it).commit())
        }
    }

    fun open(
        context: Context, id: Int, link: String?, target: String,
        course: String? = null, collection: Boolean = false
    ): PendingIntent {
        val token = link ?: installToken(context)
        val uri = Uri.Builder().scheme("neuq-widget").authority("open")
            .appendPath(id.toString()).appendPath(token).appendPath(target)
        if (course != null) uri.appendPath(courseKey(course))
        val intent = Intent(OPEN, uri.build(), context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (course != null) intent.putExtra(COURSE_ID, course)
        val mutability = if (collection) {
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        } else PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutability)
    }

    fun read(context: Context, intent: Intent?, store: WidgetSnapshotStore): Link? {
        val uri = intent?.data ?: return null
        if (intent.action != OPEN || uri.scheme != "neuq-widget" || uri.authority != "open") return null
        val parts = uri.pathSegments
        if (parts.size !in 3..4) return null
        val id = parts[0].toIntOrNull() ?: return null
        val token = parts[1]
        val authenticated = store.link() == token
        if (!authenticated && token != installToken(context)) return null
        val target = parts[2]
        if (target !in targets) return null
        val kind = WidgetUpdateManager.kind(context, id) ?: return null
        if (target !in when (kind) {
            WidgetKind.TODAY, WidgetKind.WEEK -> setOf(TIMETABLE, COURSE)
            WidgetKind.EXAMS -> setOf(EXAMS, ADD_EXAM)
        }) return null
        if (target != COURSE) return Link(target, null, if (authenticated) token else null)
        if (!authenticated) return null
        val course = intent.getStringExtra(COURSE_ID) ?: return null
        if (course.length !in 1..512) return null
        if (parts.size == 4 && parts[3] != courseKey(course)) return null
        // On cold start the verified snapshot is still available until beginVerification.
        if (!WidgetData(store.snapshot()).hasCourse(course)) return null
        return Link(target, course, token)
    }

    private fun courseKey(course: String): String =
        MessageDigest.getInstance("SHA-256").digest(course.toByteArray()).take(16).joinToString("") { "%02x".format(it) }

    fun action(context: Context, id: Int, action: String): PendingIntent {
        val intent = Intent(context, WidgetEvents::class.java).setAction(WidgetEvents.USER_ACTION)
            .setData(Uri.Builder().scheme("neuq-widget").authority("action")
                .appendPath(id.toString()).appendPath(action).build())
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    data class Link(val target: String, val course: String?, val ownerLink: String?) {
        fun arguments() = mapOf("target" to target, "course" to course)
    }
}
