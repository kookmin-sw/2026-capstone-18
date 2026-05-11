package com.littlesignals.app.inference

import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object TestZipBuilder {
    fun makeMinimalZipMissing(excluded: String): ByteArray {
        val all = mapOf(
            "ppg_green.csv" to "timestamp_ms,ppg_green\n1,1.0\n2,2.0\n",
            "eda.csv" to "timestamp_ms,skin_conductance\n1,5.0\n",
            "accel.csv" to "timestamp_ms,x,y,z\n1,0,0,9.8\n",
        )
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { zo ->
            for ((name, content) in all) {
                if (name == excluded) continue
                zo.putNextEntry(ZipEntry(name)); zo.write(content.toByteArray()); zo.closeEntry()
            }
        }
        return bos.toByteArray()
    }
}
