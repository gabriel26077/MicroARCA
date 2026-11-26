package com.microarca.app

import android.annotation.SuppressLint
import androidx.annotation.RequiresApi
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanResult
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.CompanionDeviceManager
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Seleção e associações do sistema; não faz scan BLE próprio nem cria bond. */
@RequiresApi(26)
class CompanionKitPicker(private val activity: Activity) {
    companion object {
        private const val FIRST_REQUEST = 0x4300
        private const val LAST_REQUEST = 0x7fff
        fun handlesRequestCode(code: Int) = code in FIRST_REQUEST..LAST_REQUEST
    }

    private val manager get() = activity.getSystemService(CompanionDeviceManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private class Selection(val result: MethodChannel.Result, val previousIds: Set<Int>, val requestCode: Int) {
        var accepted = false
        var confirmation: AssociationConfirmation? = null
    }
    private var pending: Selection? = null
    private var nextRequestCode = FIRST_REQUEST

    @Suppress("DEPRECATION")
    fun associations(): List<Map<String, String>> = if (Build.VERSION.SDK_INT >= 33) {
        manager.myAssociations.mapNotNull { association ->
            association.deviceMacAddress?.toString()?.let { id ->
                mapOf("id" to id, "name" to (association.displayName?.toString() ?: "Kit ARCA"))
            }
        }.distinctBy { it["id"] }
    } else {
        manager.associations.map { mapOf("id" to it, "name" to "Kit ARCA") }
    }

    fun isAssociated(address: String): Boolean =
        associations().any { it["id"].equals(address, ignoreCase = true) }

    @Suppress("DEPRECATION")
    fun forget(address: String) {
        if (Build.VERSION.SDK_INT >= 33) {
            manager.myAssociations.filter {
                it.deviceMacAddress?.toString().equals(address, ignoreCase = true)
            }.forEach { manager.disassociate(it.id) }
        } else if (isAssociated(address)) {
            manager.disassociate(address)
        }
    }

    @Suppress("DEPRECATION")
    fun select(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Já existe uma seleção de kit em andamento.", null)
            return
        }
        val previous = if (Build.VERSION.SDK_INT >= 33) manager.myAssociations.map { it.id }.toSet() else emptySet()
        val selection = Selection(result, previous, nextRequestCode)
        nextRequestCode = if (nextRequestCode == LAST_REQUEST) FIRST_REQUEST else nextRequestCode + 1
        pending = selection
        val filter = CompanionKitFilter.create()
        val request = AssociationRequest.Builder().addDeviceFilter(filter).setSingleDevice(false).build()
        val callback = object : CompanionDeviceManager.Callback() {
            override fun onDeviceFound(chooserLauncher: IntentSender) = showChooser(selection, chooserLauncher)
            override fun onAssociationPending(intentSender: IntentSender) = showChooser(selection, intentSender)
            override fun onAssociationCreated(associationInfo: AssociationInfo) {
                try {
                    acceptAssociation(selection, associationInfo)
                } catch (error: Exception) {
                    fail(selection, "selection_failed", error.message ?: "Falha ao confirmar o kit.")
                }
            }
            override fun onFailure(error: CharSequence?) {
                // Alguns Androids entregam a recusa antes de onActivityResult.
                if (pending !== selection) return
                if (error?.toString() == "user_rejected") cancel()
                else fail(selection, "selection_failed", "Nenhum kit selecionado. Confira se a placa está ligada e se o Bluetooth e a localização do Android estão ativados.")
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                manager.associate(request, activity.mainExecutor, callback)
            } else {
                manager.associate(request, callback, handler)
            }
        } catch (error: Exception) {
            fail(selection, "selection_failed", error.message ?: "Não foi possível abrir a seleção do Android.")
        }
    }

