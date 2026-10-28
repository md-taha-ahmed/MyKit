package com.mdtaha.mykit.torrent

import android.util.Log
import java.io.BufferedOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.URLEncoder
import kotlin.concurrent.thread

/**
 * Minimal HTTP/1.1 server on 127.0.0.1 that serves the file being streamed by
 * [TorrentStreamEngine], with `Range` support. Each read waits for its piece.
 */
class TorrentHttpServer(private val engine: TorrentStreamEngine) {

    companion object {
        private const val TAG = "TorrentHttp"
        private const val CHUNK = 64 * 1024
    }

    private var socket: ServerSocket? = null

    @Synchronized
    fun start() {
        if (socket != null) return
        val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        socket = server
        thread(name = "torrent-http", isDaemon = true) {
            while (!server.isClosed) {
                val client = try {
                    server.accept()
                } catch (e: IOException) {
                    break
                }
                thread(name = "torrent-http-client", isDaemon = true) { serve(client) }
            }
        }
    }

    fun urlFor(stream: TorrentStreamEngine.Stream): String {
        val port = socket?.localPort ?: 0
        val name = URLEncoder.encode(stream.fileName, "UTF-8").replace("+", "%20")
        return "http://127.0.0.1:$port/${stream.id}/$name"
    }

    private fun serve(client: Socket) {
        client.use { s ->
            try {
                s.tcpNoDelay = true
                val input = s.getInputStream()
                val out = BufferedOutputStream(s.getOutputStream(), CHUNK)
                val requestLine = readLine(input) ?: return
                val headers = mutableMapOf<String, String>()
                while (true) {
                    val line = readLine(input) ?: break
                    if (line.isEmpty()) break
                    val colon = line.indexOf(':')
                    if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
                }
                val parts = requestLine.split(' ')
                val method = parts.getOrNull(0) ?: ""
                val id = parts.getOrNull(1)?.trimStart('/')?.substringBefore('/') ?: ""

                val stream = engine.current
                val file = stream?.file
                if (stream == null || stream.id != id || file == null || stream.stopped) {
                    respond(out, "404 Not Found", emptyMap())
                    return
                }
                val size = stream.fileSize
                var start = 0L
                var end = size - 1
                val range = headers["range"]
                val partial = range != null && range.startsWith("bytes=")
                if (partial) {
                    val spec = range!!.removePrefix("bytes=").substringBefore(',')
                    val (a, b) = spec.split('-', limit = 2).let { it[0] to it.getOrElse(1) { "" } }
                    if (a.isEmpty()) {
                        start = maxOf(0, size - (b.toLongOrNull() ?: 0))
                    } else {
                        start = a.toLongOrNull() ?: 0
                        b.toLongOrNull()?.let { end = minOf(it, size - 1) }
                    }
                    if (start >= size || start > end) {
                        respond(out, "416 Range Not Satisfiable", mapOf("Content-Range" to "bytes */$size"))
                        return
                    }
                }
                val length = end - start + 1
                val head = mutableMapOf(
                    "Content-Type" to mimeType(stream.fileName),
                    "Accept-Ranges" to "bytes",
                    "Content-Length" to length.toString(),
                )
                if (partial) head["Content-Range"] = "bytes $start-$end/$size"
                respond(out, if (partial) "206 Partial Content" else "200 OK", head)
                if (method == "HEAD") return
                send(stream, file, start, end, out)
            } catch (e: SocketException) {
                // Player closed the connection (seek or stop).
            } catch (e: IOException) {
                Log.d(TAG, "Client closed: ${e.message}")
            } catch (e: Throwable) {
                Log.w(TAG, "Serving failed", e)
            }
        }
    }

    private fun send(
        stream: TorrentStreamEngine.Stream,
        file: java.io.File,
        start: Long,
        end: Long,
        out: OutputStream,
    ) {
        val buffer = ByteArray(CHUNK)
        RandomAccessFile(file, "r").use { raf ->
            var pos = start
            while (pos <= end) {
                if (stream.stopped) return
                val piece = stream.pieceAt(pos)
                if (!stream.awaitPiece(piece)) return
                // Serve up to the end of this piece.
                val pieceEnd = (piece.toLong() + 1) * stream.pieceLength - stream.fileOffset - 1
                val until = minOf(end, pieceEnd)
                while (pos <= until) {
                    val n = minOf(buffer.size.toLong(), until - pos + 1).toInt()
                    raf.seek(pos)
                    val read = raf.read(buffer, 0, n)
                    if (read <= 0) return
                    out.write(buffer, 0, read)
                    pos += read
                }
            }
            out.flush()
        }
    }

    private fun respond(out: OutputStream, status: String, headers: Map<String, String>) {
        val sb = StringBuilder("HTTP/1.1 ").append(status).append("\r\n")
        headers.forEach { (k, v) -> sb.append(k).append(": ").append(v).append("\r\n") }
        if ("Content-Length" !in headers) sb.append("Content-Length: 0\r\n")
        sb.append("Connection: close\r\n\r\n")
        out.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
        out.flush()
    }

    private fun readLine(input: InputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val c = input.read()
            if (c == -1) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString().trimEnd('\r')
            sb.append(c.toChar())
            if (sb.length > 8192) return sb.toString()
        }
    }

    private fun mimeType(name: String) = when (name.substringAfterLast('.', "").lowercase()) {
        "mp4", "m4v" -> "video/mp4"
        "webm" -> "video/webm"
        "avi" -> "video/x-msvideo"
        "mov" -> "video/quicktime"
        "ts", "m2ts" -> "video/mp2t"
        else -> "video/x-matroska"
    }
}
