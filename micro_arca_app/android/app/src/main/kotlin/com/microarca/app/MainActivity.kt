package com.microarca.app

import androidx.annotation.RequiresApi
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
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothAdapter

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var pendingDocument: MethodChannel.Result? = null
    private val permissionRequest = 2301
    private val documentRequest = 2302
    private var companionPicker: CompanionKitPicker? = null
    private var pendingEnable: MethodChannel.Result? = null
    private var enableRequestCode = 0x2400

    private fun requestBluetoothEnable(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", "Permita o acesso ao Bluetooth para ativá-lo.", null)
            return
        }
        val adapter = getSystemService(BluetoothManager::class.java)?.adapter
        if (adapter == null) {
            result.error("unsupported", "Este celular não oferece Bluetooth.", null)
        } else if (adapter.isEnabled) {
            result.success(true)
        } else if (pendingEnable != null) {
            result.error("busy", "A ativação do Bluetooth já está em andamento.", null)
        } else {
            pendingEnable = result
            enableRequestCode = if (enableRequestCode == 0x42ff) 0x2400 else enableRequestCode + 1
            try {
                startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), enableRequestCode)
            } catch (error: Exception) {
                pendingEnable = null
                result.error("enable_failed", "Não foi possível solicitar a ativação do Bluetooth.", null)
            }
        }
    }

    private fun cancelBluetoothEnable() {
        val result = pendingEnable ?: return
        pendingEnable = null
        try { finishActivity(enableRequestCode) }
        finally { result.success(false) }
    }

    @RequiresApi(26)
    private fun picker(): CompanionKitPicker {
        check(Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)) {
            "Este Android não oferece seleção de dispositivos complementares."
        }
        return companionPicker ?: CompanionKitPicker(this).also { companionPicker = it }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arca/legal_documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") result.notImplemented()
                else {
                    val document = call.argument<String>("document")
                    if (document !in listOf("privacidade", "termos")) result.error("invalid_document", "Documento inválido.", null)
                    else try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://gabriel26077.github.io/microarca-site/$document/")))
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("open_failed", "Não foi possível abrir o navegador.", null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arca/companion_devices")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "mode" -> result.success(when {
                            Build.VERSION.SDK_INT < 26 -> "legacy"
                            packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP) -> "companion"
                            else -> "unavailable"
                        })
                        "adapterState" -> {
                            val adapter = getSystemService(BluetoothManager::class.java)?.adapter
                            result.success(when {
                                adapter == null -> "unsupported"
                                !adapter.isEnabled -> "poweredOff"
                                else -> "ready"
                            })
                        }
                        "requestEnable" -> requestBluetoothEnable(result)
                        "select" -> {
                            if (Build.VERSION.SDK_INT >= 26) picker().select(result)
                            else result.error("unsupported", "A seleção pelo Android requer Android 8 ou mais recente.", null)
                        }
                        "cancel" -> {
                            cancelBluetoothEnable()
                            if (Build.VERSION.SDK_INT >= 26) companionPicker?.cancel()
                            result.success(null)
                        }
                        "list" -> result.success(if (Build.VERSION.SDK_INT >= 26) picker().associations() else emptyList<Any>())
                        "isAssociated" -> {
                            result.success(Build.VERSION.SDK_INT >= 26 && picker().isAssociated(requireNotNull(call.argument<String>("id"))))
                        }
                        "forget" -> {
                            if (Build.VERSION.SDK_INT >= 26) {
                                picker().forget(requireNotNull(call.argument<String>("id")))
                                result.success(null)
                            } else result.error("unsupported", "Este Android não mantém associações de kits.", null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("companion_error", error.message ?: "Falha na seleção do kit pelo Android.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arca/bluetooth_permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Solicitação de permissão em andamento", null)
                } else {
                    val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        arrayOf(Manifest.permission.BLUETOOTH_CONNECT)
                    } else if (Build.VERSION.SDK_INT < 26) {
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
                    } else emptyArray()
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
        if (requestCode in 0x2400..0x42ff) {
            if (requestCode != enableRequestCode) return
            val result = pendingEnable ?: return
            pendingEnable = null
            val adapter = getSystemService(BluetoothManager::class.java)?.adapter
            try {
                result.success(resultCode == Activity.RESULT_OK && adapter?.isEnabled == true)
            } catch (_: SecurityException) {
                result.error("permission_denied", "Permita o acesso ao Bluetooth para continuar.", null)
            }
            return
        }
        if (Build.VERSION.SDK_INT >= 26 && CompanionKitPicker.handlesRequestCode(requestCode)) {
            companionPicker?.onActivityResult(requestCode, resultCode, data)
            return
        }
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

    override fun onDestroy() {
        cancelBluetoothEnable()
        if (Build.VERSION.SDK_INT >= 26) companionPicker?.cancel()
        pending?.error("activity_destroyed", "A tela de conexão foi encerrada.", null)
        pending = null
        super.onDestroy()
    }
}
