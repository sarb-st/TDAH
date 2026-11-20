import XCTest
@testable import AppTDAH

/// "Casa" en el lugar y la hora del widget.
final class CasaTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "casa")
        super.tearDown()
    }

    func testReconoceCasa() {
        for t in ["casa", "Casa", " mi casa ", "en casa", "A casa", "zuhause", "nach Hause"] {
            XCTAssertTrue(Casa.es(t), t)
        }
        for t in ["Casa Mexico", "casamiento", "Bürgeramt", ""] {
            XCTAssertFalse(Casa.es(t), t)
        }
    }

    func testCompletaConLaDireccionDeAjustes() {
        UserDefaults.standard.set("Calle de prueba 1, 10000 Ciudad", forKey: "casa")
        var lugar = "en casa", direccion = ""
        Casa.completar(lugar: &lugar, direccion: &direccion)
        XCTAssertEqual(lugar, "Casa")
        XCTAssertEqual(direccion, "Calle de prueba 1, 10000 Ciudad")
    }

    func testSinCasaCargadaQuedaComoEsta() {
        UserDefaults.standard.removeObject(forKey: "casa")
        var lugar = "casa", direccion = ""
        Casa.completar(lugar: &lugar, direccion: &direccion)
        XCTAssertEqual(lugar, "casa")
        XCTAssertEqual(direccion, "")
    }

    func testHoraDelWidgetEn24Horas() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 20; c.hour = 13; c.minute = 30
        let fecha = Calendar.current.date(from: c)!
        XCTAssertEqual(LoQueViene.cuando(fecha, desde: fecha), "13:30")
    }
}
