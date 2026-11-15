import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
import AppIntents
#endif

/// Alarmas que suenan aunque el iPhone esté en silencio (AlarmKit, iOS 26 en adelante).
/// Se usan al comienzo de cada slot (0, 3 y 6 min) y al terminar el tiempo. Si no están disponibles,
/// la app usa notificaciones comunes.
enum Alarmas {
    /// Desde 2026-11-16 los avisos son notificaciones con la campanita: la pantalla de despertador de iOS no convenció.
    /// El código queda por si se vuelve a usar.
    static var activadas: Bool { false }

    /// "campanita" (sonido propio, corto y suave) o "sistema" (el de iOS).
    static var sonido: String { UserDefaults.standard.string(forKey: "sonidoAlarma") ?? "campanita" }
    static let archivoCampanita = "campanita.wav"

    static var soportadas: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    static var autorizadas: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    static var disponibles: Bool { activadas && DatosDemo.pantalla == nil && autorizadas }

    @discardableResult
    static func pedirPermiso() async -> Bool {
        guard activadas, DatosDemo.pantalla == nil else { return false }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                let estado = try await AlarmManager.shared.requestAuthorization()
                Registro.anotar("Permiso de alarmas: \(estado == .authorized ? "aceptado" : "no aceptado")")
                return estado == .authorized
            } catch {
                Registro.anotar("Permiso de alarmas: error \(error.localizedDescription)")
            }
        }
        #endif
        return false
    }

    /// Un identificador estable por tarea y por momento, para poder cancelarlo después.
    static func id(_ base: UUID, _ n: UInt8) -> UUID {
        var u = base.uuid
        u.15 = u.15 ^ (n &+ 1)
        return UUID(uuid: u)
    }

    static func programar(id: UUID, fecha: Date, titulo: String) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task { await MotorAlarmas.programar(id: id, fecha: fecha, titulo: titulo) }
        }
        #endif
    }

    /// Al abrir la app se apaga cualquier alarma que esté sonando: ya estás adentro para decidir.
    static func detenerSonando() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in (try? AlarmManager.shared.alarms) ?? [] where a.state == .alerting {
                try? AlarmManager.shared.stop(id: a.id)
            }
        }
        #endif
    }

    /// Borra las alarmas que hayan quedado programadas de versiones anteriores.
    static func cancelarTodas() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in (try? AlarmManager.shared.alarms) ?? [] { try? AlarmManager.shared.cancel(id: a.id) }
        }
        #endif
    }

    static func cancelar(_ ids: [UUID]) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let programadas = (try? AlarmManager.shared.alarms) ?? []
            for id in ids where programadas.contains(where: { $0.id == id }) {
                do { try AlarmManager.shared.cancel(id: id) }
                catch { Registro.anotar("No se pudo cancelar una alarma: \(error.localizedDescription)") }
            }
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct MetadatosAlarma: AlarmMetadata {}

/// El botón "Abrir" de la alarma apaga el sonido y lleva directo a la app, donde se decide.
@available(iOS 26.0, *)
struct AbrirAppIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Abrir AppTDAH"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarma")
    var alarma: String

    init() { self.alarma = "" }
    init(alarma: String) { self.alarma = alarma }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarma) { try? AlarmManager.shared.stop(id: id) }
        return .result()
    }
}

@available(iOS 26.0, *)
enum MotorAlarmas {
    static func programar(id: UUID, fecha: Date, titulo: String) async {
        let abrir = AlarmButton(text: "Abrir", textColor: .white, systemImageName: "circle.circle")
        let nombre = LocalizedStringResource(stringLiteral: titulo)
        let alerta: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alerta = AlarmPresentation.Alert(title: nombre, secondaryButton: abrir, secondaryButtonBehavior: .custom)
        } else {
            let detener = AlarmButton(text: "Detener", textColor: .white, systemImageName: "stop.circle")
            alerta = AlarmPresentation.Alert(title: nombre, stopButton: detener, secondaryButton: abrir, secondaryButtonBehavior: .custom)
        }
        let atributos = AlarmAttributes<MetadatosAlarma>(presentation: AlarmPresentation(alert: alerta),
                                                         metadata: MetadatosAlarma(),
                                                         tintColor: Color(red: 0.31, green: 0.42, blue: 0.33))
        let configuracion = AlarmManager.AlarmConfiguration<MetadatosAlarma>.alarm(
            schedule: .fixed(fecha),
            attributes: atributos,
            stopIntent: nil,
            secondaryIntent: AbrirAppIntent(alarma: id.uuidString),
            sound: Alarmas.sonido == "campanita" ? .named(Alarmas.archivoCampanita) : .default)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuracion)
        } catch {
            Registro.anotar("No se pudo programar una alarma: \(error.localizedDescription)")
        }
    }
}
#endif
