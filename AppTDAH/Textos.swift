import Foundation

/// Textos con formato que se pueden probar sin pantalla.
enum Textos {
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
