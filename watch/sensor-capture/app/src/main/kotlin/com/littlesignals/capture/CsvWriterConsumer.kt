package com.littlesignals.capture

import timber.log.Timber
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class CsvWriterConsumer(private val baseDir: File) : CaptureConsumer {
    private var captureDir: File? = null
    private val writers = mutableMapOf<Channel, BufferedWriter>()

    private fun fileName(channel: Channel): String = when (channel) {
        Channel.HR -> "heart_rate.csv"
        Channel.PPG -> "ppg_green.csv"
        Channel.EDA -> "eda.csv"
        Channel.ACCEL -> "accel.csv"
    }

    private fun header(channel: Channel): String = when (channel) {
        Channel.HR, Channel.PPG, Channel.EDA -> "timestamp_ms,value"
        Channel.ACCEL -> "timestamp_ms,x,y,z"
    }

    override fun onSessionStart(startedAtMs: Long, durationMs: Long) {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val dir = File(baseDir, fmt.format(Date(startedAtMs)))
        dir.mkdirs()
        captureDir = dir
        Channel.values().forEach { ch ->
            val w = File(dir, fileName(ch)).bufferedWriter()
            w.write(header(ch)); w.newLine(); w.flush()
            writers[ch] = w
        }
    }

    override fun onSample(channel: Channel, sample: Sample) {
        val w = writers[channel] ?: return
        val row = when (sample) {
            is Sample.Scalar -> "${sample.timestampMs},${sample.value}"
            is Sample.Vector -> "${sample.timestampMs}," + sample.values.joinToString(",")
        }
        try {
            w.write(row); w.newLine(); w.flush()
        } catch (t: Throwable) {
            Timber.w(t, "csv write failed for %s", channel)
        }
    }

    override fun onSessionEnd(reason: EndReason, error: String?) {
        writers.values.forEach { runCatching { it.flush(); it.close() } }
        writers.clear()
        val dir = captureDir ?: return
        captureDir = null
        if (reason == EndReason.COMPLETED || reason == EndReason.USER_STOPPED) {
            zipDirectory(dir)
        }
    }

    private fun zipDirectory(dir: File) {
        val zipFile = File(dir.parentFile, "${dir.name}.zip")
        ZipOutputStream(FileOutputStream(zipFile)).use { zos ->
            dir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    zos.putNextEntry(ZipEntry("${dir.name}/${file.name}"))
                    file.inputStream().use { it.copyTo(zos) }
                    zos.closeEntry()
                }
            }
        }
    }
}
