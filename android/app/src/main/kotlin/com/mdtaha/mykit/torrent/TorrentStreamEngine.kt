package com.mdtaha.mykit.torrent

import android.content.Context
import android.util.Log
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.SessionParams
import org.libtorrent4j.SettingsPack
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentFlags
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.SessionHandle
import java.io.File
import java.net.URL
import java.net.URLEncoder

/**
 * Streams one file of a torrent while it downloads.
 *
 * libtorrent fetches the metadata from the magnet, only the chosen file is
 * downloaded (sequentially), and [TorrentHttpServer] serves it to the player
 * over `http://127.0.0.1`, waiting for — and prioritising — whatever pieces the
 * player reads next, so seeking works too.
 *
 * One stream at a time: starting a new one stops (and deletes) the previous.
 */
class TorrentStreamEngine private constructor(context: Context) {

    companion object {
        private const val TAG = "TorrentStream"

        /** Bytes buffered before the player is started. */
        private const val PREBUFFER_BYTES = 3L * 1024 * 1024

        /** Bytes kept at top priority ahead of the player (scaled with the file size). */
        private const val MIN_WINDOW_BYTES = 24L * 1024 * 1024
        private const val MAX_WINDOW_BYTES = 96L * 1024 * 1024

        /** Fresh public trackers, added to every torrent for more peers. */
        private const val TRACKERS_URL =
            "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_best.txt"

        private val VIDEO_EXTENSIONS = setOf(
            "mkv", "mp4", "m4v", "avi", "mov", "webm", "ts", "m2ts", "wmv", "flv", "mpg", "mpeg",
        )

        @Volatile
        private var instance: TorrentStreamEngine? = null

        fun get(context: Context): TorrentStreamEngine =
            instance ?: synchronized(this) {
                instance ?: TorrentStreamEngine(context.applicationContext).also { instance = it }
            }
    }

    private val cacheDir = File(context.cacheDir, "torrent_streams")
    private val session = SessionManager(false)
    private val server = TorrentHttpServer(this)

    @Volatile
    var current: Stream? = null
        private set

    /** The stream being served, with what's needed to map reads onto pieces. */
    inner class Stream(
        val id: String,
        val infoHash: String,
        private val requestedFileIdx: Int?,
        private val filenameHint: String?,
    ) {
        @Volatile var handle: TorrentHandle? = null
        @Volatile var fileIdx = -1
        @Volatile var fileName = ""
        @Volatile var fileSize = 0L
        @Volatile var fileOffset = 0L
        @Volatile var pieceLength = 0
        @Volatile var file: File? = null
        @Volatile var stopped = false
        @Volatile var error: String? = null
        private var prebufferPieces: List<Int> = emptyList()

        /** Pieces we raised to top priority / gave a deadline, so they can be reset. */
        private val boosted = HashSet<Int>()
        private val deadlined = HashSet<Int>()
        private var windowPieces = 8

        val ready get() = file != null && prebufferPieces.all { havePiece(it) }

        fun pieceAt(position: Long) = ((fileOffset + position) / pieceLength).toInt()

        fun havePiece(piece: Int) = handle?.havePiece(piece) == true

        /** Called while no metadata yet; once it arrives, selects the file. */
        fun pollMetadata() {
            if (file != null || stopped) return
            val h = handle ?: session.find(Sha1Hash.parseHex(infoHash))?.also { handle = it } ?: return
            if (!h.isValid || !h.status().hasMetadata()) return
            val info = h.torrentFile() ?: return
            val files = info.files()
            val idx = chooseFile(files)
            if (idx < 0) {
                error = "This torrent has no playable video file."
                return
            }
            h.prioritizeFiles(Array(files.numFiles()) { if (it == idx) Priority.DEFAULT else Priority.IGNORE })
            fileIdx = idx
            fileName = files.fileName(idx)
            fileSize = files.fileSize(idx)
            fileOffset = files.fileOffset(idx)
            pieceLength = info.pieceLength()

            // Start of the file, plus its tail where MP4/MKV indexes often live.
            val first = pieceAt(0)
            val last = pieceAt(fileSize - 1)
            val head = (first..minOf(last, pieceAt(minOf(PREBUFFER_BYTES, fileSize) - 1))).toList()
            prebufferPieces = (head + last).distinct()
            val windowBytes = (fileSize / 100).coerceIn(MIN_WINDOW_BYTES, MAX_WINDOW_BYTES)
            windowPieces = maxOf(4, (windowBytes / pieceLength).toInt())
            // Plain top priority (not deadlines): peers keep full request pipelines.
            synchronized(this) {
                for (p in prebufferPieces) boost(h, p)
            }
            file = File(cacheDir, files.filePath(idx))
            Log.i(TAG, "Streaming '$fileName' ($fileSize bytes, ${prebufferPieces.size} prebuffer pieces)")
        }

        private fun chooseFile(files: org.libtorrent4j.FileStorage): Int {
            val count = files.numFiles()
            requestedFileIdx?.takeIf { it in 0 until count && !files.padFileAt(it) }?.let { return it }
            val videos = (0 until count).filter {
                !files.padFileAt(it) && files.fileName(it).substringAfterLast('.', "").lowercase() in VIDEO_EXTENSIONS
            }
            filenameHint?.let { hint ->
                videos.firstOrNull { files.fileName(it).equals(hint, ignoreCase = true) }?.let { return it }
            }
            return videos.maxByOrNull { files.fileSize(it) } ?: -1
        }

        private fun boost(h: TorrentHandle, piece: Int) {
            if (boosted.add(piece) && !h.havePiece(piece)) h.piecePriority(piece, Priority.TOP_PRIORITY)
        }

        fun bufferProgress(): Double {
            if (prebufferPieces.isEmpty()) return 0.0
            return prebufferPieces.count { havePiece(it) }.toDouble() / prebufferPieces.size
        }

        /**
         * Blocks until [piece] is downloaded, prioritising it and the pieces after it.
         * Returns false if the stream was stopped meanwhile.
         */
        fun awaitPiece(piece: Int): Boolean {
            val h = handle ?: return false
            requestAhead(h, piece)
            if (h.havePiece(piece)) return true
            while (!stopped && h.isValid) {
                if (h.havePiece(piece)) return true
                Thread.sleep(50)
            }
            return false
        }

        /**
         * Moves the top-priority window to start at [from]. Only the piece the
         * player is blocked on (and the next one) get a deadline: libtorrent's
         * deadline mode asks peers one block at a time, which is fast for one
         * piece but throttles everything if used for the whole buffer.
         */
        @Synchronized
        private fun requestAhead(h: TorrentHandle, from: Int) {
            if (!h.isValid) return
            val last = pieceAt(fileSize - 1)
            val window = from..minOf(last, from + windowPieces)

            // After a seek, pieces boosted for the old position go back to normal.
            val stale = boosted.filter { it !in window && it !in prebufferPieces }
            for (p in stale) {
                boosted.remove(p)
                if (!h.havePiece(p)) h.piecePriority(p, Priority.DEFAULT)
            }
            for (p in window) boost(h, p)

            val urgent = listOf(from, from + 1).filter { it <= last && !h.havePiece(it) }
            for (p in deadlined.filter { it !in urgent }) {
                deadlined.remove(p)
                h.resetPieceDeadline(p)
            }
            urgent.forEachIndexed { i, p -> if (deadlined.add(p)) h.setPieceDeadline(p, 1000 + i * 1000) }
        }

        fun toMap(): Map<String, Any?> {
            val status = handle?.takeIf { it.isValid }?.status()
            return mapOf(
                "id" to id,
                "state" to when {
                    error != null -> "error"
                    file == null -> "metadata"
                    ready -> "ready"
                    else -> "buffering"
                },
                "error" to error,
                "url" to file?.let { server.urlFor(this) },
                "fileName" to fileName,
                "fileSize" to fileSize,
                "buffer" to bufferProgress(),
                "progress" to (status?.progress()?.toDouble() ?: 0.0),
                "downloadRate" to (status?.downloadPayloadRate() ?: 0),
                "uploadRate" to (status?.uploadPayloadRate() ?: 0),
                "peers" to (status?.numPeers() ?: 0),
                "seeds" to (status?.numSeeds() ?: 0),
            )
        }
    }

