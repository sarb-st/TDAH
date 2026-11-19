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
    /// Cómo se viaja a una cita: "transit" (transporte público, por defecto) o "auto".
    var medioViaje: String = "transit"
    /// Los bloques de viaje (ida y vuelta) de una cita en el calendario del iPhone.
    var eventoIda: String = ""
    var eventoVuelta: String = ""
    /// La importante del día (se elige en Preparar mañana).
    var importante: Bool = false
    /// Un título corto para el widget y el fichero, si el título es largo.
    var tituloCorto: String = ""
    /// El objetivo o el área a la que pertenece (se ordena solo y se puede corregir).
    var area: String = ""
    /// Regla de repetición en JSON (vacío si no se repite).
    var repeticion: String = ""
    /// Para algo con una persona de "Los tuyos": su identificador y cómo (llamada, audio, mensaje, en persona).
    var personaUid: String = ""
    var medio: String = ""
    /// Preparar mañana: lo que hay que dejar listo ("listo", "manana" o "").
    var preparado: String = ""
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

    /// Lo que se muestra cuando no hay lugar: el título corto si hay, si no el título.
    var tituloVisible: String { tituloCorto.isEmpty ? titulo : tituloCorto }
}

@Model
final class Paso {
    var uid: UUID = UUID()
    var texto: String = ""
    var hecho: Bool = false
    var orden: Int = 0
    /// De dónde salió: "voz" (lo dictaste), "ia" (sugerido) o "" (escrito a mano).
    var origen: String = ""
    var tarea: Tarea?

    init(texto: String, orden: Int, hecho: Bool = false, origen: String = "") {
        self.texto = texto
        self.orden = orden
        self.hecho = hecho
        self.origen = origen
    }
}

/// Algo con etapas y deadline final. Es un contenedor de tareas: cada tarea funciona igual que siempre.
@Model
final class Proyecto {
    var uid: UUID = UUID()
    var titulo: String = ""
    /// Fecha final: el final del último día del proyecto.
    var deadline: Date = Date()
    /// Cuándo empieza el proyecto. Los proyectos viejos no la tienen: se usa la fecha de creación.
    var fechaInicio: Date?
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

    var inicioEfectivo: Date { fechaInicio ?? creado }

    /// El último día del proyecto, para mostrarlo (la fecha final guardada es el final de ese día).
    var ultimoDia: Date { deadline.addingTimeInterval(-60) }

    /// Qué parte del tiempo entre el inicio y la fecha final ya pasó (0 a 1).
    func avanceTiempo(ahora: Date = .now) -> Double {
        let total = deadline.timeIntervalSince(inicioEfectivo)
        guard total > 0 else { return 1 }
        return min(1, max(0, ahora.timeIntervalSince(inicioEfectivo) / total))
    }

    /// Inicio y fin de cada etapa: cada una empieza donde termina la anterior.
    var rangos: [(etapa: Etapa, inicio: Date, fin: Date)] {
        var desde = inicioEfectivo
        var r: [(etapa: Etapa, inicio: Date, fin: Date)] = []
        for e in etapasOrdenadas {
            r.append((etapa: e, inicio: desde, fin: e.fechaObjetivo))
            desde = max(desde, e.fechaObjetivo)
        }
        return r
    }

    var etapasHechas: Int { etapas.filter(\.cumplida).count }

    /// La próxima sesión agendada del proyecto.
    var proximaSesion: Tarea? { tareas.filter { $0.estado == .programada }.min { $0.inicio < $1.inicio } }

    func diasRestantes(ahora: Date = .now) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: ahora, to: deadline).day ?? 0)
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
    /// El audio del dictado (nombre del archivo en Documentos/audios), si hay.
    var audio: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Renglon.captura) var renglones: [Renglon] = []

    init(tipo: String, texto: String, titulo: String = "", tema: String = "") {
        self.tipo = tipo
        self.texto = texto
        self.titulo = titulo
        self.tema = tema
    }

    var tituloVisible: String { titulo.isEmpty ? texto : titulo }

    /// Los renglones de primer nivel, en orden.
    var principales: [Renglon] { renglones.filter { $0.padre == nil }.sorted { $0.orden < $1.orden } }
}

/// Un renglón de una lista o de una idea. Puede tener renglones adentro (un nivel).
@Model
final class Renglon {
    var uid: UUID = UUID()
    var texto: String = ""
    var orden: Int = 0
    var hecho: Bool = false
    /// "voz" (lo dictaste), "ia" (sugerido) o "" (escrito a mano).
    var origen: String = ""
    /// Una sugerencia que todavía no se sumó.
    var sugerido: Bool = false
    var captura: Captura?
    var padre: Renglon?
    @Relationship(deleteRule: .cascade, inverse: \Renglon.padre) var hijos: [Renglon] = []

    init(texto: String, orden: Int, origen: String = "", sugerido: Bool = false) {
        self.texto = texto
        self.orden = orden
        self.origen = origen
        self.sugerido = sugerido
    }

    var hijosOrdenados: [Renglon] { hijos.sorted { $0.orden < $1.orden } }
}

/// Alguien de "Los tuyos": con quién querés estar presente y cada cuánto.
@Model
final class Persona {
    var uid: UUID = UUID()
    var nombre: String = ""
    /// Cada cuántos días te gustaría hablar.
    var cadaDias: Int = 7
    var ultimaVez: Date?
    @Attribute(.externalStorage) var foto: Data?
    /// Índice del color de la paleta.
    var color: Int = 0
    var creada: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \NotaPersona.persona) var notas: [NotaPersona] = []

    init(nombre: String, cadaDias: Int = 7, color: Int = 0) {
        self.nombre = nombre
        self.cadaDias = cadaDias
        self.color = color
    }

    var inicial: String { String(nombre.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    var hilo: [NotaPersona] { notas.sorted { $0.fecha > $1.fecha } }

    func dias(ahora: Date = .now) -> Int? {
        ultimaVez.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: ahora).day ?? 0) }
    }

    /// El aro: 1 recién hablaron, 0 ya toca.
    func aro(ahora: Date = .now) -> Double {
        guard let d = dias(ahora: ahora) else { return 0 }
        return max(0, 1 - Double(d) / Double(max(1, cadaDias)))
    }

    func yaToca(ahora: Date = .now) -> Bool { aro(ahora: ahora) <= 0 }
}

/// Lo que te contó alguien o en qué quedaron: el hilo de esa persona.
@Model
final class NotaPersona {
    var texto: String = ""
    var fecha: Date = Date()
    var persona: Persona?

    init(texto: String, fecha: Date = .now) {
        self.texto = texto
        self.fecha = fecha
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

    /// Lo que ocupa, con el viaje de ida y vuelta de una cita.
    var intervalosOcupados: [DateInterval] {
        guard esCita, minutosViaje > 0 else { return [intervalo] }
        let viaje = Double(minutosViaje) * 60
        let i = intervalo
        return [DateInterval(start: i.start.addingTimeInterval(-viaje), end: i.end.addingTimeInterval(viaje))]
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
