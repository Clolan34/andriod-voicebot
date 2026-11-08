package org.studyforge.studyforge

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** All context access is serialized; only the atomic stop flag crosses threads. */
class LocalAiBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "org.studyforge/local_ai")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val lifetimeLock = Any()
    @Volatile private var handle = 0L
    @Volatile private var owner = 0
    private var nativeLoaded = false

    init { channel.setMethodCallHandler(this) }

    private fun requestStop(session: Int? = null) = synchronized(lifetimeLock) {
        if (handle != 0L && (session == null || owner == session)) nativeStop(handle)
    }

    private fun release(session: Int? = null) = synchronized(lifetimeLock) {
        if (handle != 0L && (session == null || owner == session)) {
            nativeFree(handle)
            handle = 0L
            owner = 0
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val session = call.argument<Int>("session") ?: 0
        if (call.method == "stop") {
            requestStop(session)
            result.success(null)
            return
        }
        if (call.method !in setOf("load", "tokenCount", "generate", "close")) {
            result.notImplemented()
            return
        }
        if (call.method == "generate") synchronized(lifetimeLock) {
            if (handle != 0L && owner == session) nativeResetStop(handle)
        }
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "load" -> {
                        if (!nativeLoaded) {
                            System.loadLibrary("studyforge_ai")
                            nativeLoaded = true
                        }
                        val path = requireNotNull(call.argument<String>("path"))
                        release()
                        val loaded = nativeLoad(path)
                        check(loaded != 0L) { "Model could not be loaded" }
                        synchronized(lifetimeLock) { handle = loaded; owner = session }
                        null
                    }
                    "tokenCount" -> {
                        check(handle != 0L && owner == session) { "Load the model first" }
                        nativeTokenCount(handle, requireNotNull(call.argument<String>("prompt")).toByteArray(Charsets.UTF_8))
                    }
                    "generate" -> {
                        check(handle != 0L && owner == session) { "Load the model first" }
                        String(nativeGenerate(handle,
                            requireNotNull(call.argument<String>("prompt")).toByteArray(Charsets.UTF_8)), Charsets.UTF_8)
                    }
                    else -> { release(session); null }
                }
                main.post { result.success(value) }
            } catch (_: Throwable) {
                // Do not send study text, filesystem paths or native errors to logs.
                main.post { result.error("local_ai", "Local AI operation failed on this device", null) }
            }
        }
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        requestStop()
        worker.execute { release() }
        worker.shutdown()
    }

    private external fun nativeLoad(path: String): Long
    private external fun nativeTokenCount(handle: Long, prompt: ByteArray): Int
    private external fun nativeGenerate(handle: Long, prompt: ByteArray): ByteArray
    private external fun nativeResetStop(handle: Long)
    private external fun nativeStop(handle: Long)
    private external fun nativeFree(handle: Long)
}
