import UIKit

/// Las vibraciones de la app: pocas y con sentido, para que cada una signifique algo (ver diseno/DISENO.md).
/// Se apagan en Ajustes → Vibraciones.
@MainActor
enum Haptica {
    static var activas: Bool { UserDefaults.standard.object(forKey: "vibraciones") as? Bool ?? true }

    /// Empiezo: un golpe firme al llegar arriba.
    static func empiezo() { impacto(.heavy) }

    /// Ahora no: un golpe al cerrar (la vibración que crece mientras se sostiene va con `sosten`).
    static func ahoraNo() { impacto(.rigid) }

    /// Mientras se sostiene "Ahora no": cada vez más fuerte (progreso de 0 a 1).
    static func sosten(_ progreso: Double) {
        guard activas else { return }
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.impactOccurred(intensity: CGFloat(0.25 + 0.75 * min(1, max(0, progreso))))
    }

    /// Terminé: dos toquecitos alegres.
    static func termine() {
        guard activas else { return }
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }

    /// Tachar un paso: un tic leve.
    static func tachar() { impacto(.light, intensidad: 0.6) }

    /// El halo toca una pastilla: un tic para saber que se puede soltar.
    static func pastilla() {
        guard activas else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Dictado: un tic al empezar a escuchar y otro al terminar.
    static func dictado() { impacto(.medium, intensidad: 0.7) }

    private static func impacto(_ estilo: UIImpactFeedbackGenerator.FeedbackStyle, intensidad: CGFloat = 1) {
        guard activas else { return }
        let g = UIImpactFeedbackGenerator(style: estilo)
        g.impactOccurred(intensity: intensidad)
    }
}
