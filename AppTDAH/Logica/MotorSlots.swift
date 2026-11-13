import Foundation

/// Lo mínimo que la lógica necesita saber de una tarea. Así se puede probar sin base de datos.
protocol DatosSlot {
    var inicio: Date { get }
    var duracionMinutos: Int { get }
    var estado: EstadoTarea { get }
    var inicioReal: Date? { get }
    var minutosExtra: Int { get }
    var esCita: Bool { get }
}

extension DatosSlot {
    /// Cuándo termina el slot en curso, contando las extensiones.
    var finPrevisto: Date? {
        inicioReal.map { $0.addingTimeInterval(Double(duracionMinutos + minutosExtra) * 60) }
    }
}

/// Qué pantalla corresponde mostrar.
enum Pantalla<T> {
    case fin(T)
    case enCurso(T)
    case decidir(T)
    case cuando(T, sinRespuesta: Bool)
    case espera([T])
    case vacio
}

struct Sugerencia: Equatable {
    let inicio: Date
    let libreHasta: Date
}

enum MotorSlots {
    /// Tres avisos (0, 3 y 6 min): si los tres se descartan, el slot se cierra como "Ahora no".
    static let minutosEntreAvisos = 3
    static let cantidadDeAvisos = 3
    static var ventanaDecision: TimeInterval { Double(minutosEntreAvisos * cantidadDeAvisos) * 60 }

    static func horariosAviso(_ inicio: Date) -> [Date] {
        (0..<cantidadDeAvisos).map { inicio.addingTimeInterval(Double($0 * minutosEntreAvisos) * 60) }
    }

    /// Lo pendiente de resolver va primero; si no hay nada pendiente, lo próximo.
    static func pantalla<T: DatosSlot>(_ tareas: [T], ahora: Date) -> Pantalla<T> {
        if let t = tareas.first(where: { $0.estado == .pausada }) { return .fin(t) }
        if let t = tareas.first(where: { $0.estado == .enCurso }) {
            if let fin = t.finPrevisto, ahora >= fin { return .fin(t) }
            return .enCurso(t)
        }
        if let t = tareas.first(where: { $0.estado == .faltaHora }) { return .cuando(t, sinRespuesta: false) }
        let programadas = tareas.filter { $0.estado == .programada && !$0.esCita }.sorted { $0.inicio < $1.inicio }
        if let t = programadas.first(where: { $0.inicio <= ahora }) {
            return ahora.timeIntervalSince(t.inicio) >= ventanaDecision ? .cuando(t, sinRespuesta: true) : .decidir(t)
        }
        // Las citas no piden decisión: se ven en la espera hasta que terminan.
        let citas = tareas.filter { $0.esCita && $0.estado == .programada && $0.inicio.addingTimeInterval(Double($0.duracionMinutos) * 60) > ahora }
        let proximas = Array((programadas + citas).sorted { $0.inicio < $1.inicio }.prefix(3))
        return proximas.isEmpty ? .vacio : .espera(proximas)
    }

    static func siguiente<T: DatosSlot>(despuesDe fecha: Date, en tareas: [T]) -> T? {
        tareas.filter { $0.estado == .programada && $0.inicio >= fecha }.min { $0.inicio < $1.inicio }
    }

    static func choca<T: DatosSlot>(finNuevo: Date, siguiente: T?) -> Bool {
        guard let s = siguiente else { return false }
        return s.inicio < finNuevo
    }

    /// Si un slot nuevo pisa a otro ya ocupado.
    static func solapa(_ propuesta: DateInterval, con ocupados: [DateInterval]) -> Bool {
        ocupados.contains { $0.start < propuesta.end && propuesta.start < $0.end }
    }

    /// Minutos de foco: lo trabajado en slots terminados o parados por hoy.
    static let resultadosConFoco: Set<String> = ["terminada", "paro por hoy"]

    static func redondearArriba(_ fecha: Date, minutos: Int, calendario cal: Calendar = .current) -> Date {
        let dia = cal.startOfDay(for: fecha)
        let paso = Double(minutos * 60)
        let s = fecha.timeIntervalSince(dia)
        return dia.addingTimeInterval((s / paso).rounded(.up) * paso)
    }

    /// Huecos libres donde entra la tarea, dentro del horario permitido y sin pisar otros slots.
    static func sugerencias(duracion: Int, ocupados: [DateInterval], desde ahora: Date,
                            calendario cal: Calendar = .current, apertura: Int = 8, cierre: Int = 21,
                            soloDiasHabiles: Bool = false, cantidad: Int = 3) -> [Sugerencia] {
        let dur = TimeInterval(duracion * 60)
        var resultado: [Sugerencia] = []
        var t = redondearArriba(ahora.addingTimeInterval(10 * 60), minutos: 15, calendario: cal)
        var vueltas = 0
        while resultado.count < cantidad && vueltas < 5000 {
            vueltas += 1
            let dia = cal.startOfDay(for: t)
            guard let abre = cal.date(bySettingHour: apertura, minute: 0, second: 0, of: dia),
                  let cierra = cal.date(bySettingHour: cierre, minute: 0, second: 0, of: dia),
                  let abreManana = cal.date(byAdding: .day, value: 1, to: abre) else { break }
            if soloDiasHabiles && cal.isDateInWeekend(t) { t = abreManana; continue }
            if t < abre { t = abre }
            if t.addingTimeInterval(dur) > cierra { t = abreManana; continue }
            let fin = t.addingTimeInterval(dur)
            let choques = ocupados.filter { $0.start < fin && t < $0.end }
            if let ultimo = choques.max(by: { $0.end < $1.end }) {
                t = redondearArriba(ultimo.end, minutos: 15, calendario: cal)
                continue
            }
            let proximo = ocupados.filter { $0.start >= fin }.map(\.start).min()
            resultado.append(Sugerencia(inicio: t, libreHasta: min(proximo ?? cierra, cierra)))
            t = redondearArriba(t.addingTimeInterval(max(dur, 2 * 3600)), minutos: 15, calendario: cal)
        }
        return resultado
    }
}

enum Formato {
    /// "4:32" hasta una hora; "1 h 04" desde una hora.
    static func cuenta(_ segundos: Int) -> String {
        let s = max(0, segundos)
        if s >= 3600 { return "\(s / 3600) h " + String(format: "%02d", (s % 3600) / 60) }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private static let formatoHora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f
    }()

    private static let formatoDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d"
        return f
    }()

    static func hora(_ d: Date) -> String { formatoHora.string(from: d) }

    /// "jueves, 12 de noviembre" → "Jueves, 12 de noviembre" (sin "De" en mayúscula).
    static func primeraMayuscula(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// "45 min", "1 h", "1 h 20 min".
    static func minutos(_ m: Int) -> String {
        let m = max(0, m)
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    static func diaYHora(_ d: Date, ahora: Date, calendario cal: Calendar = .current) -> String {
        if cal.isDate(d, inSameDayAs: ahora) { return "Hoy \(hora(d))" }
        if let m = cal.date(byAdding: .day, value: 1, to: ahora), cal.isDate(d, inSameDayAs: m) { return "Mañana \(hora(d))" }
        return primeraMayuscula(formatoDia.string(from: d)) + " · " + hora(d)
    }
}
