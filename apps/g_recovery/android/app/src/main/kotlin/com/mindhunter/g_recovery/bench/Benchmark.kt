package com.mindhunter.g_recovery.bench

import android.app.ActivityManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.display.DisplayManager
import android.view.Display
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.Deflater
import kotlin.math.exp
import kotlin.math.ln
import kotlin.random.Random

/**
 * The benchmark: processor on one core and on all of them, memory copy speed,
 * and storage write and read speed, measured on this phone in about a minute.
 *
 * Every category is scored against a reference so 1000 means "as fast as a
 * Galaxy S22". The raw rates come back too, so the references can be retuned
 * without touching the tests.
 *
 * Runs on its own thread. Progress streams to Flutter on the event channel so
 * the phone x-ray can light the part being tested; the final result answers
 * the `run` call.
 */
internal class Benchmark(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, METHODS)
    private val events = EventChannel(messenger, EVENTS)
    private var sink: EventChannel.EventSink? = null
    private val cancelled = AtomicBoolean(false)
    private val running = AtomicBoolean(false)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        cancelled.set(true)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "run" -> {
                if (!running.compareAndSet(false, true)) {
                    result.error("BUSY", "A test is already running", null)
                    return
                }
                cancelled.set(false)
                Thread({
                    val outcome = runCatching { runAll() }
                    running.set(false)
                    main.post {
                        outcome.fold(
                            onSuccess = { result.success(it) },
                            onFailure = {
                                if (it is Cancelled) {
                                    result.error("CANCELLED", "Stopped", null)
                                } else {
                                    result.error("FAILED", it.message, null)
                                }
                            },
                        )
                    }
                }, "benchmark").apply { priority = Thread.MAX_PRIORITY }.start()
            }
            "hardware" -> result.success(runCatching { hardware() }.getOrDefault(emptyMap()))
            "cancel" -> {
                cancelled.set(true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // What this phone is built from, for drawing its own skeleton
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Rear cameras, memory, storage and battery size as the phone reports
     * them. Anything it does not report is left out rather than guessed.
     */
    private fun hardware(): Map<String, Any?> {
        val memory = ActivityManager.MemoryInfo().also {
            (app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(it)
        }
        val data = StatFs(app.filesDir.absolutePath)
        return mapOf(
            "rearCameras" to rearCameras(),
            "ramBytes" to memory.totalMem,
            "storageBytes" to data.totalBytes,
            "batteryMah" to batteryCapacityMah(),
            "maxRefreshHz" to maxRefreshHz(),
        )
    }

    /**
     * Rear lenses, told apart by focal length. Phones that group their lenses
     * behind one logical camera list each lens as a physical camera, so those
     * are looked at too. Sorted so the main lens comes first.
     */
    private fun rearCameras(): List<Double> {
        val manager = app.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val focal = mutableSetOf<Double>()
        fun collect(id: String) {
            val c = runCatching { manager.getCameraCharacteristics(id) }.getOrNull() ?: return
            if (c.get(CameraCharacteristics.LENS_FACING) != CameraCharacteristics.LENS_FACING_BACK) return
            c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.forEach {
                focal += (it * 10).toInt() / 10.0
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                c.physicalCameraIds.forEach { collect(it) }
            }
        }
        manager.cameraIdList.forEach { collect(it) }
        return focal.sorted()
    }

    /**
     * The fastest refresh rate the screen supports. The current rate can sit
     * at 60 while the screen idles or a power saving mode is on.
     */
    private fun maxRefreshHz(): Double? {
        val display = (app.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
            .getDisplay(Display.DEFAULT_DISPLAY) ?: return null
        return display.supportedModes.maxOfOrNull { it.refreshRate.toDouble() }
    }

    /** Design capacity from the system's power profile; null if hidden. */
    private fun batteryCapacityMah(): Double? = runCatching {
        val type = Class.forName("com.android.internal.os.PowerProfile")
        val profile = type.getConstructor(Context::class.java).newInstance(app)
        (type.getMethod("getBatteryCapacity").invoke(profile) as Double).takeIf { it > 500 }
    }.getOrNull()

    // ─────────────────────────────────────────────────────────────────────
    // The run
    // ─────────────────────────────────────────────────────────────────────

    private class Cancelled : RuntimeException()

    private fun check() {
        if (cancelled.get()) throw Cancelled()
    }

    private fun emit(stage: String, progress: Double, live: Double, cores: Int = 0) {
        val event = mapOf(
            "stage" to stage,
            "progress" to progress,
            "live" to live,
            "cores" to cores,
        )
        main.post { sink?.success(event) }
    }

    private fun runAll(): Map<String, Any?> {
        val tempStart = batteryTemp()
        val threads = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)

        // Processor, one core: each workload for a fixed window.
        val singleRates = DoubleArray(WORKLOADS)
        for (w in 0 until WORKLOADS) {
            check()
            singleRates[w] = measure(w, 1) { done ->
                emit("single", 0.05 + 0.2 * (w + done) / WORKLOADS, scoreOf(singleRates, w, done, SINGLE_REF), 1)
            }
        }
        val single = categoryScore(singleRates, SINGLE_REF)

        // Processor, every core at once.
        val multiRates = DoubleArray(WORKLOADS)
        for (w in 0 until WORKLOADS) {
            check()
            multiRates[w] = measure(w, threads) { done ->
                emit("multi", 0.25 + 0.3 * (w + done) / WORKLOADS, scoreOf(multiRates, w, done, MULTI_REF), threads)
            }
        }
        val multi = categoryScore(multiRates, MULTI_REF)

        check()
        val memoryGbs = memoryCopy { done, gbs ->
            emit("memory", 0.55 + 0.15 * done, gbs / MEMORY_REF_GBS * 1000)
        }

        check()
        val writeMbs = storageWrite { done, mbs ->
            emit("storage", 0.7 + 0.2 * done, mbs / WRITE_REF_MBS * 1000)
        }
        check()
        val readMbs = storageRead { done, mbs ->
            emit("storage", 0.9 + 0.1 * done, mbs / READ_REF_MBS * 1000)
        }

        val memory = memoryGbs / MEMORY_REF_GBS * 1000
        val storage = if (readMbs != null) {
            geomean(doubleArrayOf(writeMbs / WRITE_REF_MBS, readMbs / READ_REF_MBS)) * 1000
        } else {
            writeMbs / WRITE_REF_MBS * 1000
        }
        val total = single * 0.3 + multi * 0.35 + memory * 0.15 + storage * 0.2

        emit("done", 1.0, total)
        return mapOf(
            "at" to System.currentTimeMillis(),
            "total" to total,
            "single" to single,
            "multi" to multi,
            "memory" to memory,
            "storage" to storage,
            "memoryGbs" to memoryGbs,
            "writeMbs" to writeMbs,
            "readMbs" to readMbs,
            "cores" to threads,
            "tempStart" to tempStart,
            "tempEnd" to batteryTemp(),
            "singleRaw" to singleRates.toList(),
            "multiRaw" to multiRates.toList(),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /** The score so far in a category, for the live number on screen. */
    private fun scoreOf(rates: DoubleArray, upTo: Int, done: Double, ref: DoubleArray): Double {
        if (upTo == 0 && done <= 0) return 0.0
        val known = (0 until upTo).map { rates[it] / ref[it] }
        return if (known.isEmpty()) 0.0 else geomean(known.toDoubleArray()) * 1000 * (0.9 + 0.1 * done)
    }

    private fun categoryScore(rates: DoubleArray, ref: DoubleArray): Double =
        geomean(DoubleArray(rates.size) { rates[it] / ref[it] }) * 1000

    private fun geomean(values: DoubleArray): Double {
        val logs = values.filter { it > 0 }.map { ln(it) }
        return if (logs.isEmpty()) 0.0 else exp(logs.average())
    }

    // ─────────────────────────────────────────────────────────────────────
    // Processor
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Runs workload [w] on [threads] threads for [WINDOW_MS] after a short
     * warm up, and returns units of work per second across all of them.
     */
    private fun measure(w: Int, threads: Int, tick: (Double) -> Unit): Double {
        val units = AtomicLong(0)
        val stop = AtomicBoolean(false)
        val started = CountDownLatch(threads)
        val finished = CountDownLatch(threads)
        val workers = (0 until threads).map {
            Thread {
                val job = workload(w)
                started.countDown()
                while (!stop.get()) {
                    job()
                    units.incrementAndGet()
                }
                finished.countDown()
            }.apply { priority = Thread.MAX_PRIORITY }
        }
        workers.forEach { it.start() }
        started.await()
        Thread.sleep(WARMUP_MS)
        // The window is split into slices and the median slice rate is kept,
        // so a moment of throttling or a background task does not swing it.
        val steps = 8
        val rates = DoubleArray(steps)
        var from = units.get()
        var t0 = System.nanoTime()
        repeat(steps) { i ->
            if (cancelled.get()) {
                stop.set(true)
                finished.await()
                throw Cancelled()
            }
            Thread.sleep(WINDOW_MS / steps)
            val now = System.nanoTime()
            val count = units.get()
            rates[i] = (count - from) / ((now - t0) / 1e9)
            from = count
            t0 = now
            tick((i + 1).toDouble() / steps)
        }
        stop.set(true)
        finished.await()
        rates.sort()
        return (rates[steps / 2 - 1] + rates[steps / 2]) / 2
    }

    /** One unit of each workload: hashing, compression, maths, sorting. */
    private fun workload(w: Int): () -> Unit = when (w) {
        0 -> {
            val digest = MessageDigest.getInstance("SHA-256")
            val block = ByteArray(64 * 1024).also { Random(1).nextBytes(it) }
            ({ digest.update(block); digest.digest(); Unit })
        }
        1 -> {
            val text = buildString { repeat(4000) { append("the quick brown fox ").append(it % 97) } }
                .toByteArray()
            val out = ByteArray(text.size + 1024)
            ({
                val d = Deflater(6)
                d.setInput(text)
                d.finish()
                while (!d.finished()) d.deflate(out)
                d.end()
            })
        }
        2 -> {
            val n = 48
            val a = DoubleArray(n * n) { (it % 13) * 0.5 }
            val b = DoubleArray(n * n) { (it % 7) * 0.25 }
            val c = DoubleArray(n * n)
            ({
                for (i in 0 until n) for (j in 0 until n) {
                    var s = 0.0
                    for (k in 0 until n) s += a[i * n + k] * b[k * n + j]
                    c[i * n + j] = s
                }
            })
        }
        else -> {
            val source = IntArray(8192).also { arr -> val r = Random(2); for (i in arr.indices) arr[i] = r.nextInt() }
            val work = IntArray(source.size)
            ({ System.arraycopy(source, 0, work, 0, source.size); work.sort() })
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Memory
    // ─────────────────────────────────────────────────────────────────────

    /** Copies one 32 MB block into another for a second; returns GB/s. */
    private fun memoryCopy(tick: (Double, Double) -> Unit): Double {
        val size = 32 * 1024 * 1024
        val from = ByteArray(size).also { it.fill(7) }
        val to = ByteArray(size)
        repeat(2) { System.arraycopy(from, 0, to, 0, size) }
        var copied = 0L
        val t0 = System.nanoTime()
        val deadline = t0 + 1_500_000_000L
        var lastTick = t0
        while (System.nanoTime() < deadline) {
            check()
            System.arraycopy(from, 0, to, 0, size)
            copied += size
            val now = System.nanoTime()
            if (now - lastTick > 200_000_000L) {
                lastTick = now
                tick((now - t0) / 1.5e9, copied / ((now - t0) / 1e9) / 1e9)
            }
        }
        return copied / ((System.nanoTime() - t0) / 1e9) / 1e9
    }

    // ─────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Writes four test files in 4 MB blocks, each synced to the chip and
     * timed on its own, then deletes them. The middle two speeds are kept,
     * since one pass can land in the chip's fast cache or behind a cleanup
     * it runs in the background. Sized down when the phone is short of space.
     */
    private fun storageWrite(tick: (Double, Double) -> Unit): Double {
        val dir = app.cacheDir
        val free = dir.usableSpace
        val total = when {
            free > 2L * 1024 * 1024 * 1024 -> 256L * 1024 * 1024
            free > 512L * 1024 * 1024 -> 128L * 1024 * 1024
            else -> 32L * 1024 * 1024
        }
        val passes = 4
        val perPass = total / passes
        val block = ByteArray(4 * 1024 * 1024).also { Random(3).nextBytes(it) }
        val speeds = DoubleArray(passes)
        for (p in 0 until passes) {
            val file = File(dir, "bench$p.tmp")
            try {
                val t0 = System.nanoTime()
                FileOutputStream(file).use { out ->
                    var written = 0L
                    while (written < perPass) {
                        check()
                        out.write(block)
                        written += block.size
                        val secs = (System.nanoTime() - t0) / 1e9
                        tick((p * perPass + written).toDouble() / total, written / secs / 1e6)
                    }
                    out.fd.sync()
                }
                speeds[p] = perPass / ((System.nanoTime() - t0) / 1e9) / 1e6
            } finally {
                file.delete()
            }
        }
        speeds.sort()
        return (speeds[1] + speeds[2]) / 2
    }

    /**
     * Reads the largest video already on the phone, which is not sitting in
     * the page cache the way a file this test just wrote would be. Nothing is
     * changed. Null when there is no video big enough to time.
     */
    private fun storageRead(tick: (Double, Double) -> Unit): Double? {
        val collection = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val id = runCatching {
            app.contentResolver.query(
                collection,
                arrayOf(MediaStore.Video.Media._ID, MediaStore.Video.Media.SIZE),
                "${MediaStore.Video.Media.SIZE} >= ?",
                arrayOf((64L * 1024 * 1024).toString()),
                "${MediaStore.Video.Media.SIZE} DESC",
            )?.use { if (it.moveToFirst()) it.getLong(0) else null }
        }.getOrNull() ?: return null

        val uri = ContentUris.withAppendedId(collection, id)
        val limit = 256L * 1024 * 1024
        val buffer = ByteArray(4 * 1024 * 1024)
        return runCatching {
            app.contentResolver.openInputStream(uri)?.use { input ->
                var read = 0L
                val t0 = System.nanoTime()
                while (read < limit) {
                    check()
                    val n = input.read(buffer)
                    if (n <= 0) break
                    read += n
                    val secs = (System.nanoTime() - t0) / 1e9
                    tick(read.toDouble() / limit, read / secs / 1e6)
                }
                if (read < 32L * 1024 * 1024) null else read / ((System.nanoTime() - t0) / 1e9) / 1e6
            }
        }.getOrNull()
    }

    private fun batteryTemp(): Double? {
        val status = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val tenths = status?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            ?: return null
        return if (tenths == Int.MIN_VALUE) null else tenths / 10.0
    }

    companion object {
        const val METHODS = "g_recovery/benchmark"
        const val EVENTS = "g_recovery/benchmark/progress"

        private const val WORKLOADS = 4
        private const val WARMUP_MS = 600L
        private const val WINDOW_MS = 2_400L

        /**
         * Units per second a Galaxy S22 reaches, so it scores 1000. Measured
         * on a Galaxy S22+ (same chip) on 20 Nov 2026: the median of three
         * processor and memory runs and five storage runs, as storage swings
         * with the chip's cache. Read has no
         * measured reference yet: it only counts when a large video exists.
         */
        private val SINGLE_REF = doubleArrayOf(19_180.0, 1_507.0, 12_330.0, 2_055.0)
        private val MULTI_REF = doubleArrayOf(52_810.0, 4_143.0, 33_960.0, 5_654.0)
        private const val MEMORY_REF_GBS = 14.6
        private const val WRITE_REF_MBS = 260.0
        private const val READ_REF_MBS = 1_200.0
    }
}
