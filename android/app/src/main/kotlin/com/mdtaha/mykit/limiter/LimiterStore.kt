package com.mdtaha.mykit.limiter

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

/** A platform with one shared daily allowance (app, Lite app and website). */
class LimitGroup(
    val id: String,
    val name: String,
    val packages: Set<String>,
    val domains: List<String>,
    val limitMinutes: Int,
    val enabled: Boolean,
) {
    fun matchesHost(host: String) =
        domains.any { host == it || host.endsWith(".$it") }
}

/** Fully blocked between [start] and [end] (may cross midnight) on [days]. */
class FocusWindow(
    val start: LocalTime,
    val end: LocalTime,
    val days: Set<DayOfWeek>,
    val groups: Set<String>,
) {
    fun isActive(now: LocalDateTime, groupId: String): Boolean {
        if (groupId !in groups) return false
        val t = now.toLocalTime()
        return if (start <= end) {
            now.dayOfWeek in days && t >= start && t < end
        } else {
            // e.g. 23:00 → 07:00: before midnight counts for today, after
            // midnight for the day it started.
            (now.dayOfWeek in days && t >= start) ||
                (now.minusDays(1).dayOfWeek in days && t < end)
        }
    }
}

class LimiterConfig(
    val groups: List<LimitGroup>,
    val focus: List<FocusWindow>,
    val extensionMinutes: Int,
    val extensionsPerDay: Int,
    val extensionWaitSeconds: Int,
    val warnMinutes: Int,
) {
    companion object {
        val EMPTY = LimiterConfig(emptyList(), emptyList(), 5, 2, 15, 5)

        fun parse(raw: String?): LimiterConfig {
            if (raw.isNullOrEmpty()) return EMPTY
            val j = JSONObject(raw)
            fun strings(a: JSONArray?) =
                (0 until (a?.length() ?: 0)).map { a!!.getString(it) }
            return LimiterConfig(
                groups = j.optJSONArray("groups").let { a ->
                    (0 until (a?.length() ?: 0)).map { a!!.getJSONObject(it) }.map {
                        LimitGroup(
                            id = it.getString("id"),
                            name = it.getString("name"),
                            packages = strings(it.optJSONArray("packages")).toSet(),
                            domains = strings(it.optJSONArray("domains")),
                            limitMinutes = it.optInt("limitMinutes", 30),
                            enabled = it.optBoolean("enabled", true),
                        )
                    }
                },
                focus = j.optJSONArray("focus").let { a ->
                    (0 until (a?.length() ?: 0)).map { a!!.getJSONObject(it) }.map {
                        FocusWindow(
                            start = LocalTime.parse(it.getString("start")),
                            end = LocalTime.parse(it.getString("end")),
                            days = strings(it.optJSONArray("days"))
                                .map { d -> DayOfWeek.of(d.toInt()) }.toSet(),
                            groups = strings(it.optJSONArray("groups")).toSet(),
                        )
                    }
                },
                extensionMinutes = j.optInt("extensionMinutes", 5),
                extensionsPerDay = j.optInt("extensionsPerDay", 2),
                extensionWaitSeconds = j.optInt("extensionWaitSeconds", 15),
                warnMinutes = j.optInt("warnMinutes", 5),
            )
        }
    }
}

/**
 * Screen-time limiter state on the device: the settings (written by the
 * Flutter app), seconds used per platform per day, and today's extensions.
 * Everything stays on the phone.
 */
class LimiterStore private constructor(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var config: LimiterConfig = LimiterConfig.parse(prefs.getString(KEY_CONFIG, null))
        private set

    fun saveConfig(raw: String) {
        prefs.edit().putString(KEY_CONFIG, raw).apply()
        config = LimiterConfig.parse(raw)
    }

    fun reloadConfig() {
        config = LimiterConfig.parse(prefs.getString(KEY_CONFIG, null))
    }

    // --- Usage: {"2026-10-30": {"instagram": 125, …}, …}, last 14 days ----

    private var usage: JSONObject = load(KEY_USAGE)

    fun secondsToday(groupId: String): Int =
        usage.optJSONObject(today())?.optInt(groupId, 0) ?: 0

    fun addSecond(groupId: String) {
        val day = usage.optJSONObject(today()) ?: JSONObject().also { usage.put(today(), it) }
        day.put(groupId, day.optInt(groupId, 0) + 1)
    }

    /** Writes usage (called every few seconds and when leaving an app). */
    fun flush() {
        val keep = LocalDate.now().minusDays(13).toString()
        usage.keys().asSequence().toList().filter { it < keep }.forEach { usage.remove(it) }
        prefs.edit().putString(KEY_USAGE, usage.toString()).apply()
    }

    fun usageJson(): String = usage.toString()

    // --- Extensions: {"date": "...", "<group>": {"used": n, "until": ms}} ---

    private var extensions: JSONObject = load(KEY_EXTENSIONS).let {
        if (it.optString("date") == today()) it else JSONObject().put("date", today())
    }

    private fun ext(groupId: String): JSONObject {
        if (extensions.optString("date") != today()) {
            extensions = JSONObject().put("date", today())
        }
        return extensions.optJSONObject(groupId)
            ?: JSONObject().also { extensions.put(groupId, it) }
    }

    fun extensionsUsed(groupId: String) = ext(groupId).optInt("used", 0)

    fun extensionActive(groupId: String) =
        ext(groupId).optLong("until", 0) > System.currentTimeMillis()

    fun extensionsLeft(groupId: String) =
        (config.extensionsPerDay - extensionsUsed(groupId)).coerceAtLeast(0)

    fun grantExtension(groupId: String): Boolean {
        if (extensionsLeft(groupId) <= 0) return false
        val e = ext(groupId)
        e.put("used", e.optInt("used", 0) + 1)
        e.put("until", System.currentTimeMillis() + config.extensionMinutes * 60_000L)
        prefs.edit().putString(KEY_EXTENSIONS, extensions.toString()).apply()
        return true
    }

    fun extensionsJson(): String = extensions.toString()

    // --- Warnings sent today, so each is sent once ------------------------

    fun warnedToday(groupId: String) =
        prefs.getString("$KEY_WARNED$groupId", null) == today()

    fun markWarned(groupId: String) {
        prefs.edit().putString("$KEY_WARNED$groupId", today()).apply()
    }

    private fun load(key: String) = try {
        JSONObject(prefs.getString(key, null) ?: "{}")
    } catch (_: Exception) {
        JSONObject()
    }

    companion object {
        @Volatile private var instance: LimiterStore? = null

        /** One per process, shared by the service and the app's channel. */
        fun get(context: Context): LimiterStore = instance ?: synchronized(this) {
            instance ?: LimiterStore(context.applicationContext).also { instance = it }
        }

        const val PREFS = "limiter"
        private const val KEY_CONFIG = "config"
        private const val KEY_USAGE = "usage"
        private const val KEY_EXTENSIONS = "extensions"
        private const val KEY_WARNED = "warned_"

        fun today(): String = LocalDate.now().toString()
    }
}
