import SwiftUI
import WidgetKit
import AppIntents
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
            : ColoresWidget(fondo: .hex(0xF4F2EA), superficie: .hex(0xFBF8F1), texto: .hex(0x35302A), secundario: .hex(0x7B746A),
                            primario: .hex(0x4E6B55), halo: .hex(0xA9C2A5), linea: .hex(0xDAD1C2))
    }

    static func categoria(_ c: String) -> Color {
        switch c {
        case "cita": .hex(0xC9A35E)
        case "proyecto": .hex(0x8EA3B8)
        default: .hex(0x7FA383)
        }
    }

    /// La tinta fuerte del mismo tono, para la cuenta regresiva.
    static func tinta(_ c: String, oscuro: Bool) -> Color {
        switch c {
        case "cita": oscuro ? .hex(0xE3C48A) : .hex(0x8A6420)
        case "proyecto": oscuro ? .hex(0xB8CADB) : .hex(0x4A6580)
        default: oscuro ? .hex(0xA9CDAA) : .hex(0x3E6B47)
        }
    }

    static func nombre(_ c: String) -> String {
        switch c {
        case "cita": "CITA"
        case "proyecto": "PROYECTO"
        default: "TAREA"
        }
    }

    static let dorado = Color.hex(0xD9B26E)
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

// MARK: Las flechitas del carrusel (pasan a lo siguiente sin abrir la app)

struct PasarWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Pasar a lo siguiente"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Paso") var paso: Int

    init() { paso = 1 }
    init(paso: Int) { self.paso = paso }

    func perform() async throws -> some IntentResult {
        let total = max(1, GrupoApp.leer()?.siguientes(en: .now, cantidad: 3).count ?? 1)
        CarruselWidget.indice = ((CarruselWidget.indice + paso) % total + total) % total
        return .result()
    }
}

// MARK: Hablar (un toque abre la app en el dictado)

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
        default:
            ZStack {
                Circle().fill(c.halo.opacity(0.16)).frame(width: 126, height: 126)
                Circle().fill(c.halo.opacity(0.32)).frame(width: 102, height: 102)
                Circle().fill(esquema == .dark ? Color.hex(0x3C5444) : Color.hex(0xB7CBB3)).frame(width: 78, height: 78)
                Image(systemName: "mic").font(.system(size: 30, weight: .regular))
                    .foregroundStyle(esquema == .dark ? Color.hex(0xCFE0CC) : c.primario)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(EnlaceApp.dictar)
            .fondoWidget(c.fondo)
            .accessibilityLabel("Hablar")
        }
    }
}

// MARK: Escribir (un renglón; abre la app con el teclado listo)

