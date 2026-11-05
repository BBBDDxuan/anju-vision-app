package com.eldersafety.elder_safety_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.Proxy
import java.net.URI
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.zip.ZipFile

/** Activity-owned updater. Credentials are used only for one request, never persisted. */
class AppUpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "elder_safety/app_updates")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val connectionLock = Any()
    private val directory = File(activity.cacheDir, "updates")
    @Volatile private var generation = 0L
    @Volatile private var closed = false
    private var connection: Pair<Download, HttpURLConnection>? = null
    // These fields and all MethodChannel replies belong to the main thread.
    private var downloading: Download? = null
    private var prepared: Prepared? = null
    private var installing: MethodChannel.Result? = null

    private data class Metadata(
        val versionName: String, val versionCode: Long, val packageName: String,
        val abi: String, val size: Long, val sha256: String
    )
    private class Download(
        val generation: Long, val metadata: Metadata, val part: File, val apk: File,
        val result: MethodChannel.Result
    ) {
        var replied = false
        var progressAt = -1L
        var progressReceived = -1L
    }
    private data class Prepared(val file: File, val metadata: Metadata)
    private class Failure(val errorCode: String, val safeMessage: String) : Exception()

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("UPDATER_CLOSED", "Updater is closed", null)
            return
        }
        try {
            when (call.method) {
                "info" -> {
                    val installed = installedPackage()
                    result.success(mapOf(
                        "version_name" to (installed.versionName ?: ""),
                        "version_code" to versionCode(installed),
                        "package_name" to activity.packageName,
                        "abis" to Build.SUPPORTED_ABIS.toList(),
                        "can_install" to canInstall()
                    ))
                }
                "download" -> download(call, result)
                "cancel" -> { cancelCurrent(); result.success(null) }
                "discard" -> { cancelCurrent(); clearPrepared(); result.success(null) }
                "install" -> install(result)
                else -> result.notImplemented()
            }
        } catch (e: Failure) {
            result.error(e.errorCode, e.safeMessage, null)
        } catch (_: Exception) {
            // Exception text can contain a URL/header/token; never return it to Dart or logs.
            result.error("UPDATE_FAILED", "Unable to process update request", null)
        }
    }

    private fun download(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: fail("INVALID_ARGUMENT", "Invalid update arguments")
        fun text(key: String): String = args[key] as? String
            ?: fail("INVALID_ARGUMENT", "Missing update field")
        fun integer(key: String): Long = when (val value = args[key]) {
            is Long -> value
            is Int -> value.toLong()
            else -> fail("INVALID_ARGUMENT", "Invalid numeric update field")
        }
        val hash = text("sha256").lowercase(Locale.ROOT)
        if (!hash.matches(Regex("[0-9a-f]{64}"))) fail("INVALID_ARGUMENT", "Invalid update hash")
        val metadata = Metadata(text("version_name"), integer("version_code"), text("package_name"),
            text("abi"), integer("size_bytes"), hash)
        if (metadata.versionName.isBlank() || metadata.versionName.length > 256 ||
            metadata.size !in 1L..MAX_APK_BYTES || metadata.versionCode <= 0L) {
            fail("INVALID_ARGUMENT", "Invalid update metadata")
        }
        if (metadata.packageName != activity.packageName) fail("INVALID_PACKAGE", "Update package differs from installed app")
        if (metadata.abi !in Build.SUPPORTED_ABIS) fail("UNSUPPORTED_ABI", "Update ABI is unsupported")
        if (metadata.versionCode <= versionCode(installedPackage())) fail("INVALID_VERSION", "Update must be newer than installed app")
        val url = validatedUrl(text("base_url"), text("download_path"), hash)
        val token = text("bearer_token")
        if (token.isEmpty() || token.length > 8192 || token.any { it.code <= 32 || it.code >= 127 }) {
            fail("INVALID_ARGUMENT", "Invalid bearer token")
        }
        cancelCurrent()
        clearPrepared()
        val id = UUID.randomUUID().toString()
        val job = Download(generation, metadata, File(directory, "$id.part"), File(directory, "$id.apk"), result)
        downloading = job
        executor.execute { runDownload(job, url, token) }
    }

    private fun validatedUrl(base: String, path: String, hash: String): URI {
        if (base.length > 2048) fail("INVALID_URL", "Invalid update origin")
        val uri = try { URI(base) } catch (_: Exception) { fail("INVALID_URL", "Invalid update origin") }
        if (uri.scheme !in setOf("http", "https") || uri.host.isNullOrEmpty() ||
            uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null ||
            uri.rawPath.orEmpty() !in setOf("", "/") || uri.port < -1 || uri.port == 0 || uri.port > 65535) {
            fail("INVALID_URL", "Invalid update origin")
        }
        val host = uri.host.removePrefix("[").removeSuffix("]").lowercase(Locale.ROOT)
        if (uri.scheme == "http" && !privateHttpHost(host)) {
            fail("INVALID_URL", "HTTP updates require a private or loopback address")
        }
        if (path != "/api/app/apk/$hash") fail("INVALID_URL", "Invalid update download path")
        // A fixed absolute path retains the validated scheme/host/port, never a caller URL.
        return uri.resolve(path)
    }

    private fun privateHttpHost(host: String): Boolean {
        if (host == "localhost" || host == "::1") return true
        val parts = host.split('.')
        if (parts.size != 4 || parts.any { !it.matches(Regex("0|[1-9][0-9]{0,2}")) }) return false
        val octets = parts.map { it.toInt() }
        if (octets.any { it !in 0..255 }) return false
        return octets[0] == 10 || octets[0] == 127 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1] in 16..31)
    }

    private fun runDownload(job: Download, uri: URI, token: String) {
        var http: HttpURLConnection? = null
        var keepApk = false
        try {
            checkCurrent(job.generation)
            if (!directory.isDirectory && !directory.mkdirs()) fail("CACHE_UNAVAILABLE", "Update cache is unavailable")
            // localhost must still resolve only to loopback before sending credentials.
            if (uri.scheme == "http" && uri.host.equals("localhost", ignoreCase = true)) {
                if (InetAddress.getAllByName("localhost").any { !it.isLoopbackAddress }) {
                    fail("INVALID_URL", "Invalid loopback update origin")
                }
            }
            checkCurrent(job.generation)
            // Never send private HTTP credentials through a configured HTTP proxy.
            val request = uri.toURL().openConnection(Proxy.NO_PROXY) as HttpURLConnection
            http = request
            request.instanceFollowRedirects = false
            request.connectTimeout = 15_000
            request.readTimeout = 15_000
            request.useCaches = false
            request.requestMethod = "GET"
            request.setRequestProperty("Authorization", "Bearer $token")
            request.setRequestProperty("Accept", "application/vnd.android.package-archive")
            request.setRequestProperty("Accept-Encoding", "identity")
            synchronized(connectionLock) {
                checkCurrent(job.generation)
                connection = job to request
            }
            if (request.responseCode != HttpURLConnection.HTTP_OK) fail("DOWNLOAD_HTTP_ERROR", "Update server rejected download")
            checkCurrent(job.generation)
            val encoding = request.getHeaderField("Content-Encoding")
            if (encoding != null && !encoding.equals("identity", ignoreCase = true)) {
                fail("INVALID_DOWNLOAD", "Encoded APK responses are unsupported")
            }
            val length = request.getHeaderField("Content-Length")
            if (length != null && length.toLongOrNull() != job.metadata.size) {
                fail("SIZE_MISMATCH", "APK size differs from expected size")
            }
            val digest = MessageDigest.getInstance("SHA-256")
            var received = 0L
            var lastProgress = SystemClock.elapsedRealtime()
            progress(job, 0L)
            request.inputStream.use { input ->
                job.part.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkCurrent(job.generation)
                        val count = input.read(buffer)
                        if (count == -1) break
                        if (received + count > job.metadata.size) fail("SIZE_MISMATCH", "APK exceeds expected size")
                        checkCurrent(job.generation)
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        received += count
                        val now = SystemClock.elapsedRealtime()
                        if (now - lastProgress >= 200L) {
                            progress(job, received)
                            lastProgress = now
                        }
                    }
                    output.fd.sync()
                }
            }
            if (received != job.metadata.size) fail("SIZE_MISMATCH", "APK download is incomplete")
            if (hex(digest.digest()) != job.metadata.sha256) fail("HASH_MISMATCH", "APK hash differs from expected hash")
            checkCurrent(job.generation)
            if (!job.part.renameTo(job.apk)) fail("CACHE_UNAVAILABLE", "Unable to prepare APK cache")
            // Recheck bytes and archive metadata before declaring ready.
            verify(Prepared(job.apk, job.metadata), job.generation)
            checkCurrent(job.generation)
            keepApk = true
            main.post {
                if (!closed && generation == job.generation && downloading === job && !job.replied) {
                    emitProgress(job, job.metadata.size)
                    prepared = Prepared(job.apk, job.metadata)
                    downloading = null
                    job.replied = true
                    job.result.success(mapOf("ready" to true))
                } else {
                    job.apk.delete()
                }
            }
        } catch (e: Exception) {
            val cancelled = closed || generation != job.generation
            val failure = if (cancelled) Failure("DOWNLOAD_CANCELLED", "Update download cancelled")
                else if (e is Failure) e else Failure("DOWNLOAD_FAILED", "Unable to download or verify APK")
            main.post {
                if (!job.replied) {
                    job.replied = true
                    if (downloading === job) downloading = null
                    job.result.error(failure.errorCode, failure.safeMessage, null)
                }
            }
        } finally {
            disconnect(http)
            synchronized(connectionLock) {
                if (connection?.first === job) connection = null
            }
            job.part.delete()
            if (!keepApk) job.apk.delete()
        }
    }

    private fun progress(job: Download, received: Long) {
        main.post {
            // Report the terminal count only after verification, not merely the final socket read.
            if (received < job.metadata.size) emitProgress(job, received)
        }
    }

    private fun emitProgress(job: Download, received: Long) {
        if (closed || generation != job.generation || downloading !== job || job.replied) return
        val now = SystemClock.elapsedRealtime()
        if (received == job.progressReceived ||
            (received != job.metadata.size && job.progressAt >= 0L && now - job.progressAt < 200L)) return
        job.progressAt = now
        job.progressReceived = received
        channel.invokeMethod("downloadProgress", mapOf(
            "received" to received, "total" to job.metadata.size, "sha256" to job.metadata.sha256
        ))
    }

    /** Main thread: invalidate first, disconnect now, touch only the old job's unique files. */
    private fun cancelCurrent() {
        val oldConnection = synchronized(connectionLock) {
            generation++
            val active = connection?.second
            connection = null
            active
        }
        disconnect(oldConnection)
        val old = downloading
        downloading = null
        if (old != null) {
            old.part.delete()
            old.apk.delete()
            if (!old.replied) {
                old.replied = true
                old.result.error("DOWNLOAD_CANCELLED", "Update download cancelled", null)
            }
        }
        installing?.error("DOWNLOAD_CANCELLED", "Update operation cancelled", null)
        installing = null
    }

    private fun clearPrepared() {
        prepared?.file?.delete()
        prepared = null
    }

    private fun install(result: MethodChannel.Result) {
        if (downloading != null || installing != null) fail("UPDATE_BUSY", "Another update operation is in progress")
        val candidate = prepared ?: fail("UPDATE_NOT_READY", "Download an update before installing")
        val expectedGeneration = generation
        installing = result
        executor.execute {
            try {
                // Hash, current installed version/signer, minSDK and ABI are rechecked on every press.
                verify(candidate, expectedGeneration)
                main.post {
                    if (closed || generation != expectedGeneration || installing !== result || prepared !== candidate) return@post
                    installing = null
                    try {
                        if (!canInstall()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.fromParts("package", activity.packageName, null)))
                            result.success(mapOf("status" to "permission_required"))
                        } else {
                            val content = FileProvider.getUriForFile(activity,
                                activity.packageName + ".app_updates", candidate.file)
                            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(content,
                                "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            // ClipData also propagates the read grant to package installers.
                            intent.clipData = android.content.ClipData.newRawUri("APK update", content)
                            activity.startActivity(intent)
                            result.success(mapOf("status" to "installer_opened"))
                        }
                    } catch (_: Exception) {
                        result.error("INSTALL_UNAVAILABLE", "Unable to open Android installer or install settings", null)
                    }
                }
            } catch (e: Exception) {
                main.post {
                    if (installing !== result) return@post
                    installing = null
                    if (prepared === candidate) clearPrepared()
                    val failure = if (e is Failure) e else Failure("INVALID_APK", "Unable to verify cached APK")
                    result.error(failure.errorCode, failure.safeMessage, null)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun verify(candidate: Prepared, expectedGeneration: Long) {
        checkCurrent(expectedGeneration)
        val file = candidate.file
        val metadata = candidate.metadata
        if (file.canonicalFile.parentFile != directory.canonicalFile || !file.isFile || file.length() != metadata.size ||
            metadata.size !in 1L..MAX_APK_BYTES) fail("SIZE_MISMATCH", "Cached APK size is invalid")
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                checkCurrent(expectedGeneration)
                val count = input.read(buffer)
                if (count == -1) break
                digest.update(buffer, 0, count)
            }
        }
        if (hex(digest.digest()) != metadata.sha256) fail("HASH_MISMATCH", "Cached APK hash is invalid")
        checkCurrent(expectedGeneration)
        val installed = installedPackage()
        val archive = activity.packageManager.getPackageArchiveInfo(file.absolutePath, signatureFlags())
            ?: fail("INVALID_APK", "Unable to read APK package or signatures")
        if (metadata.packageName != activity.packageName || archive.packageName != activity.packageName) {
            fail("INVALID_PACKAGE", "APK package differs from installed app")
        }
        if (versionCode(archive) != metadata.versionCode || archive.versionName != metadata.versionName ||
            versionCode(archive) <= versionCode(installed)) {
            fail("INVALID_VERSION", "APK version differs from expected version or is not newer")
        }
        // Trust only exact CURRENT installed signers, never server metadata or signing history.
        if (signers(archive) != signers(installed)) fail("SIGNATURE_MISMATCH", "APK signer differs from installed app")
        val application = archive.applicationInfo ?: fail("INVALID_APK", "APK application metadata is missing")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            fail("UNSUPPORTED_ANDROID", "APK minSDK verification requires Android 7 or newer")
        }
        if (application.minSdkVersion > Build.VERSION.SDK_INT) fail("UNSUPPORTED_ANDROID", "APK requires a newer Android version")
        if (metadata.abi !in Build.SUPPORTED_ABIS) fail("UNSUPPORTED_ABI", "APK ABI is unsupported")
        ZipFile(file).use { zip ->
            var matchesAbi = false
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                checkCurrent(expectedGeneration)
                val entry = entries.nextElement()
                if (entry.isDirectory || !entry.name.startsWith("lib/")) continue
                val segments = entry.name.split('/')
                if (segments.size != 3 || segments.any { it.isEmpty() || it == "." || it == ".." }) {
                    fail("INVALID_APK", "Invalid APK native library path")
                }
                if (segments[2].endsWith(".so") && segments[1] == metadata.abi && entry.size > 0) matchesAbi = true
            }
            // This Flutter app always has native libraries; reject metadata-only ABI claims.
            if (!matchesAbi) fail("UNSUPPORTED_ABI", "APK does not contain libraries for the expected ABI")
        }
        checkCurrent(expectedGeneration)
    }

    @Suppress("DEPRECATION")
    private fun installedPackage(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, signatureFlags())

    @Suppress("DEPRECATION")
    private fun signatureFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            info.signingInfo?.apkContentsSigners else info.signatures
        if (signatures.isNullOrEmpty()) fail("SIGNATURE_MISMATCH", "APK signing certificates are unavailable")
        return signatures.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        info.longVersionCode else info.versionCode.toLong()

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
        activity.packageManager.canRequestPackageInstalls()

    private fun checkCurrent(expectedGeneration: Long) {
        if (closed || generation != expectedGeneration || Thread.currentThread().isInterrupted) {
            fail("DOWNLOAD_CANCELLED", "Update operation cancelled")
        }
    }

    private fun disconnect(http: HttpURLConnection?) {
        try { http?.disconnect() } catch (_: Exception) { /* Still complete cancellation and cleanup. */ }
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    private fun fail(code: String, message: String): Nothing = throw Failure(code, message)

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        cancelCurrent()
        clearPrepared()
        executor.shutdownNow()
    }

    companion object {
        private const val MAX_APK_BYTES = 256L * 1024L * 1024L
    }
}
