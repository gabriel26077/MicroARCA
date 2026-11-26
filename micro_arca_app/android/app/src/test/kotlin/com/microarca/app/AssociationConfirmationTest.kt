package com.microarca.app

import android.os.Handler
import android.os.Looper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [27], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class AssociationConfirmationTest {
    private val handler = Handler(Looper.getMainLooper())
    private var associated = false
    private var confirmed = 0
    private var timedOut = 0
    private var errors = 0

    private fun confirmation(check: () -> Boolean = { associated }) = AssociationConfirmation(
        handler, check, { confirmed++ }, { timedOut++ }, { errors++ }
    )
    private fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))

    @Test fun associacaoJaRegistradaConfirmaUmaVez() {
        associated = true
        val wait = confirmation()
        wait.start()
        wait.start()
        advance(5000)
        assertEquals(1, confirmed)
        assertEquals(0, timedOut)
    }

    @Test fun registroAtrasadoNaoFalhaAntesDaConfirmacao() {
        confirmation().start()
        advance(300)
        assertEquals(0, confirmed)
        assertEquals(0, timedOut)
        associated = true
        advance(150)
        assertEquals(1, confirmed)
        advance(5000)
        assertEquals(1, confirmed)
        assertEquals(0, timedOut)
    }

    @Test fun ausenciaDeRegistroEncerraNoPrazoSemAutorizar() {
        confirmation().start()
        advance(2999)
        assertEquals(0, timedOut)
        advance(1)
        assertEquals(1, timedOut)
        associated = true
        advance(5000)
        assertEquals(0, confirmed)
        assertEquals(1, timedOut)
    }

    @Test fun cancelamentoIgnoraRegistroTardio() {
        val wait = confirmation()
        wait.start()
        advance(100)
        wait.cancel()
        associated = true
        advance(5000)
        assertEquals(0, confirmed)
        assertEquals(0, timedOut)
    }

    @Test fun novaTentativaNaoRecebeResultadoDaAnteriorCancelada() {
        val old = confirmation()
        old.start()
        old.cancel()
        confirmation().start()
        associated = true
        advance(5000)
        assertEquals(1, confirmed)
        assertEquals(0, timedOut)
    }

    @Test fun falhaAoConsultarEncerraSemAutorizar() {
        confirmation { throw SecurityException("indisponivel") }.start()
        advance(5000)
        assertEquals(1, errors)
        assertEquals(0, confirmed)
        assertEquals(0, timedOut)
    }
}
