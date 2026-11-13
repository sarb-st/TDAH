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
        case .sinClave: "Falta la clave de Claude. Cargala en Ajustes → Inteligencia artificial."
        case .claveInvalida: "La clave de Claude no es válida. Revisala en Ajustes."
        case .sinCredito: "La cuenta de Claude se quedó sin crédito o llegó a su límite."
        case .ocupado: "Claude está muy ocupado en este momento. Probá en un rato."
        case .sinConexion: "No hay conexión a internet."
        case .rechazado: "Claude no quiso procesar ese texto."
        case .respuestaRara(let detalle): "No entendí la respuesta de Claude (\(detalle))."
        }
    }
}

/// Lo que propone la IA para cada cosa dictada. El usuario la revisa y la puede cambiar antes de guardar.
struct PropuestaIA: Codable, Equatable {
    struct EtapaIA: Codable, Equatable { var titulo: String; var fecha: String }
    struct TareaIA: Codable, Equatable { var titulo: String; var duracion_min: Int }

    var tipo: String
    var alternativa: String
    var titulo: String
    var texto_original: String
    var fecha_hora: String
    var duracion_min: Int
    var lugar: String
    var direccion: String
    var notas: String
    var pasos: [String]
    var tema: String
    var horario_apertura: Int
    var horario_cierre: Int
    var solo_dias_habiles: Bool
    var deadline: String
    var etapas: [EtapaIA]
    var tareas_primera_etapa: [TareaIA]
}

struct ClasificacionIA: Codable { var items: [PropuestaIA] }
struct ReplanteoIA: Codable { var explicacion: String; var etapas: [PropuestaIA.EtapaIA] }

/// Llama a la API de Mensajes de Anthropic directamente (en Swift no hay SDK oficial) y pide JSON con esquema.
enum ClienteClaude {
    static let modelo = "claude-opus-5-5"
    private static let url = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let instrucciones = """
    Sos el asistente de una app para personas con TDAH que convierte lo que el usuario dicta en cosas concretas.
    Recibís un dictado en español rioplatense, a veces desordenado o mal transcrito, y lo separás en ítems.

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
    - pasos: solo para tareas que se beneficien de pasos concretos (como máximo 6, cortos, en infinitivo). Si no, [].
    - Si una tarea depende de que un lugar esté abierto (banco, oficina, comercio), estimá su horario de atención típico
      en horario_apertura y horario_cierre (horas enteras) y si atiende solo días hábiles. Si no aplica, -1, -1 y false.
    - Si una cita necesita preparación (documentos, compras), agregá un ítem aparte de tipo tarea con notas "Preparación para …".
    - Para proyectos: deadline en AAAA-MM-DD (si no la dijo, ""), de 3 a 6 etapas con fechas repartidas hacia atrás desde
      el deadline, y solo las tareas de la primera etapa (las demás se desglosan cuando se llegue a esa etapa).
    - Para ideas: un título corto y un tema de una palabra (diseño, casa, deporte, viajes, trabajo…).
    - titulo: corto, en infinitivo para tareas ("Llamar al banco"). texto_original: el fragmento del dictado de ese ítem.
    - Los campos que no apliquen van vacíos: "", [], 0, -1 o false según el tipo.
    """

    private static let esquemaEtapa: [String: Any] = [
        "type": "object",
        "properties": ["titulo": ["type": "string"], "fecha": ["type": "string"]],
        "required": ["titulo", "fecha"], "additionalProperties": false
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
                        "texto_original": ["type": "string"],
                        "fecha_hora": ["type": "string"],
                        "duracion_min": ["type": "integer"],
                        "lugar": ["type": "string"],
                        "direccion": ["type": "string"],
                        "notas": ["type": "string"],
                        "pasos": ["type": "array", "items": ["type": "string"]],
                        "tema": ["type": "string"],
                        "horario_apertura": ["type": "integer"],
                        "horario_cierre": ["type": "integer"],
                        "solo_dias_habiles": ["type": "boolean"],
                        "deadline": ["type": "string"],
                        "etapas": ["type": "array", "items": esquemaEtapa],
                        "tareas_primera_etapa": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["titulo": ["type": "string"], "duracion_min": ["type": "integer"]],
                                "required": ["titulo", "duracion_min"], "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["tipo", "alternativa", "titulo", "texto_original", "fecha_hora", "duracion_min", "lugar",
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

    static func contextoFecha(_ ahora: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        return "Fecha y hora actual: \(f.string(from: ahora)) (zona horaria \(TimeZone.current.identifier))."
    }

    static func clasificar(_ dictado: String, ahora: Date = .now) async throws -> [PropuestaIA] {
        let pedido = "\(contextoFecha(ahora))\n\nDictado:\n\(dictado)"
        let r: ClasificacionIA = try await pedir(sistema: instrucciones, usuario: pedido, esquema: esquemaClasificacion)
        return r.items
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
            Registro.anotar("Claude respondió \(codigo): \(detalle)")
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
