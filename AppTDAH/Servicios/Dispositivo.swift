import Foundation
import Speech
import AVFoundation
import EventKit
import MapKit
import CoreLocation
import Observation
import UIKit

/// Dictado con el reconocimiento de voz del iPhone (gratis; en el dispositivo cuando se puede).
/// El mismo audio se reconoce a la vez en español y en alemán: el español da el sentido y el alemán escribe bien
/// las calles, los locales y los términos alemanes. La IA junta las dos versiones.
@Observable
final class Dictado {
    var texto = ""
    /// Lo mismo, reconocido en alemán.
    var textoAleman = ""
    var escuchando = false
    var error: String?
    /// Qué tan fuerte se está hablando (0 a 1): el halo reacciona a la voz.
    var nivel: Double = 0
    /// La última vez que se oyó voz o cambió el texto: sirve para darse cuenta de que terminaste de hablar.
    @ObservationIgnored var ultimaVoz = Date.now
    /// Se cortó apenas empezó y está volviendo a intentar solo.
    var reintentando = false
    /// El archivo de audio del último dictado (en Documentos/audios), para ideas e inbox.
    @ObservationIgnored var ultimoAudio = ""
    @ObservationIgnored private var archivo: AVAudioFile?
    @ObservationIgnored private var nombreArchivo = ""
    @ObservationIgnored private var inicioSesion = Date.distantPast
    @ObservationIgnored private var reintentos = 0

    static var carpetaAudios: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("audios")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @ObservationIgnored private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-AR")) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    @ObservationIgnored private let motor = AVAudioEngine()
    @ObservationIgnored private var pedido: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var tarea: SFSpeechRecognitionTask?
    @ObservationIgnored private var textoPrevio = ""
    @ObservationIgnored private let reconocedorAleman = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    @ObservationIgnored private var pedidoAleman: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var tareaAleman: SFSpeechRecognitionTask?
    @ObservationIgnored private var textoPrevioAleman = ""

    func alternar() {
        if escuchando { detener() } else { Task { await empezar() } }
    }

