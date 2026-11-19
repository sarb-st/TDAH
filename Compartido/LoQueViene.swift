import Foundation

// Este archivo es parte de la app y de los widgets: es lo que la app le deja anotado al widget.

/// Lo próximo, tal como lo ve el widget "Lo que viene". La app lo escribe cada vez que cambia algo
/// y el widget lo lee sin abrir la base de datos.
struct LoQueViene: Codable, Equatable {
    struct Item: Codable, Equatable {
        var titulo: String
        /// "tarea", "cita" o "proyecto".
        var categoria: String
        var inicio: Date
        var fin: Date
        var enCurso: Bool = false
        /// Para una cita con trayecto: cuándo salir.
        var salida: Date?
        var lugar: String = ""
        var notas: String = ""
        /// Para la sesión de un proyecto: su nombre y sus fechas (para la barra de tiempo).
        var proyecto: String?
        var proyectoInicio: Date?
        var proyectoFin: Date?
        /// Un título corto para que entre en un renglón.
        var tituloCorto: String?
        /// Los próximos pasos sin tachar.
        var pasos: [String]?
        /// La importante del día (borde dorado).
        var importante: Bool?

        var tituloVisible: String { (tituloCorto?.isEmpty == false ? tituloCorto : nil) ?? titulo }
    }

    var items: [Item]

    /// Una tarea que llega a su hora sigue a la vista este rato (es cuando la app pide "Empiezo" o "Ahora no").
    static let ventanaDeLaHora: TimeInterval = 15 * 60

    /// Hasta cuándo se muestra cada cosa.
    static func visibleHasta(_ i: Item) -> Date {
        if i.categoria == "cita" || i.enCurso { return i.fin }
        return min(i.fin, i.inicio.addingTimeInterval(ventanaDeLaHora))
    }

    /// Lo que se muestra en un momento: lo que está en curso primero; si no, lo que viene antes.
    func actual(en fecha: Date) -> Item? {
        siguientes(en: fecha, cantidad: 1).first
    }

    func siguientes(en fecha: Date, cantidad: Int) -> [Item] {
        let vivos = items.filter { LoQueViene.visibleHasta($0) > fecha }
        let ordenados = vivos.sorted { a, b in
            if a.enCurso != b.enCurso { return a.enCurso }
            return a.inicio < b.inicio
        }
        return Array(ordenados.prefix(cantidad))
    }

    /// Los momentos en que el widget tiene que cambiar lo que muestra.
    func cambios(desde fecha: Date, limite: Int = 30) -> [Date] {
        var fechas: Set<Date> = [fecha]
        for i in items {
            for f in [i.inicio, i.salida, LoQueViene.visibleHasta(i)].compactMap({ $0 }) where f > fecha {
                fechas.insert(f)
            }
        }
        return Array(fechas.sorted().prefix(limite))
    }

    /// Qué decir de una cosa en un momento dado.
    enum Estado: Equatable {
        case comienzaEn(Date), esLaHora, quedan(Date)
        case saliEn(Date), empiezaEn(Date), terminaEn(Date)

        var texto: String {
            switch self {
            case .comienzaEn: "comienza en"
            case .esLaHora: "es la hora"
            case .quedan: "quedan"
            case .saliEn: "salí en"
            case .empiezaEn: "empieza en"
            case .terminaEn: "termina en"
            }
        }

        /// La fecha hacia la que corre la cuenta regresiva (si hay una).
        var hasta: Date? {
            switch self {
            case .comienzaEn(let d), .quedan(let d), .saliEn(let d), .empiezaEn(let d), .terminaEn(let d): d
            case .esLaHora: nil
            }
        }
    }

    static func estado(_ i: Item, en fecha: Date) -> Estado {
        if i.categoria == "cita" {
            if let s = i.salida, fecha < s { return .saliEn(s) }
            if fecha < i.inicio { return .empiezaEn(i.inicio) }
            return .terminaEn(i.fin)
        }
        if i.enCurso { return .quedan(i.fin) }
        if fecha < i.inicio { return .comienzaEn(i.inicio) }
        return .esLaHora
    }

