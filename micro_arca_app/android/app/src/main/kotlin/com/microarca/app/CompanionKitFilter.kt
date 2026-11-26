package com.microarca.app

import android.bluetooth.le.ScanFilter
import android.companion.BluetoothLeDeviceFilter
import android.os.Build
import android.os.ParcelUuid
import androidx.annotation.RequiresApi
import java.util.UUID
import java.util.regex.Pattern

@RequiresApi(26)
internal object CompanionKitFilter {
    private const val SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"

    fun create(): BluetoothLeDeviceFilter {
        val builder = BluetoothLeDeviceFilter.Builder()
        if (Build.VERSION.SDK_INT <= 29) {
            // Android 8–10 consulta BluetoothDevice.getUuids() (cache SDP),
            // não os UUIDs do anúncio BLE. Arrays.asList(null) derruba o CDM.
            // Sem UUID no ScanFilter, esse caminho é evitado; o nome é o
            // anunciado pelo firmware. Serviço/características e handshake
            // continuam sendo exigidos pelo transporte ao conectar.
            builder.setNamePattern(Pattern.compile("^ARCA-[0-9A-Fa-f]{6}$"))
        } else {
            builder.setScanFilter(
                ScanFilter.Builder().setServiceUuid(ParcelUuid(UUID.fromString(SERVICE))).build()
            )
        }
        return builder.build()
    }
}
