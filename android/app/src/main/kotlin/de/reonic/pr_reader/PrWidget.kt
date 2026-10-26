package de.reonic.pr_reader

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * A home screen widget for one pull request.
 *
 * The Flutter app writes a JSON snapshot per PR to its shared preferences
 * (`flutter.widget:owner/repo#n`). Each widget remembers which PR it shows;
 * one added from the launcher's widget list shows the last PR opened.
 */
class PrWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = bindings(context).edit()
        for (id in ids) edit.remove("id:$id")
        edit.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_PINNED) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            val key = intent.getStringExtra(EXTRA_KEY)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID && key != null) {
                bindings(context).edit().putString("id:$id", key).remove(PENDING).apply()
                render(context, AppWidgetManager.getInstance(context), id)
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_PINNED = "de.reonic.pr_reader.WIDGET_PINNED"
        const val EXTRA_KEY = "key"
        private const val PENDING = "pending"

        private fun bindings(context: Context) = context.getSharedPreferences("pr_widgets", Context.MODE_PRIVATE)

        private fun flutterPrefs(context: Context) =
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        private fun canPin(context: Context): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

        /** Asks the launcher to place a widget for the PR [key]. */
        fun pin(context: Context, key: String): Boolean {
            if (!canPin(context)) return false
            // The launcher may draw the new widget before the callback below
            // arrives; render it with this PR in the meantime.
            bindings(context).edit().putString(PENDING, key).apply()
            val callback = PendingIntent.getBroadcast(
                context,
                key.hashCode(),
                Intent(context, PrWidget::class.java).setAction(ACTION_PINNED).putExtra(EXTRA_KEY, key),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            return AppWidgetManager.getInstance(context)
                .requestPinAppWidget(ComponentName(context, PrWidget::class.java), null, callback)
        }

        /** PR keys that have a widget on the home screen. */
        fun pinned(context: Context): List<String> {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PrWidget::class.java))
            return ids.toList().mapNotNull { id -> keyFor(context, id, false) }.distinct()
        }

        /** Redraws every widget from the latest snapshots. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, PrWidget::class.java))) {
                render(context, manager, id)
            }
        }

        private fun keyFor(context: Context, id: Int, bind: Boolean = true): String? {
            val b = bindings(context)
            b.getString("id:$id", null)?.let { return it }
            val key = b.getString(PENDING, null) ?: lastOpened(context) ?: return null
            if (bind) b.edit().putString("id:$id", key).remove(PENDING).apply()
            return key
        }

        private fun lastOpened(context: Context): String? {
            val prefs = flutterPrefs(context)
            prefs.getString("flutter.last_pr", null)?.let { return it }
            return try {
                val first = JSONArray(prefs.getString("flutter.recents", "[]")).optJSONObject(0) ?: return null
                "${first.getString("o")}/${first.getString("r")}#${first.getInt("n")}"
            } catch (e: Exception) {
                null
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.pr_widget)
            val key = keyFor(context, id)
            val snap = key?.let { k ->
                try {
                    flutterPrefs(context).getString("flutter.widget:$k", null)?.let { JSONObject(it) }
                } catch (e: Exception) {
                    null
                }
            }
            if (key == null || snap == null) {
                views.setTextViewText(R.id.state, "PR Reader")
                views.setInt(R.id.state, "setBackgroundResource", R.drawable.chip_draft)
                views.setTextViewText(R.id.repo, key ?: "")
                views.setTextViewText(R.id.title, "Open a pull request in PR Reader to show it here.")
                views.setViewVisibility(R.id.progress, View.GONE)
                views.setTextViewText(R.id.viewed, "")
                views.setTextViewText(R.id.additions, "")
                views.setTextViewText(R.id.deletions, "")
                views.setViewVisibility(R.id.reading, View.GONE)
                views.setOnClickPendingIntent(android.R.id.background, open(context, id, null))
                manager.updateAppWidget(id, views)
                return
            }

            val state = snap.optString("state", "open")
            views.setTextViewText(R.id.state, state.replaceFirstChar { it.uppercase() })
            views.setInt(
                R.id.state,
                "setBackgroundResource",
                when (state) {
                    "draft" -> R.drawable.chip_draft
                    "merged" -> R.drawable.chip_merged
                    "closed" -> R.drawable.chip_closed
                    else -> R.drawable.chip_open
                },
            )
            views.setTextViewText(R.id.repo, "${snap.optString("repo")} #${snap.optInt("number")}")
            views.setTextViewText(R.id.title, snap.optString("title"))

            val files = snap.optInt("files")
            val viewed = snap.optInt("viewed").coerceAtMost(files)
            views.setViewVisibility(R.id.progress, if (files > 0) View.VISIBLE else View.GONE)
            views.setProgressBar(R.id.progress, files.coerceAtLeast(1), viewed, false)
            views.setTextViewText(
                R.id.viewed,
                when {
                    files == 0 -> ""
                    viewed == files -> "All ${count(files)} files viewed"
                    else -> "${count(viewed)} of ${count(files)} files viewed"
                },
            )
            views.setTextViewText(R.id.additions, "+${count(snap.optInt("additions"))}")
            views.setTextViewText(R.id.deletions, "−${count(snap.optInt("deletions"))}")

            val reading = snap.optString("reading").takeIf { it.isNotEmpty() && it != "null" }
            views.setViewVisibility(R.id.reading, if (reading != null) View.VISIBLE else View.GONE)
            if (reading != null) views.setTextViewText(R.id.reading, "Continue at ${reading.substringAfterLast('/')}")

            views.setOnClickPendingIntent(android.R.id.background, open(context, id, key))
            manager.updateAppWidget(id, views)
        }

        /** Opens the PR through its pr:// link, which resumes reading. */
        private fun open(context: Context, id: Int, key: String?): PendingIntent {
            val intent = if (key == null) {
                context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            } else {
                val (repo, number) = key.split('#', limit = 2)
                Intent(Intent.ACTION_VIEW, Uri.parse("pr://github.com/$repo/pull/$number")).setPackage(context.packageName)
            }
            return PendingIntent.getActivity(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun count(n: Int): String = when {
            n >= 10_000 -> "${n / 1000}k"
            n >= 1000 -> String.format("%.1fk", n / 1000.0).replace(".0k", "k")
            else -> n.toString()
        }
    }
}
