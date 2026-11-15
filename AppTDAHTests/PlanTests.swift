import XCTest
@testable import AppTDAH

final class PlanTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func dia(_ d: Int, _ mes: Int = 11, _ hora: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: mes, day: d, hour: hora))!
    }

    private let diaS: TimeInterval = 86_400

    func testDuracionesYFinesSonInversas() {
        let inicio = dia(3)
        let fines = [dia(10), dia(24), dia(1, 12)]
        let d = Plan.duraciones(inicio: inicio, fines: fines)
        XCTAssertEqual(d, [7 * diaS, 14 * diaS, 7 * diaS])
        XCTAssertEqual(Plan.fines(inicio: inicio, duraciones: d), fines)
    }

    func testAlargarUnaEtapaCorreLasSiguientes() {
        let inicio = dia(3)
        let fines = [dia(10), dia(24), dia(1, 12)]
        let nuevos = Plan.cambiarDuracion(inicio: inicio, fines: fines, indice: 0, a: 10 * diaS)
        XCTAssertEqual(nuevos, [dia(13), dia(27), dia(4, 12)])
    }

    func testUnaEtapaPuedeDurarHoras() {
        let inicio = dia(3)
        let nuevos = Plan.cambiarDuracion(inicio: inicio, fines: [dia(10), dia(12)], indice: 0, a: 4 * 3600)
        XCTAssertEqual(nuevos[0], dia(3, 11, 4))
        XCTAssertEqual(nuevos[1], dia(5, 11, 4))
    }

    func testNingunaEtapaDuraMenosDeUnaHora() {
        let nuevos = Plan.cambiarDuracion(inicio: dia(3), fines: [dia(10)], indice: 0, a: 60)
        XCTAssertEqual(nuevos[0], dia(3, 11, 1))
    }

    func testAchicarLasQueSiguenTerminaJustoEnLaFechaFinal() {
        let inicio = dia(1)
        // La primera se alargó: 10 días; las siguientes duran 10 y 10, pero solo quedan 10 hasta el 21.
        let fines = [dia(11), dia(21), dia(1, 12)]
        let r = Plan.achicar(inicio: inicio, fines: fines, despuesDe: 0, limite: dia(21))
        XCTAssertEqual(r?.first, dia(11))
        XCTAssertEqual(r?[1], dia(16))
        XCTAssertEqual(r?.last, dia(21))
    }

    func testAchicarNoSePuedeSiEsLaUltimaONoEntra() {
        XCTAssertNil(Plan.achicar(inicio: dia(1), fines: [dia(5), dia(9)], despuesDe: 1, limite: dia(8)))
        XCTAssertNil(Plan.achicar(inicio: dia(1), fines: [dia(9), dia(12)], despuesDe: 0, limite: dia(8)))
    }

    func testRepartirSegunPesosConCortesAMedianoche() {
        let r = Plan.repartir(inicio: dia(1), fin: dia(29), pesos: [1, 2, 1], calendario: cal)
        XCTAssertEqual(r, [dia(8), dia(22), dia(29)])
    }

    func testRepartirEnHorasSiEsMuyCorto() {
        let r = Plan.repartir(inicio: dia(1), fin: dia(1, 11, 12), pesos: [1, 1], calendario: cal)
        XCTAssertEqual(r, [dia(1, 11, 6), dia(1, 11, 12)])
    }

    func testMover() {
        XCTAssertEqual(Plan.mover(["a", "b", "c", "d"], desde: 2, hasta: 0), ["c", "a", "b", "d"])
        XCTAssertEqual(Plan.mover(["a", "b", "c", "d"], desde: 0, hasta: 3), ["b", "c", "d", "a"])
        XCTAssertEqual(Plan.mover(["a", "b"], desde: 5, hasta: 0), ["a", "b"])
    }

    func testDestinoDelArrastre() {
        let alturas: [CGFloat] = [50, 50, 50, 50]
        XCTAssertEqual(Plan.indiceDestino(alturas: alturas, desde: 0, desplazamiento: 20, espacio: 8, rango: 0...3), 0)
        XCTAssertEqual(Plan.indiceDestino(alturas: alturas, desde: 0, desplazamiento: 40, espacio: 8, rango: 0...3), 1)
        XCTAssertEqual(Plan.indiceDestino(alturas: alturas, desde: 0, desplazamiento: 500, espacio: 8, rango: 0...3), 3)
        XCTAssertEqual(Plan.indiceDestino(alturas: alturas, desde: 3, desplazamiento: -100, espacio: 8, rango: 0...3), 1)
        // No pasa por encima de lo que no se puede mover (por ejemplo, una etapa ya cumplida).
        XCTAssertEqual(Plan.indiceDestino(alturas: alturas, desde: 3, desplazamiento: -500, espacio: 8, rango: 1...3), 1)
    }

    func testDuracionEnPalabras() {
        XCTAssertEqual(Formato.duracion(3600), "1 h")
        XCTAssertEqual(Formato.duracion(6 * 3600), "6 h")
        XCTAssertEqual(Formato.duracion(diaS), "1 día")
        XCTAssertEqual(Formato.duracion(5 * diaS), "5 días")
        XCTAssertEqual(Formato.duracion(7 * diaS), "1 semana")
        XCTAssertEqual(Formato.duracion(26 * diaS), "3 semanas y 5 días")
        XCTAssertEqual(Formato.duracion(15 * diaS), "2 semanas y 1 día")
    }

    func testAvisosDeCitaSinTrayecto() {
        let a = MotorSlots.avisosCita(inicio: dia(20, 11, 10), salida: nil)
        XCTAssertEqual(a.map { $0.fecha }, [dia(20, 11, 8), dia(20, 11, 9), dia(20, 11, 10).addingTimeInterval(-1800), dia(20, 11, 10)])
        XCTAssertEqual(a.last?.tipo, .ahora)
    }

    func testAvisosDeCitaConTrayecto() {
        let salida = dia(20, 11, 9)
        let a = MotorSlots.avisosCita(inicio: dia(20, 11, 10), salida: salida)
        XCTAssertEqual(a.map { $0.fecha }, [dia(20, 11, 7), salida.addingTimeInterval(-1800), salida.addingTimeInterval(-300), salida])
        XCTAssertEqual(a.last?.tipo, .salir)
    }
}
