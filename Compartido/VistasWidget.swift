import SwiftUI
import WidgetKit
import UIKit

// Las vistas de los widgets. Viven acá (y no solo en la extensión) para que la app pueda mostrarlas
// en las capturas del simulador.

/// Colores de "Respiro" para los widgets: de día crema y salvia, de noche bosque (sigue el modo del iPhone).
struct ColoresWidget {
    let fondo, superficie, texto, secundario, primario, halo, linea: Color

    static func para(_ esquema: ColorScheme) -> ColoresWidget {
        esquema == .dark
            ? ColoresWidget(fondo: .hex(0x141A16), superficie: .hex(0x1D2520), texto: .hex(0xE6E9E1), secundario: .hex(0x99A49A),
                            primario: .hex(0x8FB197), halo: .hex(0x4A6B55), linea: .hex(0x2F3B33))
            : ColoresWidget(fondo: .hex(0xF1F1EA), superficie: .hex(0xFBF8F1), texto: .hex(0x35302A), secundario: .hex(0x7B746A),
                            primario: .hex(0x4E6B55), halo: .hex(0xA9C2A5), linea: .hex(0xDAD1C2))
    }

    static func categoria(_ c: String) -> Color {
        switch c {
        case "cita": .hex(0xC9A35E)
        case "proyecto": .hex(0x8EA3B8)
        default: .hex(0x7FA383)
        }
    }

    static func nombre(_ c: String) -> String {
        switch c {
        case "cita": "CITA"
        case "proyecto": "PROYECTO"
        default: "TAREA"
        }
    }
}

