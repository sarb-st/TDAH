import Foundation
import CoreGraphics

/// Cuentas de los planes de proyecto: las etapas van una detrás de otra, cada una con su duración.
/// Se guardan como fechas de fin; la etapa siguiente empieza donde termina la anterior.
enum Plan {
    /// Lo mínimo que puede durar una etapa.
    static let minimo: TimeInterval = 3600

    static func duraciones(inicio: Date, fines: [Date]) -> [TimeInterval] {
        var r: [TimeInterval] = []
        var desde = inicio
        for f in fines {
            r.append(max(0, f.timeIntervalSince(desde)))
            desde = max(desde, f)
        }
        return r
    }

    static func fines(inicio: Date, duraciones: [TimeInterval]) -> [Date] {
        var r: [Date] = []
        var t = inicio
        for d in duraciones {
            t = t.addingTimeInterval(max(0, d))
            r.append(t)
        }
        return r
    }

    /// Cambia lo que dura la etapa `i`; las siguientes se corren y mantienen su duración.
    static func cambiarDuracion(inicio: Date, fines: [Date], indice i: Int, a nueva: TimeInterval) -> [Date] {
        var d = duraciones(inicio: inicio, fines: fines)
        guard d.indices.contains(i) else { return fines }
        d[i] = max(minimo, nueva)
        return Plan.fines(inicio: inicio, duraciones: d)
    }

    /// Achica las etapas que vienen después de `i`, en proporción, para que la última termine en `limite`.
    /// Devuelve nil si no entran (no hay etapas después, o no queda al menos una hora para cada una).
    static func achicar(inicio: Date, fines: [Date], despuesDe i: Int, limite: Date) -> [Date]? {
        var d = duraciones(inicio: inicio, fines: fines)
        guard d.indices.contains(i), i + 1 < d.count else { return nil }
        let finI = Plan.fines(inicio: inicio, duraciones: Array(d[...i])).last ?? inicio
        let cantidad = d.count - i - 1
        let disponible = limite.timeIntervalSince(finI)
        guard disponible >= minimo * Double(cantidad) else { return nil }
        let total = d[(i + 1)...].reduce(0, +)
        for k in (i + 1)..<d.count {
            d[k] = total > 0 ? d[k] * disponible / total : disponible / Double(cantidad)
        }
        var r = Plan.fines(inicio: inicio, duraciones: d)
        r[r.count - 1] = limite
        return r
    }

    /// Reparte el tiempo entre `inicio` y `fin` según los pesos (por ejemplo, los días que propuso la IA).
    /// Si las etapas duran días, los cortes caen a medianoche.
    static func repartir(inicio: Date, fin: Date, pesos: [Double], calendario cal: Calendar = .current) -> [Date] {
        let suma = pesos.reduce(0, +)
        guard !pesos.isEmpty, suma > 0, fin > inicio else { return pesos.map { _ in fin } }
        let total = fin.timeIntervalSince(inicio)
        let porDia = total >= Double(pesos.count) * 86_400
        var r: [Date] = []
        var acumulado = 0.0
        for (k, p) in pesos.enumerated() {
            acumulado += p
            if k == pesos.count - 1 { r.append(fin); break }
            var corte = inicio.addingTimeInterval(total * acumulado / suma)
            if porDia {
                let dia = cal.startOfDay(for: corte.addingTimeInterval(43_200))
                if dia > (r.last ?? inicio) && dia < fin { corte = dia }
            }
            r.append(max(corte, r.last ?? inicio))
        }
        return r
    }

    /// Mueve un elemento de una posición a otra.
    static func mover<T>(_ lista: [T], desde: Int, hasta: Int) -> [T] {
        var l = lista
        guard l.indices.contains(desde), l.indices.contains(hasta) else { return lista }
        let x = l.remove(at: desde)
        l.insert(x, at: hasta)
        return l
    }

    /// A qué posición va una fila arrastrada, según cuánto se movió y lo que miden las demás.
    static func indiceDestino(alturas: [CGFloat], desde d: Int, desplazamiento y: CGFloat,
                              espacio: CGFloat, rango: ClosedRange<Int>) -> Int {
        guard alturas.indices.contains(d) else { return d }
        var destino = d
        var acumulado: CGFloat = 0
        if y > 0 {
            var j = d + 1
            while j < alturas.count {
                let paso = alturas[j] + espacio
                guard y > acumulado + paso / 2 else { break }
                destino = j
                acumulado += paso
                j += 1
            }
        } else if y < 0 {
            var j = d - 1
            while j >= 0 {
                let paso = alturas[j] + espacio
                guard -y > acumulado + paso / 2 else { break }
                destino = j
                acumulado += paso
                j -= 1
            }
        }
        return min(max(destino, rango.lowerBound), rango.upperBound)
    }
}

extension Formato {
    /// "6 h", "1 día", "5 días", "3 semanas y 5 días".
    static func duracion(_ s: TimeInterval) -> String {
        let horas = Int((s / 3600).rounded())
        if horas < 24 { return horas <= 1 ? "1 h" : "\(horas) h" }
        let dias = Int((s / 86_400).rounded())
        if dias < 7 { return dias == 1 ? "1 día" : "\(dias) días" }
        let semanas = dias / 7, resto = dias % 7
        let texto = semanas == 1 ? "1 semana" : "\(semanas) semanas"
        return resto == 0 ? texto : texto + " y " + (resto == 1 ? "1 día" : "\(resto) días")
    }

    private static let formatoDiaCorto: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let formatoDiaSemana: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// "17 nov".
    static func diaCorto(_ d: Date) -> String { formatoDiaCorto.string(from: d).replacingOccurrences(of: ".", with: "") }

    /// "lun 17 nov".
    static func diaSemana(_ d: Date) -> String { formatoDiaSemana.string(from: d).replacingOccurrences(of: ".", with: "") }

    /// "10 nov – 23 nov", o "24 nov · 10:00 a 14:00" si dura menos de un día.
    static func rango(_ inicio: Date, _ fin: Date, calendario cal: Calendar = .current) -> String {
        if fin.timeIntervalSince(inicio) < 86_400 * 0.99 {
            return "\(diaCorto(inicio)) · \(hora(inicio)) a \(hora(fin))"
        }
        let ultimo = fin.addingTimeInterval(-60)
        if cal.isDate(inicio, inSameDayAs: ultimo) { return diaCorto(inicio) }
        return "\(diaCorto(inicio)) – \(diaCorto(ultimo))"
    }
}
