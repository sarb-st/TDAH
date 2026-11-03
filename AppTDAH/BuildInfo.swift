import Foundation

// La nube reescribe este archivo en cada compilación con la fecha y el commit reales.
// Estos valores vacíos son solo para cuando se compila fuera de GitHub Actions.
enum BuildInfo {
    static let timestamp: TimeInterval? = nil
    static let commit: String? = nil
}
