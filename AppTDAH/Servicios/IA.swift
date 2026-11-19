import Foundation
import Security

/// La clave de la API de Anthropic vive solo en el Keychain del iPhone. Nunca en el código ni en el repositorio.
enum ClaveIA {
    private static let servicio = "app.tdah.claude"
    private static let cuenta = "api-key"

    static var guardada: String? {
        let consulta: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: servicio,
                                       kSecAttrAccount as String: cuenta,
                                       kSecReturnData as String: true,
                                       kSecMatchLimit as String: kSecMatchLimitOne]
        var resultado: AnyObject?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data, let clave = String(data: datos, encoding: .utf8), !clave.isEmpty else { return nil }
        return clave
    }

    static var hay: Bool { guardada != nil }

    static func guardar(_ clave: String) {
        borrar()
        let limpia = clave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpia.isEmpty else { return }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: servicio,
                                   kSecAttrAccount as String: cuenta,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                   kSecValueData as String: Data(limpia.utf8)]
        let estado = SecItemAdd(item as CFDictionary, nil)
        if estado != errSecSuccess { Registro.anotar("Keychain: no se pudo guardar la clave (\(estado)).") }
    }

    static func borrar() {
        let consulta: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: servicio,
                                       kSecAttrAccount as String: cuenta]
        SecItemDelete(consulta as CFDictionary)
    }
}

enum ErrorIA: LocalizedError {
    case sinClave, claveInvalida, sinCredito, ocupado, sinConexion, rechazado, respuestaRara(String)

    var errorDescription: String? {
        switch self {
        case .sinClave: "Falta la clave de la IA. Cargala en Ajustes → Inteligencia artificial."
        case .claveInvalida: "La clave de la IA no es válida. Revisala en Ajustes."
        case .sinCredito: "La cuenta de la IA se quedó sin crédito o llegó a su límite."
        case .ocupado: "La IA está muy ocupada en este momento. Probá en un rato."
        case .sinConexion: "No hay conexión a internet."
        case .rechazado: "No se pudo procesar ese texto."
        case .respuestaRara(let detalle): "No entendí la respuesta (\(detalle))."
        }
    }
}

/// Lo que propone la IA para cada cosa dictada. El usuario la revisa y la puede cambiar antes de guardar.
struct PropuestaIA: Codable, Equatable {
    struct EtapaIA: Codable, Equatable { var titulo: String; var fecha: String }
    struct TareaIA: Codable, Equatable { var titulo: String; var duracion_min: Int }
    /// Un paso: si lo dijo el usuario (dicho) o lo sugiere la IA, y si es grande (conviene partirlo).
    struct PasoIA: Codable, Equatable { var texto: String; var dicho: Bool; var grande: Bool }

    var tipo: String
    var alternativa: String
    var titulo: String
    var titulo_corto: String
    var area: String
    var texto_original: String
    var fecha_hora: String
    var duracion_min: Int
    var lugar: String
    var direccion: String
    var notas: String
    var pasos: [PasoIA]
    var tema: String
    var horario_apertura: Int
    var horario_cierre: Int
    var solo_dias_habiles: Bool
    var deadline: String
    var etapas: [PlanIA.EtapaPlan]
    var tareas_primera_etapa: [TareaIA]
}

struct ClasificacionIA: Codable { var items: [PropuestaIA] }

/// Las etapas de un proyecto nuevo, con lo que dura cada una en días (puede ser una fracción), y las sesiones de la primera.
struct PlanIA: Codable {
    struct EtapaPlan: Codable, Equatable { var titulo: String; var dias: Double }
    var etapas: [EtapaPlan]
    var tareas_primera_etapa: [PropuestaIA.TareaIA]
}
struct ReplanteoIA: Codable { var explicacion: String; var etapas: [PropuestaIA.EtapaIA] }

