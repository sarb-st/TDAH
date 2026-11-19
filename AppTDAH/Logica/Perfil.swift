import Foundation

/// Un turno de trabajo, en minutos desde la medianoche.
struct Turno: Codable, Equatable {
    var inicio: Int
    var fin: Int
}

/// Un día de una semana puntual: qué turno ("m", "t") o libre ("l"), y si tiene otro horario solo ese día.
struct DiaSemana: Codable, Equatable {
    var tipo: String
    var inicio: Int?
    var fin: Int?
}

/// Lo que se eligió para una semana en "¿Qué te toca esta semana?".
struct SemanaElegida: Codable, Equatable {
    var turno: String
    /// Siete días (lunes a domingo); nil = como siempre.
    var dias: [DiaSemana?] = Array(repeating: nil, count: 7)
}

/// El trabajo: dos turnos que se alternan y los días distintos.
struct Trabajo: Codable, Equatable {
    var activo = true
    var manana = Turno(inicio: 6 * 60, fin: 14 * 60)
    var tarde = Turno(inicio: 14 * 60, fin: 22 * 60)
    /// Lunes a domingo.
    var dias = [true, true, true, true, true, false, false]
    /// Días que son distintos siempre: día (0 = lunes) → [minutos que se corre la entrada, la salida].
    var distintos: [String: [Int]] = [:]
    var alterna = true
    /// Un lunes de referencia y qué turno tocaba esa semana.
    var lunesReferencia: Date = Perfil.lunes(de: .now)
    var turnoReferencia = "m"
    /// Semanas puntuales: "AAAA-MM-DD" del lunes → lo elegido.
    var semanas: [String: SemanaElegida] = [:]
}

/// Algo fijo que no es el trabajo (un deporte, un curso).
struct HorarioFijo: Codable, Equatable, Identifiable {
    var id = UUID()
    var titulo: String
    var dias: [Bool]
    var inicio: Int
    var fin: Int
}

/// Una corrección del usuario: lo parecido a este título va a esta área.
struct Correccion: Codable, Equatable {
    var titulo: String
    var area: String
}

/// Lo tuyo: tu día, lo que te importa y tus horarios fijos. Vive en el iPhone (UserDefaults), nunca en el código.
struct Perfil: Codable, Equatable {
    var nombre = ""
    /// Minutos desde la medianoche.
    var levanta = 7 * 60
    var acuesta = 23 * 60 + 30
    /// "manana", "tarde" o "noche".
    var rinde = "manana"
    /// Con la importante: "suave" o "firme".
    var modo = "suave"
    var objetivos: [String] = []
    var trabajo = Trabajo()
    var fijos: [HorarioFijo] = []
    var correcciones: [Correccion] = []
    /// Cada cuántos días sin nada de un objetivo aparece el empujoncito.
    var diasEmpujon = 3

    static let areas = ["Casa", "Cuidado personal", "Pareja", "Trámites y papeles", "Trabajo", "Tiempo libre"]
    static let clave = "perfil"

    var firme: Bool { modo == "firme" }

    // MARK: Guardar y leer

    static func desde(_ datos: Data) -> Perfil {
        (try? JSONDecoder().decode(Perfil.self, from: datos)) ?? Perfil()
    }

    static var actual: Perfil {
        get { desde(UserDefaults.standard.data(forKey: clave) ?? Data()) }
        set { UserDefaults.standard.set(newValue.datos, forKey: clave) }
    }

    var datos: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    // MARK: Fechas

    static func lunes(de fecha: Date, calendario cal: Calendar = .current) -> Date {
        let dia = cal.startOfDay(for: fecha)
        let i = indiceDia(dia, calendario: cal)
        return cal.date(byAdding: .day, value: -i, to: dia) ?? dia
    }

    /// 0 = lunes … 6 = domingo.
    static func indiceDia(_ fecha: Date, calendario cal: Calendar = .current) -> Int {
        (cal.component(.weekday, from: fecha) + 5) % 7
    }