struct VistaEscribirWidget: View {
    let familia: WidgetFamily
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        let c = ColoresWidget.para(esquema)
        switch familia {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                Text("Escribí algo…").font(.headline)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AccessoryWidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .widgetURL(EnlaceApp.escribir)
            .fondoWidget(.clear)
        default:
            HStack(spacing: 10) {
                Image(systemName: "pencil").font(.system(size: 17, weight: .medium)).foregroundStyle(Color.hex(0xB08A3E))
                Rectangle().fill(Color.hex(0xB08A3E)).frame(width: 2, height: 20)
                Text("Contame en qué estás…").font(.system(size: 16)).foregroundStyle(c.secundario)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(c.superficie, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(esquema == .dark ? Color.hex(0x6B5C40) : Color.hex(0xD9C49B), lineWidth: 1.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(EnlaceApp.escribir)
            .fondoWidget(c.fondo)
            .accessibilityLabel("Escribir")
        }
    }
}

// MARK: Lo que viene

struct VistaLoQueVieneWidget: View {
    let datos: LoQueViene?
    let fecha: Date
    let familia: WidgetFamily
    var indice: Int = CarruselWidget.indice
    @Environment(\.colorScheme) private var esquema

    var body: some View {
        let c = ColoresWidget.para(esquema)
        let lista = datos?.siguientes(en: fecha, cantidad: 3) ?? []
        let i = lista.isEmpty ? 0 : min(max(0, indice), lista.count - 1)
        Group {
            if let item = lista[seguro: i] {
                switch familia {
                case .accessoryInline:
                    Text("\(item.tituloVisible) · \(LoQueViene.cuando(item.inicio, desde: fecha))")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.tituloVisible).font(.headline).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(LoQueViene.estado(item, en: fecha).texto)
                            cuenta(item).monospacedDigit()
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    tarjeta(item, lista: lista, indice: i, despues: datos?.siguientes(en: fecha, cantidad: 6) ?? [], c)
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

    /// Franja de color arriba (etiqueta en blanco y flechitas), título en un renglón, la cuenta en una columna
    /// fija y, al lado, los pasos o el lugar y las notas.
    private func tarjeta(_ item: LoQueViene.Item, lista: [LoQueViene.Item], indice: Int, despues proximos: [LoQueViene.Item],
                         _ c: ColoresWidget) -> some View {
        let chico = familia == .systemSmall
        let grande = familia == .systemLarge
        let color = ColoresWidget.categoria(item.categoria)
        let etiqueta = (item.importante == true ? "★ IMPORTANTE" : (item.enCurso ? "EN CURSO" : ColoresWidget.nombre(item.categoria)))
            + " · " + LoQueViene.cuando(item.inicio, desde: fecha)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(etiqueta).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 2)
                if !chico && lista.count > 1 {
                    Button(intent: PasarWidgetIntent(paso: -1)) { flecha("chevron.left") }.buttonStyle(.plain)
                    HStack(spacing: 4) {
                        ForEach(0..<lista.count, id: \.self) { k in
                            Circle().fill(.white.opacity(k == indice ? 1 : 0.45)).frame(width: 5, height: 5)
                        }
                    }
                    Button(intent: PasarWidgetIntent(paso: 1)) { flecha("chevron.right") }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(color)
            Text(item.tituloVisible)
                .font(FuenteWidget.serif(chico ? 17 : 20))
                .foregroundStyle(c.texto)
                .lineLimit(chico ? 2 : 1)
                .padding(.horizontal, 14)
                .padding(.top, chico ? 12 : 10)
            if grande {
                // El grande: cuenta y pasos pegados al título; lugar y nota en cajitas; el aire queda antes de "Después".
                bloqueGrande(item, c).padding(.horizontal, 14).padding(.top, 12)
                Spacer(minLength: 8)
                let otras = proximos.filter { $0 != item }
                if !otras.isEmpty {
                    despues(Array(otras.prefix(cabenDespues(item))), c).padding(.horizontal, 14).padding(.bottom, 14)
                }
            } else if chico {
                Spacer(minLength: 4)
                columnaCuenta(item, c).padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                Spacer(minLength: 4)
                HStack(alignment: .bottom, spacing: 12) {
                    columnaCuenta(item, c).frame(width: 100, alignment: .leading)
                    detalle(item, maximo: 2, c).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .overlay {
            if item.importante == true {
                ContainerRelativeShape().inset(by: 1.5).stroke(ColoresWidget.dorado, lineWidth: 3)
            }
        }
    }

    private func flecha(_ icono: String) -> some View {
        Image(systemName: icono).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.2), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.5)))
    }

    private func columnaCuenta(_ item: LoQueViene.Item, _ c: ColoresWidget) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LoQueViene.estado(item, en: fecha).texto).font(.system(size: 11.5)).foregroundStyle(c.secundario)
            cuenta(item)
                .font(FuenteWidget.numero(30))
                .monospacedDigit()
                .foregroundStyle(ColoresWidget.tinta(item.categoria, oscuro: esquema == .dark))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    @ViewBuilder
    private func detalle(_ item: LoQueViene.Item, maximo: Int, _ c: ColoresWidget) -> some View {
        let color = ColoresWidget.categoria(item.categoria)
        if let pasos = item.pasos, !pasos.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pasos.prefix(maximo).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 6) {
                        Circle().stroke(color, lineWidth: 1.8).frame(width: 10, height: 10)
                        Text(p).font(.system(size: 12.5)).foregroundStyle(c.texto).lineLimit(1)
                    }
                }
                if pasos.count > maximo {
                    Text("y \(pasos.count - maximo) más").font(.system(size: 11.5)).foregroundStyle(c.secundario).padding(.leading, 16)
                }
            }
        } else if let avance = LoQueViene.avanceProyecto(item, en: fecha), let fin = item.proyectoFin {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.proyecto ?? "") · \(textoDias(LoQueViene.diasHasta(fin, desde: fecha)))")
                    .font(.system(size: 12.5)).foregroundStyle(c.secundario).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.linea)
                        Capsule().fill(color).frame(width: max(4, g.size.width * avance))
                    }
                }
                .frame(height: 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if !item.lugar.isEmpty { Text(item.lugar).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(c.texto).lineLimit(1) }
                if !item.notas.isEmpty { Text(item.notas).font(.system(size: 12.5)).foregroundStyle(c.secundario).lineLimit(3) }
            }
        }
    }

    // MARK: El bloque central del grande

    /// Una nota que no entra en un renglón de la cajita.
    private func notaLarga(_ item: LoQueViene.Item) -> Bool { item.notas.count > 34 }

    /// Con dos cajitas (o la nota a todo el ancho) entran 3 en "Después"; con un renglón o nada, 4.
    private func cabenDespues(_ item: LoQueViene.Item) -> Int {
        let hayPasos = !(item.pasos ?? []).isEmpty
        let lugar = !item.lugar.isEmpty, nota = !item.notas.isEmpty
        if hayPasos { return lugar && nota ? 3 : 4 }
        return nota && notaLarga(item) ? 3 : 4
    }

    @ViewBuilder
    private func bloqueGrande(_ item: LoQueViene.Item, _ c: ColoresWidget) -> some View {
        let pasos = item.pasos ?? []
        let lugar = !item.lugar.isEmpty, nota = !item.notas.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    columnaCuenta(item, c)
                    Text("\(LoQueViene.cuando(item.inicio, desde: fecha)) – \(LoQueViene.formatoHora.string(from: item.fin))")
                        .font(.system(size: 11)).foregroundStyle(c.secundario).monospacedDigit().lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)
                Rectangle().fill(c.linea).frame(width: 1).frame(maxHeight: .infinity)
                if !pasos.isEmpty {
                    listaPasos(pasos, item, c)
                } else if lugar || nota {
                    // Sin pasos: el lugar (y la nota corta) a la derecha de la cuenta, centrados en el alto.
                    VStack(alignment: .leading, spacing: 6) {
                        if lugar { cajita("mappin.and.ellipse", "Lugar", item.lugar, renglones: 1, c) }
                        if nota && !notaLarga(item) { cajita("note.text", "Nota", item.notas, renglones: 1, c) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    detalle(item, maximo: 4, c).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !pasos.isEmpty {
                if lugar && nota {
                    HStack(alignment: .top, spacing: 7) {
                        // El lugar ocupa menos que la nota.
                        cajita("mappin.and.ellipse", "Lugar", item.lugar, renglones: 1, c).frame(width: 118)
                        cajita("note.text", "Nota", item.notas, renglones: 1, c).frame(maxWidth: .infinity)
                    }
                } else if lugar {
                    renglon("mappin.and.ellipse", "Lugar", item.lugar, c)
                } else if nota {
                    renglon("note.text", "Nota", item.notas, c)
                }
            } else if nota && notaLarga(item) {
                cajita("note.text", "Nota", item.notas, renglones: 3, c)
            }
        }
    }

    private func listaPasos(_ pasos: [String], _ item: LoQueViene.Item, _ c: ColoresWidget) -> some View {
        let color = ColoresWidget.categoria(item.categoria)
        let maximo = 4
        let mostrar = pasos.count > maximo ? Array(pasos.prefix(maximo - 1)) : pasos
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(mostrar.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 7) {
                    Circle().stroke(color, lineWidth: 1.8).frame(width: 13, height: 13)
                    Text(p).font(.system(size: 15)).foregroundStyle(c.texto).lineLimit(1)
                }
            }
            if pasos.count > maximo {
                Text("y \(pasos.count - mostrar.count) más").font(.system(size: 12.5)).foregroundStyle(c.secundario).padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Una cajita con rótulo (ícono y "LUGAR" o "NOTA") y el texto debajo.
    private func cajita(_ icono: String, _ rotulo: String, _ texto: String, renglones: Int, _ c: ColoresWidget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(rotulo.uppercased(), systemImage: icono)
                .font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                .foregroundStyle(c.primario)
                .labelStyle(EtiquetaApretada())
            Text(texto).font(.system(size: 13, weight: .medium)).foregroundStyle(c.texto)
                .lineLimit(renglones).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(c.linea.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    /// La cajita en un solo renglón: rótulo y texto uno al lado del otro (entra una dirección larga).
    private func renglon(_ icono: String, _ rotulo: String, _ texto: String, _ c: ColoresWidget) -> some View {
        HStack(spacing: 8) {
            Label(rotulo.uppercased(), systemImage: icono)
                .font(.system(size: 9.5, weight: .bold)).tracking(0.5)
                .foregroundStyle(c.primario)
                .labelStyle(EtiquetaApretada())
                .fixedSize()
            Text(texto).font(.system(size: 13, weight: .medium)).foregroundStyle(c.texto).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(c.linea.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func despues(_ otras: [LoQueViene.Item], _ c: ColoresWidget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("DESPUÉS").font(.system(size: 11, weight: .bold)).foregroundStyle(c.secundario)
            ForEach(Array(otras.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(ColoresWidget.categoria(s.categoria)).frame(width: 5, height: 18)
                    Text(s.tituloVisible).font(.system(size: 14, weight: .medium)).foregroundStyle(c.texto).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(LoQueViene.cuando(s.inicio, desde: fecha)).font(.system(size: 13)).foregroundStyle(c.secundario).monospacedDigit()
                }
            }
        }
    }

    private func textoDias(_ n: Int) -> String {
        n == 0 ? "termina hoy" : n == 1 ? "falta 1 día" : "faltan \(n) días"
    }

    /// La cuenta regresiva viva, o la hora si falta mucho (más de 6 h).
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

extension Array {
    /// Leer sin salirse: nil si el índice no existe.
    subscript(seguro i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Ícono y texto bien juntos, para los rótulos de las cajitas del widget.
struct EtiquetaApretada: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}
