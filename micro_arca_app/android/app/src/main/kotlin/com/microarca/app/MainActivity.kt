package com.microarca.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingDocument: MethodChannel.Result? = null
    private val permissionRequest = 2301
    private val documentRequest = 2302

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arca/bluetooth_permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Solicitação de permissão em andamento", null)
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    result.success(true)
                } else {
                    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
                    } else {
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
                    }
                    val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else {
                        pending = result
                        requestPermissions(missing.toTypedArray(), permissionRequest)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arca/document_picker")
            .setMethodCallHandler { call, result ->
                if (call.method != "pickPython") {
                    result.notImplemented()
                } else if (pendingDocument != null) {
                    result.error("busy", "Já existe uma seleção de arquivo em andamento.", null)
                } else {
                    pendingDocument = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf("text/x-python", "text/plain", "application/octet-stream")
                        )
                    }
                    startActivityForResult(intent, documentRequest)
                }
            }
    }

    @Deprecated("Compatibilidade com a FlutterActivity atual")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != documentRequest) return
        val result = pendingDocument
        pendingDocument = null
        if (result == null) return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size() + count > 65536) {
                        throw IllegalArgumentException("A biblioteca deve ter no máximo 64 KiB.")
                    }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: throw IllegalArgumentException("Não foi possível abrir o arquivo.")
            result.success(mapOf("name" to displayName(uri), "bytes" to bytes))
        } catch (error: Exception) {
            result.error("read_error", error.message ?: "Falha ao ler o arquivo.", null)
        }
    }

    private fun displayName(uri: Uri): String {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        } finally {
            cursor?.close()
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "biblioteca.py"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequest) {
            val result = pending
            pending = null
            result?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        }
    }
}
