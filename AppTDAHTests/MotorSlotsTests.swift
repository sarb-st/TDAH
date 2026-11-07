import XCTest
@testable import AppTDAH

private struct SlotPrueba: DatosSlot {
    var nombre: String
    var inicio: Date
    var duracionMinutos = 30
    var estado: EstadoTarea = .programada
    var inicioReal: Date?
    var minutosExtra = 0
}

final class MotorSlotsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func fecha(_ dia: Int, _ hora: Int, _ minuto: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: minuto))!
    }

    private func nombre(_ p: Pantalla<SlotPrueba>) -> String {
        switch p {
        case .fin(let t): "fin \(t.nombre)"
        case .enCurso(let t): "enCurso \(t.nombre)"
        case .decidir(let t): "decidir \(t.nombre)"
        case .cuando(let t, let sinRespuesta): "cuando \(t.nombre) \(sinRespuesta)"
        case .espera(let l): "espera " + l.map(\.nombre).joined(separator: ",")
        case .vacio: "vacio"
        }
    }

    // MARK: Qué pantalla corresponde

    func testSinTareasEstaVacio() {
        XCTAssertEqual(nombre(MotorSlots.pantalla([SlotPrueba](), ahora: fecha(6, 10))), "vacio")
    }

    func testEsperaMuestraLasTresProximasEnOrden() {
        let ahora = fecha(6, 10)
        let tareas = [SlotPrueba(nombre: "c", inicio: fecha(6, 14)), SlotPrueba(nombre: "a", inicio: fecha(6, 11)),
                      SlotPrueba(nombre: "d", inicio: fecha(6, 15)), SlotPrueba(nombre: "b", inicio: fecha(6, 12)),
                      SlotPrueba(nombre: "x", inicio: fecha(6, 9), estado: .terminada)]
        XCTAssertEqual(nombre(MotorSlots.pantalla(tareas, ahora: ahora)), "espera a,b,c")
    }

    func testALaHoraHayQueDecidir() {
        let tareas = [SlotPrueba(nombre: "banco", inicio: fecha(6, 18))]
        XCTAssertEqual(nombre(MotorSlots.pantalla(tareas, ahora: fecha(6, 18, 2))), "decidir banco")
    }

    func testDespuesDeTresAvisosSinRespuestaPreguntaCuando() {
        let tareas = [SlotPrueba(nombre: "banco", inicio: fecha(6, 18))]
        XCTAssertEqual(nombre(MotorSlots.pantalla(tareas, ahora: fecha(6, 18, 9))), "cuando banco true")
    }

    func testFaltaHoraBloqueaLaPantalla() {
        let tareas = [SlotPrueba(nombre: "banco", inicio: fecha(6, 18), estado: .faltaHora),
                      SlotPrueba(nombre: "menu", inicio: fecha(6, 20))]
        XCTAssertEqual(nombre(MotorSlots.pantalla(tareas, ahora: fecha(6, 19))), "cuando banco false")
    }

    func testEnCursoHastaQueTerminaElTiempo() {
        let t = SlotPrueba(nombre: "banco", inicio: fecha(6, 18), duracionMinutos: 45, estado: .enCurso, inicioReal: fecha(6, 18, 1))
        XCTAssertEqual(nombre(MotorSlots.pantalla([t], ahora: fecha(6, 18, 30))), "enCurso banco")
        XCTAssertEqual(nombre(MotorSlots.pantalla([t], ahora: fecha(6, 18, 46))), "fin banco")
    }

    func testLaExtensionCorreElFin() {
        let t = SlotPrueba(nombre: "banco", inicio: fecha(6, 18), duracionMinutos: 45, estado: .enCurso,
                           inicioReal: fecha(6, 18), minutosExtra: 15)
        XCTAssertEqual(t.finPrevisto, fecha(6, 19))
        XCTAssertEqual(nombre(MotorSlots.pantalla([t], ahora: fecha(6, 18, 50))), "enCurso banco")
    }

    // MARK: Avisos y choques

    func testTresAvisosCadaTresMinutos() {
        let inicio = fecha(6, 18)
        XCTAssertEqual(MotorSlots.horariosAviso(inicio), [fecha(6, 18), fecha(6, 18, 3), fecha(6, 18, 6)])
    }

    func testExtenderChocaConElSiguiente() {
        let siguiente = SlotPrueba(nombre: "menu", inicio: fecha(6, 19))
        XCTAssertTrue(MotorSlots.choca(finNuevo: fecha(6, 19, 15), siguiente: siguiente))
        XCTAssertFalse(MotorSlots.choca(finNuevo: fecha(6, 19), siguiente: siguiente))
        XCTAssertFalse(MotorSlots.choca(finNuevo: fecha(6, 23), siguiente: SlotPrueba?.none))
    }

    // MARK: Sugerencias de "¿Cuándo, entonces?"

    func testSugerenciasEsquivanLoOcupado() {
        let ocupado = DateInterval(start: fecha(6, 18, 30), end: fecha(6, 19, 30))
        let s = MotorSlots.sugerencias(duracion: 45, ocupados: [ocupado], desde: fecha(6, 17, 55), calendario: cal)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].inicio, fecha(6, 19, 30))
        XCTAssertEqual(s[0].libreHasta, fecha(6, 21))
        XCTAssertEqual(s[1].inicio, fecha(7, 8))
        for sug in s {
            XCTAssertFalse(DateInterval(start: sug.inicio, duration: 45 * 60).intersection(with: ocupado).map { $0.duration > 0 } ?? false)
        }
    }

    func testSugerenciasRespetanElHorario() {
        let s = MotorSlots.sugerencias(duracion: 30, ocupados: [], desde: fecha(6, 20, 50), calendario: cal, apertura: 9, cierre: 16)
        XCTAssertEqual(s.first?.inicio, fecha(7, 9))
        for sug in s {
            let h = cal.component(.hour, from: sug.inicio)
            XCTAssertTrue((9..<16).contains(h), "Fuera de horario: \(sug.inicio)")
        }
    }

    func testRedondeoACuartoDeHora() {
        XCTAssertEqual(MotorSlots.redondearArriba(fecha(6, 18, 1), minutos: 15, calendario: cal), fecha(6, 18, 15))
        XCTAssertEqual(MotorSlots.redondearArriba(fecha(6, 18, 15), minutos: 15, calendario: cal), fecha(6, 18, 15))
    }
}

final class PaletaTests: XCTestCase {
    func testSiempreNocheYSiempreDia() {
        XCTAssertEqual(Paleta.para(.siempreNoche, hora: 12), Paleta.noche)
        XCTAssertEqual(Paleta.para(.siempreDia, hora: 23), Paleta.en(hora: 9.5))
    }

    func testDiaClaroYNocheOscura() {
        XCTAssertFalse(Paleta.en(hora: 9.5).esOscura)
        XCTAssertFalse(Paleta.en(hora: 7.25).esOscura, "A las 7:15 ya tiene que ser claro")
        XCTAssertFalse(Paleta.en(hora: 20).esOscura, "A las 20:00 todavía es atardecer")
        XCTAssertTrue(Paleta.en(hora: 23).esOscura)
        XCTAssertTrue(Paleta.en(hora: 3).esOscura)
    }

    /// Sin saltos: de un minuto al siguiente, ningún color cambia de golpe.
    func testElCambioDelDiaEsContinuo() {
        var h = 0.0
        while h < 24 {
            let a = Paleta.en(hora: h).fondo, b = Paleta.en(hora: h + 1.0 / 60).fondo
            XCTAssertLessThan(max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)), 0.02, "Salto a las \(h)")
            h += 1.0 / 60
        }
    }
}