    @Synchronized
    private fun ensureStarted() {
        if (session.isRunning) return
        cacheDir.deleteRecursively()
        cacheDir.mkdirs()
        val settings = SettingsPack()
            .connectionsLimit(200)
            .activeDownloads(4)
        settings.setEnableDht(true)
        // Default (multi-threaded, memory-mapped) disk I/O: the simple POSIX
        // backend is single-threaded and throttled downloads.
        session.start(SessionParams(settings))
        server.start()
    }

    @Volatile
    private var publicTrackers: List<String>? = null

    /** Starts the session (DHT bootstrap) and fetches trackers ahead of the first stream. */
    fun warmUp() {
        ensureStarted()
        trackers()
    }

    private fun trackers(): List<String> {
        publicTrackers?.let { return it }
        val list = try {
            val conn = URL(TRACKERS_URL).openConnection().apply {
                connectTimeout = 4000
                readTimeout = 4000
            }
            conn.getInputStream().bufferedReader().use { r ->
                r.readLines().map { it.trim() }.filter { it.contains("://") }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Tracker list unavailable: ${e.message}")
            return emptyList()
        }
        publicTrackers = list
        return list
    }

    @Synchronized
    fun start(infoHash: String, fileIdx: Int?, trackers: List<String>, filename: String?): Stream {
        ensureStarted()
        val hash = infoHash.lowercase()
        current?.let { if (it.infoHash == hash && it.error == null && !it.stopped) return it }
        stopCurrent()

        val magnet = buildString {
            append("magnet:?xt=urn:btih:").append(hash)
            for (tr in (trackers + trackers()).distinct()) append("&tr=").append(URLEncoder.encode(tr, "UTF-8"))
        }
        val stream = Stream("${hash}_${System.currentTimeMillis()}", hash, fileIdx, filename)
        current = stream
        session.download(magnet, cacheDir, TorrentFlags.SEQUENTIAL_DOWNLOAD)
        stream.pollMetadata()
        return stream
    }

    fun status(id: String): Map<String, Any?>? {
        val stream = current?.takeIf { it.id == id } ?: return null
        stream.pollMetadata()
        return stream.toMap()
    }

    @Synchronized
    fun stop(id: String) {
        if (current?.id == id) stopCurrent()
    }

    @Synchronized
    private fun stopCurrent() {
        val stream = current ?: return
        stream.stopped = true
        current = null
        val h = stream.handle ?: session.find(Sha1Hash.parseHex(stream.infoHash))
        if (h != null && h.isValid) session.remove(h, SessionHandle.DELETE_FILES)
    }
}
