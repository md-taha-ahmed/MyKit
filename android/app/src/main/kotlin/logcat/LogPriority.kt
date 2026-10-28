package logcat

/** Minimal stand-in for square/logcat's LogPriority used by ported Mihon code. */
enum class LogPriority(val androidPriority: Int) {
    VERBOSE(2), DEBUG(3), INFO(4), WARN(5), ERROR(6), ASSERT(7),
}
