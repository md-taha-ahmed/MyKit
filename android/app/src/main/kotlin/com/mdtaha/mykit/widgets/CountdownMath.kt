package com.mdtaha.mykit.widgets

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil

/**
 * Native mirror of `lib/features/countdown/domain/services/countdown_calculator.dart`.
 * Keep both in sync when changing countdown math.
 */
data class CountdownData(
    val id: String,
    val title: String,
    val targetYear: Int,
    val targetMonth: Int,
    val targetDay: Int,
    val recurrence: String,
    val showTitleInWidget: Boolean,
    val unit: String,
    val showLabel: Boolean,
    val decreaseCircle: Boolean,
    val decreaseStartDays: Int,
    val ringColor: Int,
    val backgroundColor: Int,
    val trackColor: Int,
    val textColor: Int,
    val font: String,
    val dropShadow: Boolean,
    val clockwise: Boolean,
) {
    companion object {
        fun fromJson(o: JSONObject): CountdownData {
            val parts = o.getString("targetDate").split("-").map { it.toInt() }
            return CountdownData(
                id = o.getString("id"),
                title = o.optString("title", ""),
                targetYear = parts[0],
                targetMonth = parts[1],
                targetDay = parts[2],
                recurrence = o.optString("recurrence", "none"),
                showTitleInWidget = o.optBoolean("showTitleInWidget", true),
                unit = o.optString("unit", "days"),
                showLabel = o.optBoolean("showLabel", true),
                decreaseCircle = o.optBoolean("decreaseCircle", true),
                decreaseStartDays = o.optInt("decreaseStartDays", 30),
                // Dart stores ARGB as unsigned ints; toInt() keeps the bit pattern.
                ringColor = o.optLong("ringColor", 0xFF7B1FA2).toInt(),
                backgroundColor = o.optLong("backgroundColor", 0xFF000000).toInt(),
                trackColor = o.optLong("trackColor", 0xFF000000).toInt(),
                textColor = o.optLong("textColor", 0xFFFFFFFF).toInt(),
                font = o.optString("font", "normal"),
                dropShadow = o.optBoolean("dropShadow", false),
                clockwise = o.optBoolean("clockwise", false),
            )
        }

        fun listFromJson(raw: String?): List<CountdownData> {
            if (raw.isNullOrEmpty()) return emptyList()
            return try {
                val array = JSONArray(raw)
                (0 until array.length()).map { fromJson(array.getJSONObject(it)) }
            } catch (e: Exception) {
                emptyList()
            }
        }
    }
}

data class CountdownSnapshot(
    val daysRemaining: Long,
    val valueText: String,
    val label: String,
    val progress: Float,
)

object CountdownMath {
    private const val DAYS_PER_MONTH = 30.436875
    private const val DAYS_PER_YEAR = 365.2425

    fun snapshot(c: CountdownData, now: Calendar = Calendar.getInstance()): CountdownSnapshot {
        val today = epochDay(
            now.get(Calendar.YEAR),
            now.get(Calendar.MONTH) + 1,
            now.get(Calendar.DAY_OF_MONTH),
        )
        val effective = nextOccurrence(c, today)
        val days = effective - today
        val absDays = abs(days).toDouble()

        val value = when (c.unit) {
            "weeks" -> absDays / 7
            "months" -> absDays / DAYS_PER_MONTH
            "years" -> absDays / DAYS_PER_YEAR
            else -> absDays
        }
        val decimals = when (c.unit) {
            "days" -> 0
            "years" -> 2
            else -> 1
        }
        val valueText = formatNumber(value, decimals)

        val label = if (days == 0L) {
            "Today"
        } else {
            val base = if (valueText == "1") singular(c.unit) else plural(c.unit)
            if (days < 0) "$base ago" else base
        }

        val progress = when {
            days < 0 -> 0f
            c.decreaseCircle -> {
                val start = if (c.decreaseStartDays <= 0) 1 else c.decreaseStartDays
                (days.toFloat() / start).coerceIn(0f, 1f)
            }
            else -> 1f
        }

        return CountdownSnapshot(days, valueText, label, progress)
    }

    private fun nextOccurrence(c: CountdownData, today: Long): Long {
        val target = epochDay(c.targetYear, c.targetMonth, c.targetDay)
        if (target >= today || c.recurrence == "none") return target

        return when (c.recurrence) {
            "daily" -> today
            "weekly" -> {
                val weeks = ceil((today - target) / 7.0).toLong()
                target + weeks * 7
            }
            "monthly", "yearly" -> {
                val step = if (c.recurrence == "monthly") 1 else 12
                var months = 0
                var date = target
                while (date < today) {
                    months += step
                    date = addMonths(c.targetYear, c.targetMonth, c.targetDay, months)
                }
                date
            }
            else -> target
        }
    }

    private fun addMonths(year: Int, month: Int, day: Int, months: Int): Long {
        val index = month - 1 + months
        val y = year + Math.floorDiv(index, 12)
        val m = Math.floorMod(index, 12) + 1
        return epochDay(y, m, minOf(day, daysInMonth(y, m)))
    }

    private fun daysInMonth(y: Int, m: Int): Int = when (m) {
        2 -> if ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) 29 else 28
        4, 6, 9, 11 -> 30
        else -> 31
    }

    /** Days since 1970-01-01 for a civil date (no java.time needed on old APIs). */
    fun epochDay(year: Int, month: Int, day: Int): Long {
        val y = if (month <= 2) year - 1 else year
        val era = Math.floorDiv(y, 400)
        val yoe = y - era * 400
        val mp = (month + 9) % 12
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097L + doe - 719468L
    }

    private fun formatNumber(value: Double, decimals: Int): String {
        var text = String.format(Locale.US, "%.${decimals}f", value)
        if (text.contains('.')) text = text.trimEnd('0').trimEnd('.')
        return text
    }

    private fun plural(unit: String) = when (unit) {
        "weeks" -> "Weeks"
        "months" -> "Months"
        "years" -> "Years"
        else -> "Days"
    }

    private fun singular(unit: String) = plural(unit).dropLast(1)
}