    static func claveSemana(_ lunes: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: lunes)
    }

    // MARK: Trabajo

    /// Qué turno toca la semana de esa fecha: lo elegido para esa semana o, si alterna, el que corresponde.
    func turno(semanaDe fecha: Date, calendario cal: Calendar = .current) -> String {
        let lunes = Perfil.lunes(de: fecha, calendario: cal)
        if let s = trabajo.semanas[Perfil.claveSemana(lunes)] { return s.turno }
        guard trabajo.alterna else { return trabajo.turnoReferencia }
        let ref = Perfil.lunes(de: trabajo.lunesReferencia, calendario: cal)
        let semanas = (cal.dateComponents([.day], from: ref, to: lunes).day ?? 0) / 7
        let par = semanas % 2 == 0
        return par ? trabajo.turnoReferencia : (trabajo.turnoReferencia == "m" ? "t" : "m")
    }

    /// Entrada y salida del trabajo ese día (nil si no trabaja).
    func horarioTrabajo(_ fecha: Date, calendario cal: Calendar = .current) -> (inicio: Int, fin: Int)? {
        guard trabajo.activo else { return nil }
        let i = Perfil.indiceDia(fecha, calendario: cal)
        let turnoSemana = turno(semanaDe: fecha, calendario: cal)
        let base = turnoSemana == "m" ? trabajo.manana : trabajo.tarde
        let elegida = trabajo.semanas[Perfil.claveSemana(Perfil.lunes(de: fecha, calendario: cal))]
        if let d = elegida?.dias[safe: i] ?? nil {
            if d.tipo == "l" { return nil }
            if let a = d.inicio, let b = d.fin { return (a, b) }
            let t = d.tipo == "m" ? trabajo.manana : trabajo.tarde
            return corrido(t, dia: i)
        }
        guard trabajo.dias[safe: i] == true else { return nil }
        return corrido(base, dia: i)
    }

    private func corrido(_ t: Turno, dia i: Int) -> (inicio: Int, fin: Int) {
        let c = trabajo.distintos[String(i)] ?? [0, 0]
        return (t.inicio + (c[safe: 0] ?? 0), t.fin + (c[safe: 1] ?? 0))
    }

    /// Todo lo fijo (trabajo y lo demás) como intervalos, para no proponer nada ahí.
    func ocupados(desde: Date = .now, dias: Int = 14, calendario cal: Calendar = .current) -> [DateInterval] {
        var r: [DateInterval] = []
        let inicio = cal.startOfDay(for: desde)
        for k in 0..<dias {
            guard let dia = cal.date(byAdding: .day, value: k, to: inicio) else { continue }
            let i = Perfil.indiceDia(dia, calendario: cal)
            if let h = horarioTrabajo(dia, calendario: cal) { r.append(intervalo(dia, h.inicio, h.fin)) }
            for f in fijos where f.dias[safe: i] == true { r.append(intervalo(dia, f.inicio, f.fin)) }
        }
        return r.filter { $0.end > desde }
    }

    private func intervalo(_ dia: Date, _ a: Int, _ b: Int) -> DateInterval {
        let desde = dia.addingTimeInterval(Double(a) * 60)
        return DateInterval(start: desde, end: max(desde, dia.addingTimeInterval(Double(b) * 60)))
    }

    /// Entre qué horas proponer cosas: desde un rato después de levantarte hasta una hora antes de acostarte.
    var apertura: Int { min(12, max(5, Int((Double(levanta + 30) / 60).rounded(.up)))) }
    var cierre: Int { max(apertura + 4, min(24, (acuesta - 60) / 60)) }

    /// Texto corto del turno: "06:00 – 14:00".
    static func horas(_ a: Int, _ b: Int) -> String { "\(hhmm(a)) – \(hhmm(b))" }
    static func hhmm(_ m: Int) -> String {
        let m = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
