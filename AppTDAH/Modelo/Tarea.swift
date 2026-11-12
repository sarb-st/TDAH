import Foundation
import SwiftData

/// Estados posibles de una tarea a lo largo de su slot.
enum EstadoTarea: String, Codable, CaseIterable {
    /// Tiene hora y todavía no llegó (o llegó y falta decidir).
    case programada
    /// El usuario deslizó "Empiezo" y el tiempo corre.
    case enCurso
    /// Terminó el tiempo y no hubo respuesta en 15 minutos.
    case pausada
    /// Dijo "Ahora no" o "Paro por hoy": necesita una hora nueva antes de seguir.
    case faltaHora
    case terminada
    /// "Ya no la voy a hacer". Se puede recuperar.
    case archivada
}

@Model
final class Tarea {
    var uid: UUID = UUID()
    var titulo: String = ""
    var inicio: Date = Date()
    var duracionMinutos: Int = 30
    var estadoRaw: String = EstadoTarea.programada.rawValue
    var inicioReal: Date?
    var minutosExtra: Int = 0
    var creada: Date = Date()
    /// Datos agregados a la tarea, distintos de los pasos: dónde es y qué no olvidar.
    var lugar: String = ""
    var direccion: String = ""
    var notas: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Paso.tarea) var pasos: [Paso] = []

    init(titulo: String, inicio: Date, duracionMinutos: Int) {
        self.titulo = titulo
        self.inicio = inicio
        self.duracionMinutos = duracionMinutos
    }

    var estado: EstadoTarea {
        get { EstadoTarea(rawValue: estadoRaw) ?? .programada }
        set { estadoRaw = newValue.rawValue }
    }

    var pasosOrdenados: [Paso] { pasos.sorted { $0.orden < $1.orden } }
}

@Model
final class Paso {
    var uid: UUID = UUID()
    var texto: String = ""
    var hecho: Bool = false
    var orden: Int = 0
    var tarea: Tarea?

    init(texto: String, orden: Int, hecho: Bool = false) {
        self.texto = texto
        self.orden = orden
        self.hecho = hecho
    }
}

/// Rastro de cada slot: cuándo se planeó, qué pasó y cuánto duró de verdad.
@Model
final class SlotRegistro {
    var uidTarea: UUID = UUID()
    var titulo: String = ""
    var inicioPlaneado: Date = Date()
    var inicioReal: Date?
    var fin: Date?
    var resultado: String = ""
    var minutosReales: Int = 0

    init(uidTarea: UUID, titulo: String, inicioPlaneado: Date, inicioReal: Date?, fin: Date?, resultado: String, minutosReales: Int) {
        self.uidTarea = uidTarea
        self.titulo = titulo
        self.inicioPlaneado = inicioPlaneado
        self.inicioReal = inicioReal
        self.fin = fin
        self.resultado = resultado
        self.minutosReales = minutosReales
    }
}

extension Tarea: DatosSlot {
    var intervalo: DateInterval {
        DateInterval(start: inicioReal ?? inicio, duration: Double(max(1, duracionMinutos + minutosExtra)) * 60)
    }

    /// Ocupa lugar en la agenda: lo que todavía va a pasar o está pasando.
    var ocupaAgenda: Bool { estado == .programada || estado == .enCurso }

    var mapa: URL? {
        let texto = direccion.isEmpty ? lugar : direccion
        guard !texto.isEmpty, let q = texto.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "maps://?q=\(q)")
    }
}

extension EstadoTarea {
    var nombre: String {
        switch self {
        case .programada: "Programada"
        case .enCurso: "En curso"
        case .pausada: "En pausa"
        case .faltaHora: "Falta hora"
        case .terminada: "Hecha"
        case .archivada: "Archivada"
        }
    }
}
