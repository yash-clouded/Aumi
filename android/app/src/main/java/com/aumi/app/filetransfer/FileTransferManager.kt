package com.aumi.app.filetransfer

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import java.io.OutputStream

/**
 * Handles incoming file transfers from the Mac and saves them to the Downloads/Aumi folder.
 * Uses Scoped Storage (MediaStore) to ensure compatibility with Android 10-14.
 */
class FileTransferManager(private val context: Context) {

    private var currentOutputStream: OutputStream? = null
    private var currentFileUri: Uri? = null

    /**
     * Initializes a new file receipt. Creates the file in MediaStore.
     */
    fun handleInit(fileName: String, fileSize: Long) {
        try {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Aumi")
            }

            val contentResolver = context.contentResolver
            currentFileUri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
            
            currentFileUri?.let { uri ->
                currentOutputStream = contentResolver.openOutputStream(uri)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Receives a chunk of data and writes it to the output stream.
     */
    fun handleChunk(dataBase64: String) {
        try {
            val data = Base64.decode(dataBase64, Base64.DEFAULT)
            currentOutputStream?.write(data)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Finalizes the file transfer. Closes the stream.
     */
    fun handleComplete() {
        try {
            currentOutputStream?.flush()
            currentOutputStream?.close()
            currentOutputStream = null
            currentFileUri = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
