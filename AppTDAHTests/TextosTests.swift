import XCTest
@testable import AppTDAH

final class TextosTests: XCTestCase {
    func testSinFechaMuestraVersionDeDesarrollo() {
        XCTAssertEqual(Textos.fechaDeCompilacion(timestamp: nil), "Versión de desarrollo")
    }

    func testFechaSeMuestraEnEspanol() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let texto = Textos.fechaDeCompilacion(timestamp: 0, locale: Locale(identifier: "es_AR"), zonaHoraria: utc)
        XCTAssertTrue(texto.contains("1970"), "Texto recibido: \(texto)")
        XCTAssertTrue(texto.contains("enero"), "Texto recibido: \(texto)")
    }

    func testCuentaRegresiva() {
        XCTAssertEqual(Formato.cuenta(272), "4:32")
        XCTAssertEqual(Formato.cuenta(59), "0:59")
        XCTAssertEqual(Formato.cuenta(3872), "1 h 04")
        XCTAssertEqual(Formato.cuenta(-5), "0:00")
    }
}
