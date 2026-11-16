import XCTest
@testable import AppTDAH

/// Lo que muestra el widget "Lo que viene" en cada momento.
final class LoQueVieneTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private func t(_ minutos: Double) -> Date { base.addingTimeInterval(minutos * 60) }

    private func item(_ titulo: String, _ desde: Double, _ hasta: Double, categoria: String = "tarea",
                      enCurso: Bool = false, salida: Double? = nil) -> LoQueViene.Item {
        LoQueViene.Item(titulo: titulo, categoria: categoria, inicio: t(desde), fin: t(hasta), enCurso: enCurso,
                        salida: salida.map { t($0) })
    }

    func testMuestraLoMasProximoYLuegoElSiguiente() {
        let d = LoQueViene(items: [item("b", 60, 90), item("a", 10, 40)])
        XCTAssertEqual(d.actual(en: t(0))?.titulo, "a")
        // "a" sigue a la vista 15 min después de su hora (es cuando se decide), después pasa a "b".
        XCTAssertEqual(d.actual(en: t(20))?.titulo, "a")
        XCTAssertEqual(d.actual(en: t(26))?.titulo, "b")
        XCTAssertNil(d.actual(en: t(100)))
    }

    func testLoEnCursoVaPrimeroHastaQueTermina() {
        let d = LoQueViene(items: [item("proxima", 30, 60), item("curso", -10, 50, enCurso: true)])
        XCTAssertEqual(d.actual(en: t(0))?.titulo, "curso")
        XCTAssertEqual(d.actual(en: t(45))?.titulo, "curso")
        XCTAssertEqual(d.siguientes(en: t(0), cantidad: 2).map(\.titulo), ["curso", "proxima"])
    }

    func testEstadosDeUnaTarea() {
        let i = item("a", 10, 40)
        XCTAssertEqual(LoQueViene.estado(i, en: t(0)), .comienzaEn(t(10)))
        XCTAssertEqual(LoQueViene.estado(i, en: t(12)), .esLaHora)
        XCTAssertEqual(LoQueViene.estado(item("c", -5, 40, enCurso: true), en: t(0)), .quedan(t(40)))
    }

    func testEstadosDeUnaCita() {
        let c = item("dentista", 60, 105, categoria: "cita", salida: 20)
        XCTAssertEqual(LoQueViene.estado(c, en: t(0)), .saliEn(t(20)))
        XCTAssertEqual(LoQueViene.estado(c, en: t(30)), .empiezaEn(t(60)))
        XCTAssertEqual(LoQueViene.estado(c, en: t(70)), .terminaEn(t(105)))
        // Una cita se ve hasta que termina.
        XCTAssertEqual(LoQueViene(items: [c]).actual(en: t(100))?.titulo, "dentista")
    }

    func testCambiosIncluyenInicioSalidaYFin() {
        let d = LoQueViene(items: [item("a", 10, 40), item("cita", 60, 90, categoria: "cita", salida: 30)])
        XCTAssertEqual(d.cambios(desde: t(0)), [t(0), t(10), t(25), t(30), t(60), t(90)])
    }

    func testAvanceDelProyecto() {
        var i = item("sesion", 10, 40, categoria: "proyecto")
        i.proyectoInicio = t(0)
        i.proyectoFin = t(100)
        XCTAssertEqual(LoQueViene.avanceProyecto(i, en: t(25)) ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(LoQueViene.avanceProyecto(i, en: t(200)), 1)
    }

    func testSeGuardaYSeLeeIgual() throws {
        let d = LoQueViene(items: [item("a", 10, 40, salida: 5)])
        let json = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(LoQueViene.self, from: json), d)
    }
}
