import XCTest
@testable import AppTDAH

final class TextosTests: XCTestCase {
    func testSaludoDiceHola() {
        XCTAssertEqual(Textos.saludo, "Hola")
    }

    func testSinFechaMuestraVersionDeDesarrollo() {
        XCTAssertEqual(Textos.fechaDeCompilacion(timestamp: nil), "Versión de desarrollo")
    }

    func testFechaSeMuestraEnEspanol() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let texto = Textos.fechaDeCompilacion(
            timestamp: 0,
            locale: Locale(identifier: "es_AR"),
            zonaHoraria: utc
        )
        XCTAssertTrue(texto.contains("1970"), "Texto recibido: \(texto)")
        XCTAssertTrue(texto.contains("enero"), "Texto recibido: \(texto)")
    }
}
