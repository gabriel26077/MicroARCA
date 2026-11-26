package com.microarca.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.companion.BluetoothLeDeviceFilter
import android.os.ParcelUuid
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.lang.reflect.InvocationTargetException
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27, 29], manifest = Config.NONE)
class CompanionKitFilterTest {
    private val service = ParcelUuid(UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e"))

    @Suppress("DEPRECATION")
    private fun advertisement(name: String, withService: Boolean): ScanResult {
        val device = BluetoothAdapter.getDefaultAdapter().getRemoteDevice("02:00:00:00:00:01")
        shadowOf(device).setName(name)
        shadowOf(device).setUuids(null) // Estado que disparou o crash no Samsung.
        val bytes = if (withService) byteArrayOf(
            0x02, 0x01, 0x06, 0x11, 0x07,
            0x9e.toByte(), 0xca.toByte(), 0xdc.toByte(), 0x24, 0x0e, 0xe5.toByte(),
            0xa9.toByte(), 0xe0.toByte(), 0x93.toByte(), 0xf3.toByte(), 0xa3.toByte(),
            0xb5.toByte(), 0x01, 0x00, 0x40, 0x6e
        ) else byteArrayOf(0x02, 0x01, 0x06)
        val record = ScanRecord::class.java.getDeclaredMethod("parseFromBytes", ByteArray::class.java)
            .invoke(null, bytes) as ScanRecord
        if (withService) assertEquals("UUID anunciado", listOf(service), record.serviceUuids)
        return ScanResult(device, record, -40, 0L)
    }

    private fun matches(filter: BluetoothLeDeviceFilter, result: ScanResult): Boolean =
        filter.javaClass.getMethod("matches", ScanResult::class.java).invoke(filter, result) as Boolean

    @Test
    fun kitSemCacheDeUuidsPodeSerSelecionado() {
        assertTrue(matches(CompanionKitFilter.create(), advertisement("ARCA-ABC123", true)))
    }

    @Test
    fun dispositivoForaDoFiltroNaoAparece() {
        assertFalse(matches(CompanionKitFilter.create(), advertisement("Fone Bluetooth", false)))
    }

    @Test
    @Config(sdk = [27])
    fun filtroAnteriorReproduzNullPointerDoRelatorio() {
        val oldFilter = BluetoothLeDeviceFilter.Builder().setScanFilter(
            ScanFilter.Builder().setServiceUuid(service).build()
        ).build()
        try {
            matches(oldFilter, advertisement("ARCA-ABC123", true))
            fail("O framework antigo deve reproduzir o crash com cache UUID nulo")
        } catch (error: InvocationTargetException) {
            assertTrue(error.cause is NullPointerException)
        }
    }

    @Test
    @Config(sdk = [30])
    fun android11ContinuaExigindoUuidDoServicoNoAnuncio() {
        val filter = CompanionKitFilter.create()
        val scanFilter = filter.javaClass.getMethod("getScanFilter").invoke(filter) as ScanFilter
        assertEquals(service, scanFilter.serviceUuid)
        // O android-all 11 do Robolectric ainda contém o matcher CDM antigo;
        // aqui verificamos o ScanFilter de anúncio mantido pelo app moderno.
        assertFalse(scanFilter.matches(advertisement("ARCA-ABC123", false)))
        assertTrue(scanFilter.matches(advertisement("Outro nome", true)))
    }
}
