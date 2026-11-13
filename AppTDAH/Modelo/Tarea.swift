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
    /// Una cita tiene hora fija (dentista, reunión): no pasa por "Empiezo" o "Ahora no".
    var esCita: Bool = false
    /// Minutos de viaje hasta el lugar de la cita; con ellos se calcula la hora de salida.
    var minutosViaje: Int = 0
    /// Horario del lugar (hora de apertura y cierre, -1 si no aplica): las horas propuestas lo respetan.
    var apertura: Int = -1
    var cierre: Int = -1
    var soloDiasHabiles: Bool = false
    /// Identificador del evento espejo en el calendario del iPhone.
    var eventoCalendario: String = ""
    var proyecto: Proyecto?
    var etapa: Etapa?
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

/// Algo con etapas y deadline final. Es un contenedor de tareas: cada tarea funciona igual que siempre.
@Model
final class Proyecto {
    var uid: UUID = UUID()
    var titulo: String = ""
    var deadline: Date = Date()
    var notas: String = ""
    var creado: Date = Date()
    var archivado: Bool = false
    /// Replanteos seguidos sin cumplir un hito a tiempo.
    var replanteos: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \Etapa.proyecto) var etapas: [Etapa] = []
    @Relationship(deleteRule: .nullify, inverse: \Tarea.proyecto) var tareas: [Tarea] = []

    init(titulo: String, deadline: Date) {
        self.titulo = titulo
        self.deadline = deadline
    }

    var etapasOrdenadas: [Etapa] { etapas.sorted { $0.orden < $1.orden } }

    /// La primera etapa que no está cumplida.
    var etapaActual: Etapa? { etapasOrdenadas.first { !$0.cumplida } }

    /// Qué parte del tiempo hasta el deadline ya pasó (0 a 1).
    func avanceTiempo(ahora: Date = .now) -> Double {
        let total = deadline.timeIntervalSince(creado)
        guard total > 0 else { return 1 }
        return min(1, max(0, ahora.timeIntervalSince(creado) / total))
    }

    /// Hay atraso si una etapa ya venció y todavía no se cumplió.
    func atrasado(ahora: Date = .now) -> Etapa? {
        etapasOrdenadas.first { !$0.cumplida && $0.fechaObjetivo < ahora }
    }
}

@Model
final class Etapa {
    var uid: UUID = UUID()
    var titulo: String = ""
    var fechaObjetivo: Date = Date()
    var orden: Int = 0
    var cumplida: Bool = false
    var proyecto: Proyecto?
    @Relationship(deleteRule: .nullify, inverse: \Tarea.etapa) var tareas: [Tarea] = []

    init(titulo: String, fechaObjetivo: Date, orden: Int) {
        self.titulo = titulo
        self.fechaObjetivo = fechaObjetivo
        self.orden = orden
    }
}

/// IDEA o INBOX: lo que se captura sin hora. La captura se guarda siempre al instante, aunque falten datos.
@Model
final class Captura {
    var uid: UUID = UUID()
    /// "inbox" o "idea".
    var tipo: String = "inbox"
    var texto: String = ""
    var titulo: String = ""
    var tema: String = ""
    var creada: Date = Date()
    var archivada: Bool = false

    init(tipo: String, texto: String, titulo: String = "", tema: String = "") {
        self.tipo = tipo
        self.texto = texto
        self.titulo = titulo
        self.tema = tema
    }

    var tituloVisible: String { titulo.isEmpty ? texto : titulo }
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

    /// Para una cita: cuándo hay que salir (viaje + 10 min de margen).
    var salida: Date? {
        guard esCita, minutosViaje > 0 else { return nil }
        return inicio.addingTimeInterval(-Double(minutosViaje + 10) * 60)
    }

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
