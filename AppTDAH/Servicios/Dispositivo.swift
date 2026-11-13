import Foundation
import Speech
import AVFoundation
import EventKit
import MapKit
import CoreLocation
import Observation

/// Dictado con el reconocimiento de voz del iPhone (gratis; en el dispositivo cuando se puede).
@Observable
final class Dictado {
    var texto = ""
    var escuchando = false
    var error: String?

    @ObservationIgnored private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-AR")) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    @ObservationIgnored private let motor = AVAudioEngine()
    @ObservationIgnored private var pedido: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var tarea: SFSpeechRecognitionTask?
    @ObservationIgnored private var textoPrevio = ""

    func alternar() {
        if escuchando { detener() } else { Task { await empezar() } }
    }

    @MainActor
    func empezar() async {
        error = nil
        let voz = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard voz == .authorized else { error = "Falta el permiso de reconocimiento de voz (Ajustes del iPhone → AppTDAH)."; return }
        let micro = await AVAudioApplication.requestRecordPermission()
        guard micro else { error = "Falta el permiso del micrófono (Ajustes del iPhone → AppTDAH)."; return }
        guard let reconocedor, reconocedor.isAvailable else { error = "El reconocimiento de voz no está disponible ahora."; return }

        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(.record, mode: .measurement, options: .duckOthers)
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)
            let pedido = SFSpeechAudioBufferRecognitionRequest()
            pedido.shouldReportPartialResults = true
            if reconocedor.supportsOnDeviceRecognition { pedido.requiresOnDeviceRecognition = true }
            self.pedido = pedido
            textoPrevio = texto.isEmpty ? "" : texto + " "
            let entrada = motor.inputNode
            entrada.removeTap(onBus: 0)
            entrada.installTap(onBus: 0, bufferSize: 1024, format: entrada.outputFormat(forBus: 0)) { buffer, _ in
                pedido.append(buffer)
            }
            motor.prepare()
            try motor.start()
            escuchando = true
            tarea = reconocedor.recognitionTask(with: pedido) { [weak self] resultado, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let resultado { self.texto = self.textoPrevio + resultado.bestTranscription.formattedString }
                    if error != nil || resultado?.isFinal == true { self.detener() }
                }
            }
        } catch {
            self.error = "No se pudo usar el micrófono."
            Registro.anotar("Dictado: \(error.localizedDescription)")
            detener()
        }
    }

    func detener() {
        if motor.isRunning {
            motor.stop()
            motor.inputNode.removeTap(onBus: 0)
        }
        pedido?.endAudio()
        tarea?.cancel()
        pedido = nil
        tarea = nil
        escuchando = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Tiempo de viaje en transporte público hasta una dirección, con Mapas de Apple.
final class Viaje: NSObject, CLLocationManagerDelegate {
    static let shared = Viaje()
    private let ubicacion = CLLocationManager()
    private var esperaPermiso: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        ubicacion.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        esperaPermiso?.resume()
        esperaPermiso = nil
    }

    @MainActor
    func minutos(hasta direccion: String) async -> Int? {
        if ubicacion.authorizationStatus == .notDetermined {
            await withCheckedContinuation { c in
                esperaPermiso = c
                ubicacion.requestWhenInUseAuthorization()
            }
        }
        guard ubicacion.authorizationStatus == .authorizedWhenInUse || ubicacion.authorizationStatus == .authorizedAlways else { return nil }
        let busqueda = MKLocalSearch.Request()
        busqueda.naturalLanguageQuery = direccion
        guard let destino = try? await MKLocalSearch(request: busqueda).start().mapItems.first else { return nil }
        for medio in [MKDirectionsTransportType.transit, .walking, .automobile] {
            let pedido = MKDirections.Request()
            pedido.source = MKMapItem.forCurrentLocation()
            pedido.destination = destino
            pedido.transportType = medio
            if let eta = try? await MKDirections(request: pedido).calculateETA() {
                return Int((eta.expectedTravelTime / 60).rounded(.up))
            }
        }
        return nil
    }
}