/// Llama a la API de Mensajes de Anthropic directamente (en Swift no hay SDK oficial) y pide JSON con esquema.
enum ClienteClaude {
    static let modelo = "claude-opus-5-5"
    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let instrucciones = """
    Sos el asistente de una app para personas con TDAH que convierte lo que el usuario dicta en cosas concretas.
    Recibís un dictado en español rioplatense, a veces desordenado o mal transcrito, y lo separás en ítems.
    El usuario vive en un país de habla alemana y mezcla palabras en alemán y en inglés. Te paso la transcripción en
    español (la principal: de ahí sale el sentido) y, a veces, otra del mismo audio reconocida en alemán. Cuando aparezca
    un nombre de calle, un local, una institución o un término alemán, tomá su escritura de la versión en alemán
    (por ejemplo "casta nien alle" en español y "Kastanienallee" en alemán → "Kastanienallee"). Si no hay versión en
    alemán, reconstruí la palabra cuando sea evidente ("termin" → "Termin", "mitin" → "meeting"). Escribila bien
    (mayúsculas, umlauts). El resto de la versión en alemán ignoralo.

    Tipos:
    - cita: día y hora fija, normalmente con otra persona o en un lugar (dentista, reunión, turno).
    - tarea: algo de corto plazo que se hace en el día o en una o dos sesiones (llamar, comprar, limpiar).
    - proyecto: algo con etapas y una fecha final que dura días o semanas (mudanza, viaje, proyecto de diseño, cumpleaños).
    - idea: algo que quiere sacarse de la cabeza sin compromiso de hacerlo ahora.
    - inbox: lo que no se entiende o no alcanza para decidir (un dictado cortado, "lo de Martín").

    Reglas:
    - Si en el dictado hay varias cosas, devolvé un ítem por cada una.
    - Nunca inventes contenido que el usuario no dijo. Podés estimar duraciones y horarios típicos, pero no agregar cosas nuevas.
    - Si dudás entre dos tipos, poné el más probable en "tipo" y el segundo en "alternativa"; si no dudás, "ninguna".
    - fecha_hora: fecha y hora local en formato AAAA-MM-DDTHH:MM, calculada desde la fecha actual que te paso. Si no dijo cuándo, "".
    - duracion_min: la que dijo o una estimación razonable. Para ideas e inbox, 0.
    - pasos: si el usuario dijo los pasos ("primero X, después Y", "antes tengo que…", "armá una lista con…"), usá
      exactamente esos, con sus palabras (cortos, en infinitivo), marcados dicho = true. Ordenalos según el procedimiento
      lógico aunque los haya dicho desordenados. En ese caso podés sumar como mucho dos pasos sugeridos, solo si son
      muy relacionados y faltan (dicho = false). Si no dijo ningún paso, proponé pasos solo para tareas que se beneficien
      (como máximo 6, cortos, en infinitivo), todos con dicho = false. grande = true si un paso es claramente grande y
      conviene partirlo en pasos más chicos. Si no hay pasos, [].
    - titulo_corto: si el título tiene más de 26 caracteres, una versión corta que se entienda en un renglón
      ("Banco: tarjeta y dirección"). Si el título ya es corto, "".
    - area: para tareas, citas y proyectos, a cuál de los objetivos o áreas que te paso pertenece (escribilo igual que en la
      lista). Si no encaja en ninguno, "". Para ideas e inbox, "".
    - Si una tarea depende de que un lugar esté abierto (banco, oficina, comercio), estimá su horario de atención típico
      en horario_apertura y horario_cierre (horas enteras) y si atiende solo días hábiles. Si no aplica, -1, -1 y false.
    - notas: solo lo que el usuario pidió explícitamente recordar o llevar ("llevar la orden", "preguntar por la tarjeta").
      Nunca pongas en notas fragmentos que no entendiste, ni repitas el título o la fecha. Si queda algo que no se entiende,
      va como un ítem aparte de tipo inbox con ese fragmento. Si no hay nada para recordar, notas = "".
    - Si una cita necesita preparación (documentos, compras), agregá un ítem aparte de tipo tarea con notas "Preparación para …".
    - Para proyectos: deadline en AAAA-MM-DD (si no la dijo, ""). Si el usuario nombró etapas, usá exactamente esas, en su
      orden y con sus palabras. Si no, proponé de 3 a 6 etapas concretas que correspondan a lo que dijo y al título (nada
      genérico), cada una con cuántos días dura (puede ser una fracción). Solo las tareas de la primera etapa
      (las demás se desglosan cuando se llegue a esa etapa).
    - Para ideas: un título corto y un tema de una palabra (diseño, casa, deporte, viajes, trabajo…).
    - titulo: corto, en infinitivo para tareas ("Llamar al banco"). texto_original: el fragmento del dictado de ese ítem.
    - Los campos que no apliquen van vacíos: "", [], 0, -1 o false según el tipo.
    """

    private static let esquemaEtapa: [String: Any] = [
        "type": "object",
        "properties": ["titulo": ["type": "string"], "fecha": ["type": "string"]],
        "required": ["titulo", "fecha"], "additionalProperties": false
    ]

