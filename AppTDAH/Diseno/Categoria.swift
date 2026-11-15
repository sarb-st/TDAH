import SwiftUI

/// Las cinco categorías, cada una con su color (paleta "Bosque", ver diseno/DISENO.md).
enum Categoria: String, CaseIterable {
    case tarea, cita, proyecto, idea, inbox

    var nombre: String {
        switch self {
        case .tarea: "Tarea"
        case .cita: "Cita"
        case .proyecto: "Proyecto"
        case .idea: "Idea"
        case .inbox: "Inbox"
        }
    }

    var rgb: RGB {
        switch self {
        case .tarea: RGB(0x7FA383)
        case .cita: RGB(0xC9A35E)
        case .proyecto: RGB(0x8EA3B8)
        case .idea: RGB(0x9C92B4)
        case .inbox: RGB(0xC2B49C)
        }
    }

    /// El color para escribir el nombre de la categoría: más oscuro de día, más claro de noche, para que se lea.
    func texto(en p: Paleta) -> Color {
        (p.esOscura ? rgb.mezcla(RGB(0xFFFFFF), 0.2) : rgb.mezcla(RGB(0x2C2A25), 0.32)).color
    }

    /// Fondo suave para los bloques del calendario.
    func fondo(en p: Paleta) -> Color { p.superficie.mezcla(rgb, p.esOscura ? 0.35 : 0.3).color }
}

extension Tarea {
    var categoria: Categoria { esCita ? .cita : (proyecto != nil ? .proyecto : .tarea) }
}

/// Tarjeta con la banda de color de su categoría a la izquierda.
struct TarjetaBanda<Contenido: View>: View {
    let categoria: Categoria
    let paleta: Paleta
    var radio: CGFloat = 18
    @ViewBuilder var contenido: () -> Contenido

    var body: some View {
        contenido()
            .padding(.vertical, 12)
            .padding(.leading, 20)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paleta.superficie.color)
            .overlay(alignment: .leading) { Rectangle().fill(categoria.rgb.color).frame(width: 6) }
            .clipShape(RoundedRectangle(cornerRadius: radio))
            .overlay(RoundedRectangle(cornerRadius: radio).stroke(paleta.linea.color))
            .contentShape(RoundedRectangle(cornerRadius: radio))
    }
}

/// El nombre de la categoría escrito en su color (no es una etiqueta con fondo).
struct EtiquetaCategoria: View {
    let categoria: Categoria
    let paleta: Paleta
    var extra: String? = nil

    var body: some View {
        Text((extra.map { "\(categoria.nombre) · \($0)" } ?? categoria.nombre).uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(categoria.texto(en: paleta))
            .lineLimit(1)
    }
}

/// Líneas diagonales para tachar un slot cerrado en el calendario.
struct Rayado: Shape {
    var espacio: CGFloat = 7

    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += espacio
        }
        return p
    }
}

/// Manija ≡ para reordenar arrastrando.
struct Manija: View {
    var activa: Bool
    var cambio: (CGFloat) -> Void
    var fin: () -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body)
            .foregroundStyle(paleta.secundario.color)
            .frame(width: 36, height: 40)
            .contentShape(Rectangle())
            .opacity(activa ? 1 : 0)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { cambio($0.translation.height) }
                        .onEnded { _ in fin() },
                     including: activa ? .all : .none)
            .accessibilityHidden(!activa)
            .accessibilityLabel("Mover")
    }
}

private struct AlturasClave: PreferenceKey {
    static let defaultValue: [AnyHashable: CGFloat] = [:]
    static func reduce(value: inout [AnyHashable: CGFloat], nextValue: () -> [AnyHashable: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Una lista que se reordena arrastrando la manija de cada fila (siempre visible).
struct ListaReordenable<Item: Identifiable, Fila: View>: View {
    let items: [Item]
    var espacio: CGFloat = 8
    var movible: (Item) -> Bool
    var alMover: (_ desde: Int, _ hasta: Int) -> Void
    @ViewBuilder var fila: (Item, Manija) -> Fila

    @State private var alturas: [AnyHashable: CGFloat] = [:]
    @State private var arrastrado: AnyHashable?
    @State private var y: CGFloat = 0

    var body: some View {
        VStack(spacing: espacio) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let clave = AnyHashable(item.id)
                let esEste = arrastrado == clave
                fila(item, Manija(activa: movible(item),
                                  cambio: { t in
                                      if arrastrado == nil { arrastrado = clave }
                                      if arrastrado == clave { y = t }
                                  },
                                  fin: { soltar(clave) }))
                    .background(GeometryReader { g in
                        Color.clear.preference(key: AlturasClave.self, value: [clave: g.size.height])
                    })
                    .offset(y: desplazamiento(i, clave))
                    .zIndex(esEste ? 1 : 0)
                    .shadow(color: .black.opacity(esEste ? 0.18 : 0), radius: esEste ? 10 : 0, y: esEste ? 5 : 0)
                    .animation(esEste ? nil : .easeInOut(duration: 0.2), value: y)
            }
        }
        .onPreferenceChange(AlturasClave.self) { alturas = $0 }
        .transformPreference(AlturasClave.self) { $0 = [:] }
        .sensoryFeedback(.selection, trigger: arrastrado)
    }

    private func indice(_ clave: AnyHashable) -> Int? { items.firstIndex { AnyHashable($0.id) == clave } }

    private func destino(_ d: Int) -> Int {
        let hs = items.map { alturas[AnyHashable($0.id)] ?? 0 }
        let primero = items.firstIndex(where: movible) ?? 0
        let ultimo = items.lastIndex(where: movible) ?? max(0, items.count - 1)
        return Plan.indiceDestino(alturas: hs, desde: d, desplazamiento: y, espacio: espacio, rango: primero...max(primero, ultimo))
    }

    private func desplazamiento(_ i: Int, _ clave: AnyHashable) -> CGFloat {
        guard let a = arrastrado, let d = indice(a) else { return 0 }
        if clave == a { return y }
        let h = (alturas[a] ?? 0) + espacio
        let hasta = destino(d)
        if d < hasta, i > d, i <= hasta { return -h }
        if d > hasta, i >= hasta, i < d { return h }
        return 0
    }

    private func soltar(_ clave: AnyHashable) {
        guard arrastrado == clave, let d = indice(clave) else { return }
        let hasta = destino(d)
        var sinAnimar = Transaction()
        sinAnimar.disablesAnimations = true
        withTransaction(sinAnimar) {
            arrastrado = nil
            y = 0
            if hasta != d { alMover(d, hasta) }
        }
    }
}