    private fun showChooser(selection: Selection, sender: IntentSender) {
        if (pending !== selection) return
        try {
            activity.startIntentSenderForResult(sender, selection.requestCode, null, 0, 0, 0)
        } catch (error: Exception) {
            fail(selection, "selection_failed", error.message ?: "Não foi possível abrir a seleção do Android.")
        }
    }

    private fun fail(selection: Selection, code: String, message: String) {
        if (pending !== selection) return
        selection.confirmation?.cancel()
        pending = null
        selection.result.error(code, message, null)
    }

    private fun accept(selection: Selection, address: String, name: String?) {
        if (pending !== selection || selection.confirmation != null) return
        // RESULT_OK pode chegar antes de o serviço do Android persistir o kit.
        // A conexão só é autorizada após a associação aparecer na consulta.
        val confirmation = AssociationConfirmation(
            handler = handler,
            isAssociated = { isAssociated(address) },
            onConfirmed = { completeAcceptance(selection, address, name) },
            onTimeout = { fail(selection, "not_associated", "O Android não confirmou a associação com o kit. Tente selecionar o kit novamente.") },
            onError = { fail(selection, "selection_failed", it.message ?: "Falha ao confirmar o kit.") },
        )
        selection.confirmation = confirmation
        confirmation.start()
    }

    @SuppressLint("MissingPermission")
    private fun completeAcceptance(selection: Selection, address: String, name: String?) {
        if (pending !== selection) return
        selection.confirmation?.cancel()
        selection.accepted = true
        pending = null
        val deviceName = name ?: try {
            activity.getSystemService(BluetoothManager::class.java).adapter.getRemoteDevice(address).name
        } catch (_: Exception) { null }
        selection.result.success(mapOf("id" to address, "name" to (deviceName ?: "Kit ARCA")))
    }

    private fun acceptAssociation(selection: Selection, association: AssociationInfo) {
        if (Build.VERSION.SDK_INT < 33) return
        // Callback e onActivityResult podem notificar a mesma escolha.
        if (selection.accepted || (pending === selection && selection.confirmation != null)) return
        if (pending !== selection) {
            if (association.id !in selection.previousIds) manager.disassociate(association.id)
            return
        }
        val address = association.deviceMacAddress?.toString()
        if (address == null) {
            if (association.id !in selection.previousIds) manager.disassociate(association.id)
            fail(selection, "invalid_device", "O Android não retornou o endereço Bluetooth do kit.")
            return
        }
        // Evita acumular associações ao escolher novamente a mesma placa.
        val existing = manager.myAssociations.any {
            it.id in selection.previousIds && it.deviceMacAddress == association.deviceMacAddress
        }
        if (existing && association.id !in selection.previousIds) manager.disassociate(association.id)
        accept(selection, address, association.displayName?.toString())
    }

    @Suppress("DEPRECATION")
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val selection = pending ?: return
        if (selection.requestCode != requestCode) return
        if (resultCode != Activity.RESULT_OK) {
            cancel()
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                val association = data?.getParcelableExtra(CompanionDeviceManager.EXTRA_ASSOCIATION, AssociationInfo::class.java)
                if (association != null) {
                    acceptAssociation(selection, association)
                    return
                }
            }
            val selected = data?.getParcelableExtra<android.os.Parcelable>(CompanionDeviceManager.EXTRA_DEVICE)
            val device = when (selected) {
                is ScanResult -> selected.device
                is BluetoothDevice -> selected
                else -> null
            }
            if (device == null) fail(selection, "invalid_device", "O Android não retornou o kit selecionado.")
            else accept(selection, device.address, (selected as? ScanResult)?.scanRecord?.deviceName)
        } catch (error: Exception) {
            fail(selection, "selection_failed", error.message ?: "Falha ao confirmar o kit.")
        }
    }

    fun cancel() {
        val selection = pending ?: return
        selection.confirmation?.cancel()
        pending = null
        try {
            activity.finishActivity(selection.requestCode)
        } finally {
            selection.result.success(null)
        }
    }
}