    private static let esquemaPaso: [String: Any] = [
        "type": "object",
        "properties": ["texto": ["type": "string"], "dicho": ["type": "boolean"], "grande": ["type": "boolean"]],
        "required": ["texto", "dicho", "grande"], "additionalProperties": false
    ]

    private static let esquemaClasificacion: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "tipo": ["type": "string", "enum": ["tarea", "cita", "proyecto", "idea", "inbox"]],
                        "alternativa": ["type": "string", "enum": ["ninguna", "tarea", "cita", "proyecto", "idea"]],
                        "titulo": ["type": "string"],
                        "titulo_corto": ["type": "string"],
                        "area": ["type": "string"],
                        "texto_original": ["type": "string"],
                        "fecha_hora": ["type": "string"],
                        "duracion_min": ["type": "integer"],
                        "lugar": ["type": "string"],
                        "direccion": ["type": "string"],
                        "notas": ["type": "string"],
                        "pasos": ["type": "array", "items": esquemaPaso],
                        "tema": ["type": "string"],
                        "horario_apertura": ["type": "integer"],
                        "horario_cierre": ["type": "integer"],
                        "solo_dias_habiles": ["type": "boolean"],
                        "deadline": ["type": "string"],
                        "etapas": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["titulo": ["type": "string"], "dias": ["type": "number"]],
                                "required": ["titulo", "dias"], "additionalProperties": false
                            ]
                        ],
                        "tareas_primera_etapa": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["titulo": ["type": "string"], "duracion_min": ["type": "integer"]],
                                "required": ["titulo", "duracion_min"], "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["tipo", "alternativa", "titulo", "titulo_corto", "area", "texto_original", "fecha_hora", "duracion_min", "lugar",
                                 "direccion", "notas", "pasos", "tema", "horario_apertura", "horario_cierre",
                                 "solo_dias_habiles", "deadline", "etapas", "tareas_primera_etapa"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["items"], "additionalProperties": false
    ]

    private static let esquemaReplanteo: [String: Any] = [
        "type": "object",
        "properties": ["explicacion": ["type": "string"], "etapas": ["type": "array", "items": esquemaEtapa]],
        "required": ["explicacion", "etapas"], "additionalProperties": false
    ]

    private static let esquemaPlan: [String: Any] = [
        "type": "object",
        "properties": [
            "etapas": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["titulo": ["type": "string"], "dias": ["type": "number"]],
                    "required": ["titulo", "dias"], "additionalProperties": false
                ]
            ],
            "tareas_primera_etapa": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["titulo": ["type": "string"], "duracion_min": ["type": "integer"]],
                    "required": ["titulo", "duracion_min"], "additionalProperties": false
                ]
            ]
        ],
        "required": ["etapas", "tareas_primera_etapa"], "additionalProperties": false
    ]

    static func contextoFecha(_ ahora: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        return "Fecha y hora actual: \(f.string(from: ahora)) (zona horaria \(TimeZone.current.identifier))."
    }

    /// Los objetivos y áreas del usuario, con lo que ya corrigió, para que la IA ordene cada cosa.
    static func contextoAreas(_ perfil: Perfil = .actual) -> String {
        let objetivos = perfil.objetivos.filter { !$0.isEmpty }
        var t = "Objetivos del usuario: \(objetivos.isEmpty ? "(ninguno)" : objetivos.joined(separator: "; ")).\n"
        t += "Áreas: \(Perfil.areas.joined(separator: "; "))."
        let ejemplos = perfil.correcciones.suffix(20)
        if !ejemplos.isEmpty {
            t += "\nCorrecciones del usuario (lo parecido va al mismo lugar): "
            t += ejemplos.map { "\"\($0.titulo)\" → \($0.area)" }.joined(separator: "; ")
        }
        return t
    }

    static func clasificar(_ dictado: String, aleman: String = "", ahora: Date = .now) async throws -> [PropuestaIA] {
        let deAleman = aleman.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = deAleman.isEmpty ? "" : "\n\nEl mismo audio reconocido en alemán (solo para nombres y términos alemanes):\n\(deAleman)"
        let pedido = "\(contextoFecha(ahora))\n\(contextoAreas())\n\nDictado:\n\(dictado)\(extra)"
        let r: ClasificacionIA = try await pedir(sistema: instrucciones, usuario: pedido, esquema: esquemaClasificacion)
        return r.items
    }

    // MARK: Pedidos chicos

    private static let sistemaCorto = "Ayudás a una persona con TDAH en español rioplatense. Respuestas cortas, concretas, sin inventar cosas que no se deduzcan de lo que te pasan."

    private static func esquema(_ propiedades: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": propiedades, "required": Array(propiedades.keys), "additionalProperties": false]
    }
    private static let listaTextos: [String: Any] = ["type": "array", "items": ["type": "string"]]

    private struct ListaDeTextos: Codable { var textos: [String] }

    /// Parte un paso grande en dos a cuatro pasos más chicos.
    static func partirPaso(tarea: String, paso: String, pasos: [String]) async throws -> [String] {
        let pedido = "Tarea: \(tarea)\nPasos: \(pasos.joined(separator: " · "))\n\nEl paso \"\(paso)\" es grande. Partilo en 2 a 4 pasos más chicos, en orden, cortos y en infinitivo."
        let r: ListaDeTextos = try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema(["textos": listaTextos]))
        return r.textos
    }

    private struct OtroPaso: Codable { var texto: String; var despues_de: Int }

    /// Un paso más, bien relacionado con la tarea, y dónde va en el procedimiento.
    static func otroPaso(tarea: String, pasos: [String]) async throws -> (texto: String, despuesDe: Int) {
        let lista = pasos.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let pedido = "Tarea: \(tarea)\nPasos actuales:\n\(lista.isEmpty ? "(ninguno)" : lista)\n\nSugerí UN paso más que falte y sea muy relacionado (corto, en infinitivo). En despues_de poné el número del paso después del que va (0 si va primero). Si no falta nada con sentido, texto vacío."
        let r: OtroPaso = try await pedir(sistema: sistemaCorto, usuario: pedido,
                                          esquema: esquema(["texto": ["type": "string"], "despues_de": ["type": "integer"]]))
        return (r.texto, r.despues_de)
    }

    struct Adivinanza: Codable, Equatable { var tipo: String; var titulo: String }
    private struct Adivinanzas: Codable { var opciones: [Adivinanza] }

    /// Para un inbox que no se entendió: dos o tres opciones de qué puede ser.
    static func adivinarInbox(_ texto: String) async throws -> [Adivinanza] {
        let pedido = "\(contextoFecha())\nEl usuario dictó esto y no quedó claro qué es: \"\(texto)\".\nProponé 2 o 3 interpretaciones posibles, cada una con tipo (tarea, cita, idea o lista) y un título corto en infinitivo para tareas. No inventes nombres ni datos que no estén."
        let opcion: [String: Any] = esquema(["tipo": ["type": "string", "enum": ["tarea", "cita", "idea", "lista"]], "titulo": ["type": "string"]])
        let r: Adivinanzas = try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema(["opciones": ["type": "array", "items": opcion]]))
        return r.opciones
    }

    /// Cosas más chicas dentro de un renglón de una idea (generales, no pasos concretos).
    static func abrirRenglon(idea: String, renglon: String) async throws -> [String] {
        let pedido = "Idea: \(idea)\nRenglón: \(renglon)\n\nProponé 2 o 3 cosas un poco más chicas para pensar dentro de ese renglón. Es una idea, no un plan: nada de pasos concretos todavía."
        let r: ListaDeTextos = try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema(["textos": listaTextos]))
        return r.textos
    }

    /// Primeros pasos para una idea, a pedido.
    static func pasosIdea(idea: String, renglones: [String]) async throws -> [String] {
        let pedido = "Idea: \(idea)\nLo que la mueve: \(renglones.joined(separator: " · "))\n\nProponé 3 primeros pasos concretos y chicos para empezar a llevarla adelante, cortos y en infinitivo."
        let r: ListaDeTextos = try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema(["textos": listaTextos]))
        return r.textos
    }

    /// Temas para hablar con alguien, siguiendo el hilo de lo que se anotó.
    static func temasPersona(nombre: String, hilo: [String]) async throws -> [String] {
        let pedido = "Persona: \(nombre)\nLo último anotado de esa persona:\n\(hilo.prefix(6).map { "- \($0)" }.joined(separator: "\n"))\n\nProponé 2 o 3 temas cortos para preguntarle o retomar la próxima vez (por ejemplo \"¿Cómo quedó la cocina?\"). Solo de lo anotado; nada de trabajo, tareas ni proyectos."
        let r: ListaDeTextos = try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema(["textos": listaTextos]))
        return r.textos
    }

    struct SugerenciaObjetivo: Codable { var comentario: String; var sugerencias: [PropuestaIA.TareaIA] }

    /// El empujoncito: un comentario cálido sobre lo último que hizo y dos tareas chicas para seguir.
    static func empujon(objetivo: String, recientes: [String]) async throws -> SugerenciaObjetivo {
        let pedido = "Objetivo: \(objetivo)\nLo último que hizo para ese objetivo: \(recientes.isEmpty ? "(nada todavía)" : recientes.joined(separator: "; ")).\n\nEscribí un comentario cálido de una o dos frases que recuerde lo último que hizo y lo invite a seguir (sin culpa, sin \"hace tantos días\"). Y proponé dos tareas chicas y concretas para seguir, con su duración en minutos."
        let tarea: [String: Any] = esquema(["titulo": ["type": "string"], "duracion_min": ["type": "integer"]])
        return try await pedir(sistema: sistemaCorto, usuario: pedido,
                               esquema: esquema(["comentario": ["type": "string"], "sugerencias": ["type": "array", "items": tarea]]))
    }

    struct ReglaIA: Codable, Equatable {
        var modo: String
        var dias: [Bool]
        var cada: Int
        var unidad: String
        var dia_mes: Int
        var hora: String
        var hasta: String
        var meses: Int
        var fecha: String
        var veces: Int
    }

    /// "los martes y viernes a las siete de la tarde, por dos meses" → la regla.
    static func interpretarRepeticion(_ texto: String) async throws -> ReglaIA {
        let pedido = """
        \(contextoFecha())
        El usuario dice cómo se repite una tarea: "\(texto)".
        modo: dia (todos los días), dias (algunos días de la semana), cada (cada N días o semanas) o mes (una vez por mes).
        dias: siete booleanos de lunes a domingo (para modo dias). cada y unidad ("dias" o "semanas") para modo cada.
        dia_mes: el día del mes para modo mes. hora: "HH:MM" o "" si no la dijo.
        hasta: siempre, meses (con meses), fecha (con fecha AAAA-MM-DD) o veces (con veces). Lo que no aplique: 0, "" o false.
        """
        return try await pedir(sistema: sistemaCorto, usuario: pedido, esquema: esquema([
            "modo": ["type": "string", "enum": ["dia", "dias", "cada", "mes"]],
            "dias": ["type": "array", "items": ["type": "boolean"]],
            "cada": ["type": "integer"], "unidad": ["type": "string", "enum": ["dias", "semanas"]],
            "dia_mes": ["type": "integer"], "hora": ["type": "string"],
            "hasta": ["type": "string", "enum": ["siempre", "meses", "fecha", "veces"]],
            "meses": ["type": "integer"], "fecha": ["type": "string"], "veces": ["type": "integer"]
        ]))
    }

    struct SemanaIA: Codable { struct Dia: Codable { var tipo: String; var entra: String; var sale: String }; var turno: String; var dias: [Dia] }

    /// "de lunes a miércoles de tarde, jueves y viernes de mañana" → la semana.
    static func interpretarSemana(_ texto: String, manana: String, tarde: String) async throws -> SemanaIA {
        let pedido = """
        El usuario cuenta cómo trabaja esta semana: "\(texto)".
        Turno mañana: \(manana). Turno tarde: \(tarde).
        Devolvé turno (el que más se repite: "m" o "t") y siete días de lunes a domingo, cada uno con tipo "m", "t" o "l" (libre),
        y entra/sale "HH:MM" solo si dijo un horario distinto ese día (si no, "").
        """
        let dia: [String: Any] = esquema(["tipo": ["type": "string", "enum": ["m", "t", "l"]], "entra": ["type": "string"], "sale": ["type": "string"]])
        return try await pedir(sistema: sistemaCorto, usuario: pedido,
                               esquema: esquema(["turno": ["type": "string", "enum": ["m", "t"]], "dias": ["type": "array", "items": dia]]))
    }

    /// Propone las etapas de un proyecto nuevo entre la fecha de inicio y la final.
    static func armarEtapas(titulo: String, notas: String, inicio: Date, fin: Date, ahora: Date = .now) async throws -> PlanIA {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let dias = max(1, (Calendar.current.dateComponents([.day], from: inicio, to: fin).day ?? 0) + 1)
        let pedido = """
        \(contextoFecha(ahora))
        Proyecto: \(titulo)
        \(notas.isEmpty ? "" : "Notas del usuario: \(notas)\n")Empieza el \(f.string(from: inicio)) y termina el \(f.string(from: fin)) (\(dias) días en total).

        Si en el nombre o en las notas el usuario nombra etapas, usá exactamente esas, en su orden. Si no, proponé de 3 a 6
        etapas en orden que correspondan concretamente a este proyecto (a su nombre y a sus notas), nunca genéricas,
        con un título corto cada una y cuántos días dura (puede ser una fracción si es menos de un día).
        La suma no tiene que pasar de \(dias). Agregá solo las sesiones de la primera etapa: título corto en infinitivo y
        duración en minutos (las demás se arman cuando se llegue a cada etapa). No inventes cosas que no se deduzcan del proyecto.
        """
        return try await pedir(sistema: "Ayudás a planificar proyectos de una persona con TDAH, en español rioplatense: etapas concretas y alcanzables.",
                               usuario: pedido, esquema: esquemaPlan)
    }

    static func replantear(_ p: Proyecto, ahora: Date = .now) async throws -> ReplanteoIA {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let etapas = p.etapasOrdenadas.map { e in
            let pendientes = e.tareas.filter { $0.estado != .terminada && $0.estado != .archivada }.count
            return "- \(e.titulo): objetivo \(f.string(from: e.fechaObjetivo)), \(e.cumplida ? "cumplida" : "pendiente"), \(pendientes) tareas sin terminar"
        }.joined(separator: "\n")
        let pedido = """
        \(contextoFecha(ahora))
        Proyecto: \(p.titulo). Deadline: \(f.string(from: p.deadline)).
        Etapas:
        \(etapas)

        El usuario va atrasado. Proponé nuevas fechas (AAAA-MM-DD) para las etapas no cumplidas, sin pasar el deadline,
        manteniendo los títulos y el orden, y explicá en una o dos frases cortas y sin culpa qué cambia.
        Si no entra todo, sugerí en la explicación qué recortar.
        """
        return try await pedir(sistema: "Ayudás a replanificar proyectos de una persona con TDAH, en español rioplatense, sin generar culpa.",
                               usuario: pedido, esquema: esquemaReplanteo)
    }

    private static func pedir<T: Decodable>(sistema: String, usuario: String, esquema: [String: Any]) async throws -> T {
        guard let clave = ClaveIA.guardada else { throw ErrorIA.sinClave }
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(clave, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Si Claude rechaza el pedido por seguridad, la API lo reintenta con otro modelo en la misma llamada.
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let cuerpo: [String: Any] = [
            "model": modelo,
            "max_tokens": 8000,
            "system": sistema,
            "fallbacks": "default",
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": esquema]],
            "messages": [["role": "user", "content": usuario]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)

        let datos: Data
        let respuesta: URLResponse
        do { (datos, respuesta) = try await URLSession.shared.data(for: req) }
        catch { throw ErrorIA.sinConexion }

        let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else {
            let detalle = String(data: datos.prefix(300), encoding: .utf8) ?? ""
            Registro.anotar("La IA respondió \(codigo): \(detalle)")
            switch codigo {
            case 401, 403: throw ErrorIA.claveInvalida
            case 402: throw ErrorIA.sinCredito
            case 429: throw detalle.contains("credit") ? ErrorIA.sinCredito : ErrorIA.ocupado
            case 500...599: throw ErrorIA.ocupado
            default: throw ErrorIA.respuestaRara("código \(codigo)")
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: datos) as? [String: Any] else { throw ErrorIA.respuestaRara("sin JSON") }
        let motivo = json["stop_reason"] as? String
        if motivo == "refusal" { throw ErrorIA.rechazado }
        if motivo == "max_tokens" { Registro.anotar("Claude: respuesta cortada por max_tokens.") }
        let bloques = json["content"] as? [[String: Any]] ?? []
        let texto = bloques.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard let datosTexto = texto.data(using: .utf8), !texto.isEmpty else { throw ErrorIA.respuestaRara("sin texto") }
        do { return try JSONDecoder().decode(T.self, from: datosTexto) }
        catch {
            Registro.anotar("Claude: no se pudo leer el JSON: \(error.localizedDescription)")
            throw ErrorIA.respuestaRara("formato")
        }
    }
}

/// Convierte las fechas que devuelve la IA ("2026-11-14T18:00", "2026-12-01") en fechas locales.
enum FechasIA {
    static func fechaHora(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for formato in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = formato
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func dia(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(s.prefix(10))) {
            return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: d)
        }
        return nil
    }
}
