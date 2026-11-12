import SwiftUI

/// El protagonista de la app: un círculo sin línea con un halo que respira (ver diseno/DISENO.md).
struct CirculoQueRespira<Contenido: View>: View {
    var halo: RGB
    var fondo: RGB
    var diametro: CGFloat = Medidas.circulo
    /// 0 = respiración normal; 1 = el halo se agranda (al sostener "Ahora no" o al celebrar).
    var intensidad: Double = 0
    @ViewBuilder var contenido: () -> Contenido

    @State private var motor = MotorHalo()
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    var body: some View {
        contenido()
            .frame(width: diametro, height: diametro)
            .background {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { linea in
                    Canvas { gc, tamano in
                        motor.dibujar(gc, tamano: tamano, fecha: linea.date, halo: halo, fondo: fondo, quieto: reducirMovimiento, intensidad: intensidad)
                    }
                }
                .frame(width: diametro * 2, height: diametro * 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

enum Medidas {
    static let circulo: CGFloat = 168
    /// Centro óptico: un poco por encima de la mitad.
    static let alturaCentro: CGFloat = 0.48
}

/// Dibuja el halo: banda pegada al borde, capas hacia afuera sin borde final y capas cortas hacia adentro.
/// La forma cambia en cada respiración y gira despacio.
final class MotorHalo {
    struct Onda { let k: Double; let a: Double; let p: Double }

    private var a = MotorHalo.semilla()
    private var b = MotorHalo.semilla()
    private var ciclo: Int?
    private let desfase = Double.random(in: 0..<1)

    static let periodo = 7.0
    static let inhala = 0.43
    static let expansion = 1.75

    static func semilla() -> [Onda] {
        [2.0, 3, 4, 5].map { Onda(k: $0, a: .random(in: 0.35...1), p: .random(in: 0...(2 * .pi))) }
    }

    static func suave(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }

    /// 0 = exhalado, 1 = inhalado.
    static func respiro(fase: Double) -> Double {
        fase < inhala ? suave(fase / inhala) : suave(1 - (fase - inhala) / (1 - inhala))
    }

    func dibujar(_ gc: GraphicsContext, tamano: CGSize, fecha: Date, halo: RGB, fondo: RGB, quieto: Bool, intensidad: Double = 0) {
        let tt = fecha.timeIntervalSinceReferenceDate + desfase * Self.periodo
        let n = Int((tt / Self.periodo).rounded(.down))
        let fase = tt / Self.periodo - Double(n)
        if ciclo == nil {
            ciclo = n
        } else if ciclo != n {
            ciclo = n
            if !quieto { a = b; b = Self.semilla() }
        }
        let respiro = quieto ? 0.6 : Self.respiro(fase: fase)
        let giro = quieto ? 0 : tt * 0.06
        let m = quieto ? 0 : Self.suave(fase)

        let c = CGPoint(x: tamano.width / 2, y: tamano.height / 2)
        let r = Double(tamano.width) / 4
        let banda = 5.0
        let maxExt = r * (Self.expansion - 1) * 1.6
        let k = max(0, min(1, intensidad))
        let ext = maxExt * (0.15 + 0.85 * respiro) * (1 + 0.9 * k) + maxExt * 0.4 * k
        let haciaAdentro = 9 + 5 * (1 - respiro)

        var forma = [Double](repeating: 0.5, count: 121)
        for i in 0...120 {
            let t = Double(i) / 120 * 2 * .pi
            var s = 0.0, suma = 0.0
            for j in 0..<4 {
                let aa = a[j].a + (b[j].a - a[j].a) * m
                let pp = a[j].p + (b[j].p - a[j].p) * m
                s += aa * sin(a[j].k * t + pp + giro)
                suma += aa
            }
            forma[i] = 0.5 + 0.5 * s / suma
        }

        func mancha(_ radio: (Int) -> Double) -> Path {
            var p = Path()
            for i in 0...120 {
                let t = Double(i) / 120 * 2 * .pi
                let rr = radio(i)
                let punto = CGPoint(x: c.x + rr * cos(t), y: c.y + rr * sin(t))
                if i == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
            }
            p.closeSubpath()
            return p
        }

        let colorHalo = halo.color
        let colorFondo = fondo.color
        gc.fill(mancha { _ in r + banda }, with: .color(colorHalo.opacity(0.95)))
        for capa in 1...22 {
            let q = pow(Double(capa) / 22, 1.6)
            gc.fill(mancha { i in r + banda + ext * q * (0.35 + 0.65 * forma[i]) },
                    with: .color(colorHalo.opacity((0.08 + 0.1 * respiro + 0.06 * k) * (1 - q * 0.5))))
        }
        for capa in 0...18 {
            let q = Double(capa) / 18
            gc.fill(mancha { i in r - haciaAdentro * q * (0.35 + 0.65 * forma[(i + 40) % 120]) },
                    with: .color(colorFondo.opacity(0.2)))
        }
        gc.fill(mancha { i in r - haciaAdentro * (0.35 + 0.65 * forma[(i + 40) % 120]) - 1 }, with: .color(colorFondo))
    }
}

/// El punto que invita a decidir.
struct PuntoQueLate: View {
    @Environment(\.paleta) private var paleta
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var late = false

    var body: some View {
        ZStack {
            Circle().stroke(paleta.punto.color.opacity(0.5), lineWidth: 1).frame(width: 30, height: 30)
            Circle().fill(paleta.punto.color).frame(width: 17, height: 17)
                .scaleEffect(late ? 1.18 : 1)
                .opacity(late ? 0.6 : 0.85)
        }
        .onAppear {
            guard !reducirMovimiento else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { late = true }
        }
    }
}

/// Encabezado común: etiqueta chica, título de la tarea y detalle.
struct Encabezado: View {
    let etiqueta: String
    let titulo: String
    let detalle: String
    @Environment(\.paleta) private var paleta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(etiqueta.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(paleta.secundario.color)
            Text(titulo)
                .font(.tituloTarea)
                .foregroundStyle(paleta.texto.color)
                .lineLimit(3)
            Text(detalle)
                .font(.subheadline)
                .foregroundStyle(paleta.secundario.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pone el círculo siempre en el mismo lugar, con contenido arriba y abajo.
struct LienzoCirculo<Arriba: View, Centro: View, Abajo: View>: View {
    let arriba: Arriba
    let centro: Centro
    let abajo: Abajo

    init(@ViewBuilder arriba: () -> Arriba, @ViewBuilder centro: () -> Centro, @ViewBuilder abajo: () -> Abajo) {
        self.arriba = arriba()
        self.centro = centro()
        self.abajo = abajo()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    arriba
                    Spacer(minLength: 0)
                    abajo
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(width: geo.size.width, height: geo.size.height)
                centro.position(x: geo.size.width / 2, y: geo.size.height * Medidas.alturaCentro)
            }
        }
    }
}