/// Espejo en el calendario del iPhone (incluido Google Calendar si está agregado) y lectura de lo ocupado.
enum Calendario {
    private static let almacen = EKEventStore()
    private static let nombre = "AppTDAH"

    static var activado: Bool { UserDefaults.standard.object(forKey: "calendario") as? Bool ?? true }
    static var autorizado: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    @discardableResult
    static func pedirAcceso() async -> Bool {
        guard activado, DatosDemo.pantalla == nil else { return false }
        if autorizado { return true }
        do { return try await almacen.requestFullAccessToEvents() }
        catch { Registro.anotar("Calendario: \(error.localizedDescription)"); return false }
    }

    private static func calendarioApp() -> EKCalendar? {
        if let c = almacen.calendars(for: .event).first(where: { $0.title == nombre && $0.allowsContentModifications }) { return c }
        guard let fuente = almacen.defaultCalendarForNewEvents?.source ?? almacen.sources.first(where: { $0.sourceType == .local }) else { return nil }
        let c = EKCalendar(for: .event, eventStore: almacen)
        c.title = nombre
        c.source = fuente
        c.cgColor = CGColor(red: 0.31, green: 0.42, blue: 0.33, alpha: 1)
        do { try almacen.saveCalendar(c, commit: true); return c }
        catch { Registro.anotar("Calendario: no se pudo crear el calendario (\(error.localizedDescription))."); return nil }
    }

    /// Crea, actualiza o borra el evento espejo de una tarea o cita.
    @MainActor
    static func sincronizar(_ t: Tarea) {
        guard activado, autorizado, DatosDemo.pantalla == nil else { return }
        let existente = t.eventoCalendario.isEmpty ? nil : almacen.event(withIdentifier: t.eventoCalendario)
        let mostrar = t.ocupaAgenda || t.estado == .terminada
        guard mostrar else {
            if let e = existente { try? almacen.remove(e, span: .thisEvent, commit: true) }
            t.eventoCalendario = ""
            return
        }
        guard let calendario = calendarioApp() else { return }
        let e = existente ?? EKEvent(eventStore: almacen)
        e.calendar = calendario
        e.title = t.titulo
        e.startDate = t.inicioReal ?? t.inicio
        e.endDate = (t.inicioReal ?? t.inicio).addingTimeInterval(Double(max(5, t.duracionMinutos + t.minutosExtra)) * 60)
        e.location = t.direccion.isEmpty ? (t.lugar.isEmpty ? nil : t.lugar) : t.direccion
        e.notes = t.notas.isEmpty ? nil : t.notas
        do {
            try almacen.save(e, span: .thisEvent, commit: true)
            t.eventoCalendario = e.eventIdentifier ?? ""
        } catch {
            Registro.anotar("Calendario: no se pudo guardar un evento (\(error.localizedDescription)).")
        }
    }

    static func borrar(_ t: Tarea) {
        guard autorizado, !t.eventoCalendario.isEmpty, let e = almacen.event(withIdentifier: t.eventoCalendario) else { return }
        try? almacen.remove(e, span: .thisEvent, commit: true)
    }

    /// Lo ocupado en los otros calendarios (no el de la app), para no proponer horas que se pisan.
    static func ocupados(desde: Date = .now, dias: Int = 10) -> [DateInterval] {
        guard activado, autorizado else { return [] }
        let hasta = desde.addingTimeInterval(Double(dias) * 86_400)
        let calendarios = almacen.calendars(for: .event).filter { $0.title != nombre }
        guard !calendarios.isEmpty else { return [] }
        let predicado = almacen.predicateForEvents(withStart: desde, end: hasta, calendars: calendarios)
        return almacen.events(matching: predicado)
            .filter { !$0.isAllDay && $0.availability != .free }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
    }
}
