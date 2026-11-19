import Foundation

/// Cómo se repite una tarea. Se guarda en JSON dentro de la tarea; al terminarla se crea la siguiente.
struct Regla: Codable, Equatable {
    /// "dia" (todos los días), "dias" (algunos días de la semana), "cada" (cada N días o semanas) o "mes" (una vez por mes).
    var modo = "dias"
    /// Lunes a domingo (para "dias").
    var dias = [false, true, false, true, false, false, false]
    /// Cada cuánto (para "cada") y en qué unidad: "dias" o "semanas".
    var cada = 2
    var unidad = "semanas"
    /// El día del mes (para "mes").
    var diaMes = 20
    /// La hora, en minutos desde la medianoche.
    var hora = 19 * 60
    /// "siempre", "meses", "fecha" o "veces".
    var hasta = "meses"
    var meses = 3
    var fechaFin: Date?
    var veces = 10
    /// Desde cuándo cuenta (la primera vez posible).
    var desde: Date = Calendar.current.startOfDay(for: .now)
    /// Cuántas veces ya se hizo (para "veces").
    var hechas = 0

    static func leer(_ json: String) -> Regla? {
        guard !json.isEmpty, let d = json.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Regla.self, from: d)
    }

    var json: String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Hasta qué día (inclusive) se repite; nil si es siempre o por cantidad de veces.
    func ultimoDia(calendario cal: Calendar = .current) -> Date? {
        switch hasta {
        case "meses":
            let inicio = cal.startOfDay(for: desde)
            guard let f = cal.date(byAdding: .month, value: max(1, meses), to: inicio) else { return nil }
            return cal.date(byAdding: .day, value: -1, to: f)
        case "fecha": return fechaFin.map { cal.startOfDay(for: $0) }
        default: return nil
        }
    }

    /// Si toca ese día (sin mirar el fin).
    func toca(_ dia: Date, calendario cal: Calendar = .current) -> Bool {
        let d = cal.startOfDay(for: dia)
        let inicio = cal.startOfDay(for: desde)
        guard d >= inicio else { return false }
        switch modo {
        case "dia": return true
        case "dias": return dias[safe: Perfil.indiceDia(d, calendario: cal)] == true
        case "cada":
            let dif = cal.dateComponents([.day], from: inicio, to: d).day ?? 0
            let paso = max(1, cada) * (unidad == "dias" ? 1 : 7)
            return dif % paso == 0
        default: return cal.component(.day, from: d) == diaMes
        }
    }

    /// Las próximas veces (con su hora), desde una fecha, respetando el fin.
    func ocurrencias(desde fecha: Date, limite: Int = 400, calendario cal: Calendar = .current) -> [Date] {
        var r: [Date] = []
        let fin = ultimoDia(calendario: cal)
        var restantes = hasta == "veces" ? max(0, veces - hechas) : Int.max
        var dia = cal.startOfDay(for: fecha)
        var vueltas = 0
        while r.count < limite && restantes > 0 && vueltas < 800 {
            vueltas += 1
            if let fin, dia > fin { break }
            if toca(dia, calendario: cal) {
                let cuando = dia.addingTimeInterval(Double(hora) * 60)
                if cuando > fecha { r.append(cuando); restantes -= 1 }
            }
            guard let siguiente = cal.date(byAdding: .day, value: 1, to: dia) else { break }
            dia = siguiente
        }
        return r
    }

    /// La próxima vez después de una fecha (nil si ya terminó).
    func siguiente(despuesDe fecha: Date, calendario cal: Calendar = .current) -> Date? {
        ocurrencias(desde: fecha, limite: 1, calendario: cal).first
    }

    /// "Los martes y viernes a las 19:00".
    var resumen: String {
        let nombres = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábados", "domingos"]
        let cuando: String
        switch modo {
        case "dia": cuando = "Todos los días"
        case "dias":
            let elegidos = dias.enumerated().filter(\.element).map { nombres[$0.offset] }
            cuando = elegidos.isEmpty ? "Ningún día" : "Los " + Regla.lista(elegidos)
        case "cada":
            let u = cada == 1 ? (unidad == "dias" ? "día" : "semana") : (unidad == "dias" ? "días" : "semanas")
            cuando = "Cada \(cada) \(u)"
        default: cuando = "El \(diaMes) de cada mes"
        }
        return "\(cuando) a las \(Perfil.hhmm(hora))"
    }

    static func lista(_ a: [String]) -> String {
        a.count <= 1 ? a.joined() : a.dropLast().joined(separator: ", ") + " y " + (a.last ?? "")
    }
}