extension Color {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum FuenteWidget {
    static func serif(_ tamano: CGFloat) -> Font {
        UIFont(name: "Fraunces-Regular", size: tamano) != nil ? .custom("Fraunces-Regular", size: tamano) : .system(size: tamano, design: .serif)
    }
    static func numero(_ tamano: CGFloat) -> Font {
        UIFont(name: "Fraunces-Light", size: tamano) != nil
            ? .custom("Fraunces-Light", size: tamano)
            : .system(size: tamano, weight: .light, design: .serif)
    }
}

extension View {
    /// El fondo del widget (en la app, para las capturas, se pinta aparte).
    func fondoWidget(_ color: Color) -> some View {
        containerBackground(for: .widget) { color }
    }
}

// MARK: Captura

struct VistaCapturaWidget: View {
    let familia: WidgetFamily
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        let c = ColoresWidget.para(esquema)
        switch familia {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2)
            }
            .widgetURL(EnlaceApp.dictar)
            .fondoWidget(.clear)
        case .systemMedium:
            HStack(spacing: 12) {
                Link(destination: EnlaceApp.dictar) { boton(c, icono: "mic.fill", texto: "Hablá", grande: true) }
                Link(destination: EnlaceApp.escribir) { boton(c, icono: "pencil", texto: "Escribí", grande: false) }
            }
            .fondoWidget(c.fondo)
        default:
            VStack(spacing: 10) {
                circulo(c, icono: "mic.fill", lado: 74)
                Text("Hablá").font(FuenteWidget.serif(20)).foregroundStyle(c.texto)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(EnlaceApp.dictar)
            .fondoWidget(c.fondo)
        }
    }

    private func circulo(_ c: ColoresWidget, icono: String, lado: CGFloat) -> some View {
        ZStack {
            Circle().fill(c.halo.opacity(0.35)).frame(width: lado * 1.25, height: lado * 1.25)
            Circle().fill(c.halo.opacity(0.7)).frame(width: lado, height: lado)
            Image(systemName: icono).font(.system(size: lado * 0.34, weight: .medium)).foregroundStyle(c.primario)
        }
    }

    private func boton(_ c: ColoresWidget, icono: String, texto: String, grande: Bool) -> some View {
        VStack(spacing: 8) {
            if grande {
                circulo(c, icono: icono, lado: 62)
            } else {
                Image(systemName: icono).font(.system(size: 24, weight: .medium)).foregroundStyle(c.primario)
                    .frame(width: 62, height: 62)
                    .background(Circle().stroke(c.linea, lineWidth: 1.5))
            }
            Text(texto).font(FuenteWidget.serif(18)).foregroundStyle(c.texto)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Lo que viene

struct VistaLoQueVieneWidget: View {
    let datos: LoQueViene?
    let fecha: Date
    let familia: WidgetFamily
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        let c = ColoresWidget.para(esquema)
        let lista = datos?.siguientes(en: fecha, cantidad: 2) ?? []
        Group {
            if let item = lista.first {
                switch familia {
                case .accessoryInline:
                    Text("\(item.titulo) · \(LoQueViene.cuando(item.inicio, desde: fecha))")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.titulo).font(.headline).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(LoQueViene.estado(item, en: fecha).texto)
                            cuenta(item).monospacedDigit()
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .systemMedium:
                    HStack(alignment: .top, spacing: 14) {
                        principal(item, c).frame(maxWidth: .infinity, alignment: .leading)
                        detalle(item, siguiente: lista.dropFirst().first, c).frame(maxWidth: .infinity, alignment: .leading)
                    }
                default:
                    principal(item, c).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                vacio(c)
            }
        }
        .widgetURL(EnlaceApp.inicio)
        .fondoWidget(familia.esPantallaBloqueada ? .clear : c.fondo)
    }

    @ViewBuilder
    private func vacio(_ c: ColoresWidget) -> some View {
        switch familia {
        case .accessoryInline, .accessoryRectangular:
            Text("Nada por ahora")
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("Nada por ahora.").font(FuenteWidget.serif(19)).foregroundStyle(c.texto)
                Text("Tocá para abrir la app.").font(.caption).foregroundStyle(c.secundario)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func principal(_ item: LoQueViene.Item, _ c: ColoresWidget) -> some View {
        let estado = LoQueViene.estado(item, en: fecha)
        let color = item.enCurso ? c.primario : ColoresWidget.categoria(item.categoria)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.enCurso ? "EN CURSO" : ColoresWidget.nombre(item.categoria))
                .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(color)
            Text(item.titulo).font(FuenteWidget.serif(18)).foregroundStyle(c.texto).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 2)
            Text(estado.texto).font(.caption).foregroundStyle(c.secundario)
            cuenta(item).font(FuenteWidget.numero(28)).monospacedDigit().foregroundStyle(c.texto)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 4) }
    }

    @ViewBuilder
    private func detalle(_ item: LoQueViene.Item, siguiente: LoQueViene.Item?, _ c: ColoresWidget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !item.lugar.isEmpty {
                Label(item.lugar, systemImage: "mappin").font(.caption).foregroundStyle(c.texto).lineLimit(1)
            }
            if !item.notas.isEmpty {
                Text(item.notas).font(.caption).foregroundStyle(c.secundario).lineLimit(item.lugar.isEmpty ? 4 : 3)
            }
            if let avance = LoQueViene.avanceProyecto(item, en: fecha), let fin = item.proyectoFin {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.proyecto ?? "").font(.caption2.weight(.semibold)).foregroundStyle(c.texto).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.linea)
                            Capsule().fill(ColoresWidget.categoria("proyecto")).frame(width: max(4, g.size.width * avance))
                        }
                    }
                    .frame(height: 5)
                    Text(textoDias(LoQueViene.diasHasta(fin, desde: fecha))).font(.caption2).foregroundStyle(c.secundario)
                }
            }
            Spacer(minLength: 0)
            if let s = siguiente {
                Text("Después: \(s.titulo) · \(LoQueViene.cuando(s.inicio, desde: fecha))")
                    .font(.caption2).foregroundStyle(c.secundario).lineLimit(2)
            }
        }
    }

    private func textoDias(_ n: Int) -> String {
        n == 0 ? "termina hoy" : n == 1 ? "falta 1 día" : "faltan \(n) días"
    }

    /// La cuenta regresiva viva, o la hora si falta mucho.
    private func cuenta(_ item: LoQueViene.Item) -> Text {
        guard let hasta = LoQueViene.estado(item, en: fecha).hasta, hasta > fecha else {
            return Text(LoQueViene.cuando(item.inicio, desde: fecha))
        }
        if hasta.timeIntervalSince(fecha) > LoQueViene.cuentaMaxima { return Text(LoQueViene.cuando(hasta, desde: fecha)) }
        return Text(timerInterval: fecha...hasta, countsDown: true)
    }
}

extension WidgetFamily {
    var esPantallaBloqueada: Bool { self == .accessoryInline || self == .accessoryRectangular || self == .accessoryCircular }
}