    /// Una cuenta regresiva de más de este tiempo se muestra como hora ("mañana 18:00").
    static let cuentaMaxima: TimeInterval = 6 * 3600

    /// "18:00", "mañana 18:00" o "jue 18:00".
    static func cuando(_ fecha: Date, desde ahora: Date) -> String {
        let cal = Calendar.current
        let hora = fecha.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "es_AR")))
        if cal.isDate(fecha, inSameDayAs: ahora) { return hora }
        if let manana = cal.date(byAdding: .day, value: 1, to: ahora), cal.isDate(fecha, inSameDayAs: manana) { return "mañana \(hora)" }
        let dia = fecha.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "es_AR")))
            .replacingOccurrences(of: ".", with: "")
        return "\(dia) \(hora)"
    }

    /// Cuánto del proyecto ya pasó, de 0 a 1.
    static func avanceProyecto(_ i: Item, en fecha: Date) -> Double? {
        guard let a = i.proyectoInicio, let b = i.proyectoFin, b > a else { return nil }
        return min(1, max(0, fecha.timeIntervalSince(a) / b.timeIntervalSince(a)))
    }

    static func diasHasta(_ fin: Date, desde fecha: Date) -> Int {
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: fecha), to: cal.startOfDay(for: fin)).day ?? 0)
    }
}

/// La carpeta que comparten la app y los widgets (App Group).
/// SideStore le cambia el nombre al instalar con tu Apple ID, así que el nombre real se lee de la firma.
enum GrupoApp {
    static let base = "group.app.tdah.AppTDAH"
    static let archivo = "lo-que-viene.json"

    static var identificador: String {
        let candidatos = gruposDeLaFirma() + ((Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? [])
        return candidatos.first { $0.hasPrefix(base) } ?? candidatos.first ?? base
    }

    static var carpeta: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identificador)
    }

    static func guardar(_ datos: LoQueViene) -> Bool {
        guard let url = carpeta?.appendingPathComponent(archivo),
              let json = try? JSONEncoder().encode(datos) else { return false }
        return (try? json.write(to: url, options: .atomic)) != nil
    }

    static func leer() -> LoQueViene? {
        guard let url = carpeta?.appendingPathComponent(archivo), let json = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LoQueViene.self, from: json)
    }

    /// Los App Groups que figuran en el perfil con el que SideStore firmó esta app (o este widget).
    private static func gruposDeLaFirma() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let datos = try? Data(contentsOf: url),
              let texto = String(data: datos, encoding: .isoLatin1),
              let desde = texto.range(of: "<?xml"),
              let hasta = texto.range(of: "</plist>"),
              let dic = try? PropertyListSerialization.propertyList(
                  from: Data(String(texto[desde.lowerBound..<hasta.upperBound]).utf8), format: nil) as? [String: Any],
              let permisos = dic["Entitlements"] as? [String: Any] else { return [] }
        return permisos["com.apple.security.application-groups"] as? [String] ?? []
    }
}

/// En qué cosa está el carrusel del widget "Lo que viene" (las flechitas lo mueven sin abrir la app).
enum CarruselWidget {
    static let clave = "indiceLoQueViene"
    static var defaults: UserDefaults? { UserDefaults(suiteName: GrupoApp.identificador) }
    static var indice: Int {
        get { defaults?.integer(forKey: clave) ?? 0 }
        set { defaults?.set(newValue, forKey: clave) }
    }
}

/// Los enlaces con que los widgets abren la app.
enum EnlaceApp {
    static let dictar = URL(string: "apptdah://dictar")!
    static let escribir = URL(string: "apptdah://escribir")!
    static let inicio = URL(string: "apptdah://inicio")!
}