    @MainActor
    func empezar(esReintento: Bool = false) async {
        error = nil
        if !esReintento { reintentos = 0 }
        // Desde un widget, la app puede estar abriéndose todavía: si empieza a escuchar antes, el reconocimiento
        // falla al instante. Espera (hasta 2 s) a que esté activa del todo.
        var espera = 0
        while UIApplication.shared.applicationState != .active && espera < 20 {
            try? await Task.sleep(for: .milliseconds(100))
            espera += 1
        }
        let voz = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard voz == .authorized else { error = "Falta el permiso de reconocimiento de voz (Ajustes del iPhone → AppTDAH)."; reintentando = false; return }
        let micro = await AVAudioApplication.requestRecordPermission()
        guard micro else { error = "Falta el permiso del micrófono (Ajustes del iPhone → AppTDAH)."; reintentando = false; return }
        guard let reconocedor, reconocedor.isAvailable else { error = "El reconocimiento de voz no está disponible ahora."; reintentando = false; return }

        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(.record, mode: .measurement, options: .duckOthers)
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)
            let pedido = SFSpeechAudioBufferRecognitionRequest()
            pedido.shouldReportPartialResults = true
            if reconocedor.supportsOnDeviceRecognition { pedido.requiresOnDeviceRecognition = true }
            self.pedido = pedido
            textoPrevio = texto.isEmpty ? "" : texto + " "
            var aleman: SFSpeechAudioBufferRecognitionRequest?
            if let de = reconocedorAleman, de.isAvailable {
                let p = SFSpeechAudioBufferRecognitionRequest()
                p.shouldReportPartialResults = true
                if de.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
                aleman = p
            }
            pedidoAleman = aleman
            textoPrevioAleman = textoAleman.isEmpty ? "" : textoAleman + " "
            let entrada = motor.inputNode
            entrada.removeTap(onBus: 0)
            let formato = entrada.outputFormat(forBus: 0)
            guard formato.sampleRate > 0 else { throw NSError(domain: "Dictado", code: 1, userInfo: [NSLocalizedDescriptionKey: "el micrófono todavía no está listo"]) }
            // El audio se guarda también en un archivo, para escucharlo después en la ficha de una idea o un inbox.
            if !esReintento || archivo == nil {
                nombreArchivo = "\(UUID().uuidString).caf"
                archivo = try? AVAudioFile(forWriting: Dictado.carpetaAudios.appendingPathComponent(nombreArchivo), settings: formato.settings)
            }
            let grabar = archivo
            entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
                pedido.append(buffer)
                aleman?.append(buffer)
                try? grabar?.write(from: buffer)
                let n = Dictado.volumen(buffer)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.nivel = n > self.nivel ? self.nivel * 0.3 + n * 0.7 : self.nivel * 0.82 + n * 0.18
                    if n > 0.45 { self.ultimaVoz = .now }
                }
            }
            motor.prepare()
            try motor.start()
            ultimaVoz = .now
            inicioSesion = .now
            escuchando = true
            reintentando = false
            tarea = reconocedor.recognitionTask(with: pedido) { [weak self] resultado, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let resultado {
                        let nuevo = self.textoPrevio + resultado.bestTranscription.formattedString
                        if nuevo != self.texto { self.ultimaVoz = .now }
                        self.texto = nuevo
                    }
                    if let error {
                        // Si se cortó apenas empezó y sin texto, reintenta solo (hasta dos veces) en vez de rendirse.
                        let vacio = self.texto.trimmingCharacters(in: .whitespaces).isEmpty
                        if self.escuchando && vacio && Date.now.timeIntervalSince(self.inicioSesion) < 2.5 && self.reintentos < 2 {
                            self.reintentos += 1
                            Registro.anotar("Dictado: se cortó al empezar (\((error as NSError).domain) \((error as NSError).code)); reintento \(self.reintentos).")
                            self.reintentar()
                        } else {
                            if vacio { Registro.anotar("Dictado: terminó con error (\((error as NSError).domain) \((error as NSError).code)).") }
                            self.detener()
                        }
                    } else if resultado?.isFinal == true {
                        self.detener()
                    }
                }
            }
            if let de = reconocedorAleman, let aleman {
                tareaAleman = de.recognitionTask(with: aleman) { [weak self] resultado, _ in
                    guard let resultado else { return }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.textoAleman = self.textoPrevioAleman + resultado.bestTranscription.formattedString
                    }
                }
            }
        } catch {
            Registro.anotar("Dictado: \(error.localizedDescription)")
            if reintentos < 2 {
                reintentos += 1
                reintentar()
            } else {
                self.error = "No te pude escuchar. Tocá de nuevo para hablar."
                detener()
            }
        }
    }

    /// Para el motor sin perder lo escuchado y vuelve a empezar en un ratito.
    private func reintentar() {
        reintentando = true
        pararMotor()
        escuchando = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard reintentando else { return }
            await empezar(esReintento: true)
        }
    }

    private func pararMotor() {
        if motor.isRunning {
            motor.stop()
        }
        motor.inputNode.removeTap(onBus: 0)
        pedido?.endAudio()
        tarea?.cancel()
        pedido = nil
        tarea = nil
        pedidoAleman?.endAudio()
        tareaAleman?.cancel()
        pedidoAleman = nil
        tareaAleman = nil
    }

    func detener() {
        pararMotor()
        reintentando = false
        escuchando = false
        nivel = 0
        // Cierra el archivo de audio: si quedó algo grabado, queda como el último audio.
        if archivo != nil {
            archivo = nil
            let url = Dictado.carpetaAudios.appendingPathComponent(nombreArchivo)
            let tamano = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if tamano > 8_000 { ultimoAudio = nombreArchivo } else { try? FileManager.default.removeItem(at: url); ultimoAudio = "" }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Volumen de un pedazo de audio, de 0 (silencio) a 1 (voz fuerte).
    static func volumen(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let canal = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var suma: Float = 0
        for i in 0..<n { suma += canal[i] * canal[i] }
        let rms = sqrt(suma / Float(n))
        let db = 20 * log10(max(rms, 0.000_01))
        return Double(min(1, max(0, (db + 52) / 32)))
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

    var autorizada: Bool { ubicacion.authorizationStatus == .authorizedWhenInUse || ubicacion.authorizationStatus == .authorizedAlways }

    @MainActor
    func pedirPermiso() async {
        guard ubicacion.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { c in
            esperaPermiso = c
            ubicacion.requestWhenInUseAuthorization()
        }
    }

    /// Busca un lugar o dirección en Mapas, cerca de la ciudad del usuario si está cargada.
    /// Busca un lugar en Mapas y lo acepta solo si está cerca de donde estás o de tu ciudad (a menos de 60 km).
    @MainActor
    func buscarCerca(_ texto: String) async -> MKMapItem? {
        guard let item = await buscar(texto) else { return nil }
        if let region = await regionSugerida() {
            let centro = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let c = item.placemark.coordinate
            if CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: centro) > 60_000 { return nil }
        }
        return item
    }

    /// "Kastanienallee 12, 10435 Berlin".
    static func direccion(de item: MKMapItem) -> String {
        let p = item.placemark
        let calle = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let ciudad = [p.postalCode, p.locality].compactMap { $0 }.joined(separator: " ")
        return [calle, ciudad].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @MainActor
    func buscar(_ texto: String) async -> MKMapItem? {
        let busqueda = MKLocalSearch.Request()
        busqueda.naturalLanguageQuery = texto
        if let r = await regionSugerida() { busqueda.region = r }
        return try? await MKLocalSearch(request: busqueda).start().mapItems.first
    }

    @MainActor private var regionCiudad: (ciudad: String, region: MKCoordinateRegion)?

    /// Dónde buscar lugares: alrededor de donde estás o, si no, de tu ciudad (Ajustes → Lugares).
    @MainActor
    func regionSugerida() async -> MKCoordinateRegion? {
        if autorizada, let aca = ubicacion.location?.coordinate {
            return MKCoordinateRegion(center: aca, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        let ciudad = (UserDefaults.standard.string(forKey: "ciudad") ?? "").trimmingCharacters(in: .whitespaces)
        guard !ciudad.isEmpty else { return nil }
        if let c = regionCiudad, c.ciudad == ciudad { return c.region }
        let busqueda = MKLocalSearch.Request()
        busqueda.naturalLanguageQuery = ciudad
        guard let item = try? await MKLocalSearch(request: busqueda).start().mapItems.first else { return nil }
        let region = MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        regionCiudad = (ciudad, region)
        return region
    }

    /// Minutos de viaje en transporte público desde donde estás ahora. Sin permiso de ubicación, desde tu casa
    /// (Ajustes → Lugares). Devuelve nil si no se puede calcular.
    @MainActor
    func minutos(hasta direccion: String, medio: String = "transit") async -> Int? {
        await pedirPermiso()
        let origen: MKMapItem
        if autorizada {
            origen = MKMapItem.forCurrentLocation()
        } else {
            let casa = (UserDefaults.standard.string(forKey: "casa") ?? "").trimmingCharacters(in: .whitespaces)
            guard !casa.isEmpty, let item = await buscar(casa) else { return nil }
            origen = item
        }
        guard let destino = await buscar(direccion) else { return nil }
        let medios: [MKDirectionsTransportType] = medio == "auto" ? [.automobile, .transit] : [.transit, .walking, .automobile]
        for tipo in medios {
            let pedido = MKDirections.Request()
            pedido.source = origen
            pedido.destination = destino
            pedido.transportType = tipo
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
            for id in [t.eventoIda, t.eventoVuelta] where !id.isEmpty {
                if let e = almacen.event(withIdentifier: id) { try? almacen.remove(e, span: .thisEvent, commit: true) }
            }
            t.eventoIda = ""
            t.eventoVuelta = ""
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
        sincronizarViaje(t, calendario: calendario)
    }

    /// En una cita con viaje, bloquea en el calendario el trayecto de ida (antes) y de vuelta (después).
    @MainActor
    private static func sincronizarViaje(_ t: Tarea, calendario: EKCalendar) {
        let conViaje = t.esCita && t.minutosViaje > 0 && t.estado == .programada
        let viaje = Double(t.minutosViaje) * 60
        let fin = t.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60)
        let medio = t.medioViaje == "auto" ? "en auto" : "en transporte"
        func bloque(_ id: String, desde: Date, hasta: Date, titulo: String) -> String {
            let existente = id.isEmpty ? nil : almacen.event(withIdentifier: id)
            guard conViaje else {
                if let e = existente { try? almacen.remove(e, span: .thisEvent, commit: true) }
                return ""
            }
            let e = existente ?? EKEvent(eventStore: almacen)
            e.calendar = calendario
            e.title = titulo
            e.startDate = desde
            e.endDate = hasta
            do { try almacen.save(e, span: .thisEvent, commit: true); return e.eventIdentifier ?? "" }
            catch { Registro.anotar("Calendario: no se pudo guardar un viaje (\(error.localizedDescription))."); return id }
        }
        t.eventoIda = bloque(t.eventoIda, desde: t.inicio.addingTimeInterval(-viaje), hasta: t.inicio, titulo: "Viaje \(medio) · \(t.titulo)")
        t.eventoVuelta = bloque(t.eventoVuelta, desde: fin, hasta: fin.addingTimeInterval(viaje), titulo: "Vuelta \(medio) · \(t.titulo)")
    }

    static func borrar(_ t: Tarea) {
        guard autorizado else { return }
        for id in [t.eventoCalendario, t.eventoIda, t.eventoVuelta] where !id.isEmpty {
            if let e = almacen.event(withIdentifier: id) { try? almacen.remove(e, span: .thisEvent, commit: true) }
        }
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
