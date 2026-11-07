import SwiftUI

/// Color en RGB (0 a 1), fácil de mezclar y de probar.
struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mezcla(_ otro: RGB, _ t: Double) -> RGB {
        RGB(r: r + (otro.r - r) * t, g: g + (otro.g - g) * t, b: b + (otro.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    var luminancia: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

enum Apariencia: String, CaseIterable, Identifiable {
    case automatico, siempreDia, siempreNoche
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .automatico: "Automático"
        case .siempreDia: "Siempre día"
        case .siempreNoche: "Siempre noche"
        }
    }
}

/// Paleta "Respiro": salvia y crema de día, bosque de noche, con paso continuo entre ambas (ver diseno/DISENO.md).
struct Paleta: Equatable, Sendable {
    var fondo: RGB
    var superficie: RGB
    var texto: RGB
    var secundario: RGB
    var primario: RGB
    var linea: RGB
    var halo: RGB
    var energia: RGB

    var esOscura: Bool { fondo.luminancia < 0.45 }
    var punto: RGB { primario.mezcla(halo, 0.35) }
    static let aviso = RGB(0xB0812F)

    func mezcla(_ o: Paleta, _ t: Double) -> Paleta {
        Paleta(fondo: fondo.mezcla(o.fondo, t), superficie: superficie.mezcla(o.superficie, t),
               texto: texto.mezcla(o.texto, t), secundario: secundario.mezcla(o.secundario, t),
               primario: primario.mezcla(o.primario, t), linea: linea.mezcla(o.linea, t),
               halo: halo.mezcla(o.halo, t), energia: energia.mezcla(o.energia, t))
    }

    static let noche = Paleta(fondo: RGB(0x141A16), superficie: RGB(0x1D2520), texto: RGB(0xE6E9E1), secundario: RGB(0x99A49A),
                              primario: RGB(0x8FB197), linea: RGB(0x2F3B33), halo: RGB(0x4A6B55), energia: RGB(0x7FAE8B))
    static let manana = Paleta(fondo: RGB(0xF1F1EA), superficie: RGB(0xFBF8F1), texto: RGB(0x35302A), secundario: RGB(0x7B746A),
                               primario: RGB(0x4E6B55), linea: RGB(0xDAD1C2), halo: RGB(0xA9C2A5), energia: RGB(0x86B892))
    static let mediodia: Paleta = {
        var p = manana
        p.fondo = RGB(0xF2EDE2); p.halo = RGB(0xB6BE9B); p.energia = RGB(0xA2B07E)
        return p
    }()
    static let tarde: Paleta = {
        var p = manana
        p.fondo = RGB(0xF2E9DB); p.linea = RGB(0xDCCFBC); p.halo = RGB(0xC3B591); p.energia = RGB(0xBCA96C)
        return p
    }()
    static let ocaso = Paleta(fondo: RGB(0xD9CDB8), superficie: RGB(0xE8DFCF), texto: RGB(0x35302A), secundario: RGB(0x6E665A),
                              primario: RGB(0x4E6553), linea: RGB(0xC7B9A2), halo: RGB(0xB4A27E), energia: RGB(0xAD9C66))
    static let crepusculo = Paleta(fondo: RGB(0x56604F), superficie: RGB(0x606A59), texto: RGB(0xEEF0E8), secundario: RGB(0xC3C8BC),
                                   primario: RGB(0xB9D0BE), linea: RGB(0x6D7766), halo: RGB(0x7A8C6F), energia: RGB(0x9DB48A))
    static let alba: Paleta = {
        var p = ocaso
        p.fondo = RGB(0xE4DFCF); p.superficie = RGB(0xEFEBDF); p.linea = RGB(0xCEC6B3); p.halo = RGB(0xAEB79A); p.energia = RGB(0x9DB28A)
        return p
    }()

    /// Puntos del día; entre ellos los colores se mezclan sin saltos.
    static let puntos: [(hora: Double, paleta: Paleta)] = [
        (5, noche), (5.8, crepusculo), (6.6, alba), (8, manana), (13, mediodia),
        (18, tarde), (20.2, ocaso), (21.1, crepusculo), (21.8, noche), (24, noche)
    ]

    static func en(hora h: Double) -> Paleta {
        for i in 0..<(puntos.count - 1) {
            let (h0, p0) = puntos[i], (h1, p1) = puntos[i + 1]
            if h >= h0 && h <= h1 {
                let x = (h - h0) / (h1 - h0)
                return p0.mezcla(p1, x * x * (3 - 2 * x))
            }
        }
        return noche
    }

    static func para(_ apariencia: Apariencia, hora: Double) -> Paleta {
        switch apariencia {
        case .automatico: en(hora: hora)
        case .siempreDia: en(hora: 9.5)
        case .siempreNoche: noche
        }
    }

    static func hora(de fecha: Date, calendario cal: Calendar = .current) -> Double {
        let c = cal.dateComponents([.hour, .minute], from: fecha)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }
}

private struct ClavePaleta: EnvironmentKey {
    static let defaultValue = Paleta.manana
}

extension EnvironmentValues {
    var paleta: Paleta {
        get { self[ClavePaleta.self] }
        set { self[ClavePaleta.self] = newValue }
    }
}

extension Font {
    /// Fraunces todavía no está incluida: por ahora, la serif del sistema (New York).
    static let tituloTarea = Font.system(.largeTitle, design: .serif)
    static let pregunta = Font.system(.title2, design: .serif)
    static func numero(_ tamano: CGFloat) -> Font { .system(size: tamano, weight: .light, design: .serif) }
}

struct BotonPrimario: ButtonStyle {
    let paleta: Paleta
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(paleta.primario.color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(paleta.fondo.color)
    }
}
