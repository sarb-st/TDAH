import XCTest
@testable import AppTDAH

/// Repetir tareas y los horarios fijos del perfil.
final class RepeticionTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func fecha(_ a: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: a, month: m, day: d, hour: h, minute: min))!
    }

    func testAlgunosDiasPorDosMeses() {
        // Viernes 20 de noviembre de 2026: martes y viernes a las 19, por 2 meses.
        var r = Regla()
        r.modo = "dias"
        r.dias = [false, true, false, false, true, false, false]
        r.hora = 19 * 60
        r.hasta = "meses"
        r.meses = 2
        r.desde = fecha(2026, 11, 20)
        let veces = r.ocurrencias(desde: fecha(2026, 11, 20), calendario: cal)
        XCTAssertEqual(veces.first, fecha(2026, 11, 20, 19))
        XCTAssertEqual(veces.dropFirst().first, fecha(2026, 11, 24, 19))
        XCTAssertTrue(veces.allSatisfy { $0 <= fecha(2027, 1, 19, 23, 59) })
        XCTAssertEqual(veces.count, 18)
    }

    func testCadaDosSemanas() {
        var r = Regla()
        r.modo = "cada"
        r.cada = 2
        r.unidad = "semanas"
        r.hasta = "veces"
        r.veces = 3
        r.hora = 10 * 60
        r.desde = fecha(2026, 11, 20)
        let veces = r.ocurrencias(desde: fecha(2026, 11, 19), calendario: cal)
        XCTAssertEqual(veces, [fecha(2026, 11, 20, 10), fecha(2026, 12, 4, 10), fecha(2026, 12, 18, 10)])
    }

    func testVecesDescuentaLasHechas() {
        var r = Regla()
        r.modo = "dia"
        r.hasta = "veces"
        r.veces = 5
        r.hechas = 4
        r.desde = fecha(2026, 11, 20)
        XCTAssertEqual(r.ocurrencias(desde: fecha(2026, 11, 20), calendario: cal).count, 1)
    }

    func testUnaVezPorMesYSiguiente() {
        var r = Regla()
        r.modo = "mes"
        r.diaMes = 20
        r.hasta = "siempre"
        r.hora = 9 * 60
        r.desde = fecha(2026, 11, 1)
        XCTAssertEqual(r.siguiente(despuesDe: fecha(2026, 11, 20, 10), calendario: cal), fecha(2026, 12, 20, 9))
    }

    func testSeGuardaYSeLeeIgual() {
        var r = Regla()
        r.modo = "cada"
        r.fechaFin = fecha(2026, 12, 31)
        r.hasta = "fecha"
        XCTAssertEqual(Regla.leer(r.json)?.modo, "cada")
        XCTAssertEqual(Regla.leer(r.json)?.hasta, "fecha")
    }

    func testTurnoAlternaCadaSemana() {
        var p = Perfil()
        p.trabajo.alterna = true
        p.trabajo.lunesReferencia = fecha(2026, 11, 16)
        p.trabajo.turnoReferencia = "m"
        XCTAssertEqual(p.turno(semanaDe: fecha(2026, 11, 19), calendario: cal), "m")
        XCTAssertEqual(p.turno(semanaDe: fecha(2026, 11, 25), calendario: cal), "t")
        XCTAssertEqual(p.turno(semanaDe: fecha(2026, 12, 2), calendario: cal), "m")
    }

    func testDiaDistintoYSemanaElegida() {
        var p = Perfil()
        p.trabajo.alterna = false
        p.trabajo.turnoReferencia = "m"
        p.trabajo.distintos["4"] = [0, -120]
        // Viernes 20: turno mañana, sale 2 h antes.
        XCTAssertEqual(p.horarioTrabajo(fecha(2026, 11, 20), calendario: cal)?.fin, 12 * 60)
        // Sábado: libre.
        XCTAssertNil(p.horarioTrabajo(fecha(2026, 11, 21), calendario: cal))
        // Una semana puntual: el martes libre.
        var s = SemanaElegida(turno: "t")
        s.dias[1] = DiaSemana(tipo: "l")
        p.trabajo.semanas[Perfil.claveSemana(Perfil.lunes(de: fecha(2026, 11, 23), calendario: cal))] = s
        XCTAssertNil(p.horarioTrabajo(fecha(2026, 11, 24), calendario: cal))
        XCTAssertEqual(p.horarioTrabajo(fecha(2026, 11, 23), calendario: cal)?.inicio, 14 * 60)
    }
}

/// Lo nuevo del perfil y del widget.
final class PerfilTests: XCTestCase {
    func testVentanaDelDiaSegunCuandoTeLevantasYAcostas() {
        var p = Perfil()
        p.levanta = 7 * 60
        p.acuesta = 23 * 60 + 30
        XCTAssertEqual(p.apertura, 8)
        XCTAssertEqual(p.cierre, 22)
    }

    func testHorasEnTexto() {
        XCTAssertEqual(Perfil.horas(6 * 60, 14 * 60), "06:00 – 14:00")
        XCTAssertEqual(Perfil.hhmm(25 * 60), "01:00")
    }

    func testTituloCortoEnElWidget() {
        var i = LoQueViene.Item(titulo: "Llamar al banco por la tarjeta nueva", categoria: "tarea", inicio: .now, fin: .now)
        XCTAssertEqual(i.tituloVisible, "Llamar al banco por la tarjeta nueva")
        i.tituloCorto = "Banco: tarjeta"
        XCTAssertEqual(i.tituloVisible, "Banco: tarjeta")
    }

    func testElPerfilSeGuardaYSeLee() {
        var p = Perfil()
        p.modo = "firme"
        p.objetivos = ["Portfolio"]
        let leido = Perfil.desde(p.datos)
        XCTAssertTrue(leido.firme)
        XCTAssertEqual(leido.objetivos, ["Portfolio"])
    }
}
