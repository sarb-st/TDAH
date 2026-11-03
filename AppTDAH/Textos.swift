import Foundation

/// Textos que muestra la app. Están separados de la pantalla para poder probarlos.
enum Textos {
    static let saludo = "Hola"

    static func fechaDeCompilacion(
        timestamp: TimeInterval?,
        locale: Locale = .current,
        zonaHoraria: TimeZone = .current
    ) -> String {
        guard let timestamp else {
            return "Versión de desarrollo"
        }
        let formato = DateFormatter()
        formato.locale = locale
        formato.timeZone = zonaHoraria
        formato.dateStyle = .long
        formato.timeStyle = .short
        return formato.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
