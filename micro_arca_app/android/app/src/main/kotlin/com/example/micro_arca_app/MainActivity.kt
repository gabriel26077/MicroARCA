package com.example.micro_arca_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val permissionRequest = 2301

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
