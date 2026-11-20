import SwiftUI
import SwiftData
import UIKit

// MARK: - Arriba

/// Arriba de la pantalla principal: a la izquierda Vos (la personita), a la derecha Ajustes (el engranaje).
struct BarraSuperior: View {
    let navegacion: Navegacion
    @Environment(\.paleta) private var paleta

    var body: some View {
        HStack {
            Button(action: navegacion.vos) { FotoPerfil(lado: 30).frame(width: 44, height: 44) }
                .accessibilityLabel("Vos")
            Spacer()
            Button(action: navegacion.ajustes) { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                .accessibilityLabel("Ajustes")
        }
        .font(.title3)
        .foregroundStyle(paleta.primario.color)
        .padding(.horizontal, 10)
    }
}

/// La foto de Vos o, si no hay, la personita.
struct FotoPerfil: View {
    var lado: CGFloat
    var conBorde = false
    @AppStorage("fotoPerfil") private var version = 0
    @AppStorage(Perfil.clave) private var datos = Data()
    @Environment(\.paleta) private var paleta

    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("perfil.jpg") }

    var body: some View {
        Group {
            if version > 0, let img = UIImage(contentsOfFile: FotoPerfil.url.path) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: lado, height: lado)
                    .clipShape(Circle())
            } else if conBorde {
                let inicial = String(Perfil.desde(datos).nombre.prefix(1)).uppercased()
                Group {
                    if inicial.isEmpty { Image(systemName: "person").font(.system(size: lado * 0.4)) }
                    else { Text(inicial).font(.serif(lado * 0.42, relativoA: .title)) }
                }
                .frame(width: lado, height: lado)
                .foregroundStyle(paleta.primario.color)
                .background(paleta.superficie.color, in: Circle())
                .overlay(Circle().stroke(paleta.primario.color.opacity(0.55), lineWidth: 2))
            } else {
                Image(systemName: "person")
            }
        }
        .id(version)
    }
}

struct Navegacion {
    var ajustes: () -> Void
    var vos: () -> Void
    var lista: () -> Void
    var calendario: () -> Void
    var cajon: () -> Void
}

// MARK: - Inicio

/// Hacia dónde se estira el halo.
enum Direccion: CaseIterable {
    case izquierda, derecha, arriba, abajo

    var nombre: String {
        switch self {
        case .izquierda: "Calendario"
        case .derecha: "Listado"
        case .arriba: "Cajón"
        case .abajo: "Ver todo"
        }
    }

    var icono: String {
        switch self {
        case .izquierda: "calendar"
        case .derecha: "list.bullet"
        case .arriba: "tray"
        case .abajo: "rectangle.stack"
        }
    }

    var horizontal: Bool { self == .arriba || self == .abajo }
}

/// La pantalla principal: el círculo es el micrófono (un toque y escucha; mantenerlo apretado, escribir).
/// Apoyando el dedo en cualquier lugar, el halo se estira hacia el dedo como un imán; llevándolo hasta una de las
/// cuatro medias pastillas y soltando, se abre (calendario, listado, cajón, ver todo). La de abajo asoma por encima
/// de las tarjetas del fichero; tocar las tarjetas las despliega.
struct InicioView: View {
    let tareas: [Tarea]
    let ahora: Date
    let navegacion: Navegacion
    let captura: CapturaInicio
    var importante: Tarea? = nil
    var onAbrir: (Tarea) -> Void = { _ in }
    var onTermine: (Tarea) -> Void = { _ in }

    @Environment(\.paleta) private var paleta
    @Environment(\.modelContext) private var ctx
    @AppStorage(Perfil.clave) private var datosPerfil = Data()
    @State private var dedo: CGPoint?
    @State private var punta: CGSize = .zero
    @State private var encendida: Direccion?
    @State private var ficheroAbierto = false
    @State private var altoFichero: CGFloat = 0

    /// Hasta dónde llega la gota (casi hasta el dedo) y desde dónde se enciende una pastilla.
    private let alcance: CGFloat = 250
    private let umbral: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let centro = CGPoint(x: geo.size.width / 2, y: geo.size.height * Medidas.alturaCentro)
            let escuchando = captura.dictado.escuchando || captura.dictado.reintentando
            let tocando = dedo != nil
            ZStack(alignment: .top) {
                // El fondo recibe el dedo: el halo se estira hacia él.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { mover($0.location, centro: centro) }
                                .onEnded { _ in soltar() })

                BarraSuperior(navegacion: navegacion)

                // El imán: el verde salvia (más oscuro que el halo), bien opaco y poco difuso, para que se vea.
                HaloEstirado(punta: punta, radio: Medidas.circulo / 2 * 1.08, alcance: alcance)
                    .fill(halo.mezcla(paleta.primario, 0.45).color)
                    .blur(radius: 8)
                    .opacity(tocando ? 0.62 : 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: centro.x, y: centro.y)
                    .allowsHitTesting(false)

                circulo
                    .offset(x: punta.width * 0.16, y: punta.height * 0.16)
                    .position(x: centro.x, y: centro.y)

                ForEach(Direccion.allCases, id: \.self) { d in
                    pastilla(d, tocando: tocando)
                        .position(posicion(d, centro: centro, tamano: geo.size, tocando: tocando))
                }

                if tocando, let d = direccionActual {
                    Text((cerca ? "Soltá para abrir " : "Seguí hacia ") + d.nombre.lowercased())
                        .font(.serif(17, relativoA: .headline))
                        .foregroundStyle(paleta.primario.color)
                        .position(x: centro.x, y: centro.y - Medidas.circulo * 0.95)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                pistaYListo(escuchando: escuchando)
                    .padding(.horizontal, 30)
                    .position(x: centro.x, y: centro.y + Medidas.circulo * 0.82)

                VStack {
                    Spacer()
                    if tareas.isEmpty {
                        Text("Nada a la vista por ahora.")
                            .font(.subheadline)
                            .foregroundStyle(paleta.secundario.color)
                            .padding(.bottom, 24)
                    } else {
                        Fichero(tareas: tareas, ahora: ahora, abierto: $ficheroAbierto, importante: importante,
                                firme: Perfil.desde(datosPerfil).firme,
                                onAbrir: onAbrir, onTermine: onTermine)
                            .background(GeometryReader { g in
                                Color.clear
                                    .onAppear { altoFichero = g.size.height }
                                    .onChange(of: g.size.height) { _, alto in altoFichero = alto }
                            })
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.3), value: tocando)
            .onChange(of: encendida) { _, nueva in if nueva != nil { Haptica.pastilla() } }
        }
    }

    private var halo: RGB {
        let enCurso = tareas.contains { $0.estado == .enCurso }
        return enCurso ? paleta.halo.mezcla(paleta.energia, 0.55) : paleta.halo
    }

    // MARK: El imán

    private var direccionActual: Direccion? {
        let ax = abs(punta.width), ay = abs(punta.height)
        guard max(ax, ay) >= 22 else { return nil }
        return ax >= ay ? (punta.width < 0 ? .izquierda : .derecha) : (punta.height < 0 ? .arriba : .abajo)
    }

    private var cerca: Bool { max(abs(punta.width), abs(punta.height)) >= umbral }

    private func mover(_ p: CGPoint, centro: CGPoint) {
        guard !captura.dictado.escuchando else { return }
        dedo = p
        let dx = p.x - centro.x, dy = p.y - centro.y
        let d = max(1, hypot(dx, dy))
        let largo = min(d * 0.94, alcance)
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.72)) {
            punta = CGSize(width: dx / d * largo, height: dy / d * largo)
        }
        encendida = cerca ? direccionActual : nil
    }

    private func soltar() {
        let abrir = encendida
        dedo = nil
        encendida = nil
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { punta = .zero }
        switch abrir {
        case .izquierda: navegacion.calendario()
        case .derecha: navegacion.lista()
        case .arriba: navegacion.cajon()
        case .abajo: navegacion.lista()
        case nil: break
        }
    }

    // MARK: Las medias pastillas

    private func posicion(_ d: Direccion, centro: CGPoint, tamano: CGSize, tocando: Bool) -> CGPoint {
        // En reposo asoman apenas desde el borde; al apoyar el dedo entran enteras.
        switch d {
        case .izquierda: CGPoint(x: tocando ? 32 : 2, y: centro.y)
        case .derecha: CGPoint(x: tamano.width - (tocando ? 32 : 2), y: centro.y)
        case .arriba: CGPoint(x: centro.x, y: tocando ? 80 : 52)
        case .abajo:
            // Asoma por encima de las tarjetas (la mitad queda detrás) y, al apoyar el dedo, sube entera con aire.
            // Si asoma la solapa dorada de la importante, se corre por encima de ella.
            let techo = tareas.isEmpty ? tamano.height : tamano.height - 10 - altoFichero
            let solapa: CGFloat = haySolapa ? 30 : 0
            CGPoint(x: centro.x, y: techo - solapa - (tocando ? 21 + 16 : 0))
        }
    }

    /// Igual que en el Fichero: en firme, la solapa dorada asoma si la importante no es la primera.
    private var haySolapa: Bool {
        guard Perfil.desde(datosPerfil).firme, !ficheroAbierto, let imp = importante else { return false }
        return tareas.first?.uid != imp.uid
    }

    private func pastilla(_ d: Direccion, tocando: Bool) -> some View {
        let luz = encendida == d
        let forma = Capsule()
        return VStack(spacing: 3) {
            Image(systemName: d.icono)
                .font(.system(size: 16, weight: .medium))
                .opacity(tocando ? 1 : 0)
                .frame(width: d.horizontal ? 84 : 42, height: d.horizontal ? 42 : 84)
                .foregroundStyle(luz ? paleta.fondo.color : paleta.primario.color)
                .background(luz ? paleta.primario.color : paleta.primario.mezcla(paleta.fondo, 0.88).color, in: forma)
                .overlay(forma.stroke(paleta.primario.color.opacity(0.22)))
                .scaleEffect(luz ? 1.1 : 1)
        }
        .overlay(alignment: d == .abajo ? .top : .bottom) {
            if tocando {
                Text(d.nombre).font(.caption2).foregroundStyle(paleta.primario.color)
                    .fixedSize()
                    .offset(y: d == .abajo ? -16 : 16)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Círculo

    @ViewBuilder
    private func pistaYListo(escuchando: Bool) -> some View {
        VStack(spacing: 8) {
            if escuchando {
                Button("Listo") { captura.terminar(ctx: ctx) }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 26).padding(.vertical, 10)
                    .background(paleta.superficie.color, in: Capsule())
                    .overlay(Capsule().stroke(paleta.linea.color))
                    .foregroundStyle(paleta.primario.color)
            } else if let error = captura.dictado.error {
                Text(error).font(.footnote).foregroundStyle(Paleta.aviso.color).multilineTextAlignment(.center)
                Button("Escribirlo") { captura.escribiendo = true }.font(.footnote.weight(.semibold))
            } else if !captura.pensando {
                VStack(spacing: 2) {
                    Text("Tocá para hablar").font(.subheadline).foregroundStyle(paleta.secundario.color)
                    Text("Apoyá el dedo y llevá el halo").font(.caption).foregroundStyle(paleta.primario.color)
                    Button("o escribilo") { captura.escribiendo = true }
                        .font(.caption.weight(.medium))
                        .underline()
                        .foregroundStyle(paleta.primario.color)
                        .padding(.top, 2)
                        .accessibilityLabel("Escribir en vez de dictar")
                }
                .opacity(dedo == nil ? 1 : 0)
            }
        }
    }

    private var circulo: some View {
        let escuchando = captura.dictado.escuchando
        let intensidad = escuchando ? 0.25 : (captura.pensando ? 0.2 : 0)
        let colorHalo = escuchando ? paleta.energia : halo
        return CirculoQueRespira(halo: colorHalo, fondo: paleta.fondo, intensidad: intensidad,
                                 voz: escuchando ? captura.dictado.nivel : 0) {
            Group {
                if captura.pensando {
                    Image(systemName: "brain")
                        .symbolEffect(.pulse, options: .repeating)
                } else if escuchando || captura.dictado.reintentando {
                    // Micrófono → oreja → cerebro.
                    Image(systemName: "ear")
                        .scaleEffect(1 + captura.dictado.nivel * 0.25)
                        .animation(.easeOut(duration: 0.12), value: captura.dictado.nivel)
                } else {
                    Image(systemName: "mic")
                }
            }
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(paleta.primario.color)
            .frame(width: Medidas.circulo, height: Medidas.circulo)
            .contentShape(Circle())
            .onTapGesture { captura.tocar(ctx: ctx) }
            .onLongPressGesture(minimumDuration: 0.6) { captura.escribiendo = true }
        }
        .accessibilityElement()
        .accessibilityLabel(captura.pensando ? "Ordenando lo que dijiste" : (escuchando ? "Dejar de escuchar" : "Dictar"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { captura.tocar(ctx: ctx) }
        .accessibilityAction(named: "Escribir") { captura.escribiendo = true }
        .accessibilityAction(named: "Calendario") { navegacion.calendario() }
        .accessibilityAction(named: "Listado") { navegacion.lista() }
        .accessibilityAction(named: "Cajón") { navegacion.cajon() }
    }
}

/// El halo que se estira: un círculo en el centro, otro más chico en la punta y el puente entre los dos
/// (sus tangentes exteriores). Se anima la punta.
struct HaloEstirado: Shape {
    var punta: CGSize
    var radio: CGFloat
    var alcance: CGFloat = 160

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(punta.width, punta.height) }
        set { punta = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let ext = min(1, hypot(punta.width, punta.height) / alcance)
        let base = CGPoint(x: c.x + punta.width * 0.12, y: c.y + punta.height * 0.12)
        let tip = CGPoint(x: c.x + punta.width, y: c.y + punta.height)
        let r1 = radio
        let r2 = radio * (1 - ext * 0.3)
        var p = Path()
        p.addEllipse(in: CGRect(x: base.x - r1, y: base.y - r1, width: r1 * 2, height: r1 * 2))
        let dx = tip.x - base.x, dy = tip.y - base.y, d = hypot(dx, dy)
        guard d > 2, d > abs(r1 - r2) else { return p }
        p.addEllipse(in: CGRect(x: tip.x - r2, y: tip.y - r2, width: r2 * 2, height: r2 * 2))
        let a = atan2(dy, dx), b = acos((r1 - r2) / d)
        func punto(_ o: CGPoint, _ rr: CGFloat, _ ang: CGFloat) -> CGPoint { CGPoint(x: o.x + rr * cos(ang), y: o.y + rr * sin(ang)) }
        p.move(to: punto(base, r1, a + b))
        p.addLine(to: punto(tip, r2, a + b))
        p.addLine(to: punto(tip, r2, a - b))
        p.addLine(to: punto(base, r1, a - b))
        p.closeSubpath()
        return p
    }
}

// MARK: - Fichero

/// Lo próximo en tres tarjetas apiladas. Un toque las despliega; desplegadas, tocar una la abre. A los pocos segundos
/// vuelven solas. "Ver todo" se abre llevando el halo a la pastilla de abajo.
/// La importante lleva borde dorado; en firme, si hay otra antes, asoma una solapa dorada detrás, a la izquierda.
struct Fichero: View {
    let tareas: [Tarea]
    let ahora: Date
    @Binding var abierto: Bool
    var importante: Tarea? = nil
    var firme = false
    var onAbrir: (Tarea) -> Void = { _ in }
    var onTermine: (Tarea) -> Void = { _ in }

    @Environment(\.paleta) private var paleta

    var body: some View {
        let lista = Array(tareas.prefix(3))
        let solapa = firme && !abierto ? importante.flatMap { imp in lista.first?.uid == imp.uid ? nil : imp } : nil
        VStack(spacing: abierto ? 8 : 0) {
            ForEach(Array(lista.enumerated()), id: \.element.uid) { i, t in
                FichaInicio(tarea: t, ahora: ahora, primera: i == 0, onTermine: i == 0 ? { onTermine(t) } : nil)
                    .frame(height: i == 0 || abierto ? nil : 8, alignment: .bottom)
                    .clipped()
                    .scaleEffect(x: abierto ? 1 : 1 - 0.03 * CGFloat(i), y: 1, anchor: .top)
                    .opacity(i == 0 || abierto ? 1 : 0.9)
                    .zIndex(Double(3 - i))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Lo que está pasando ahora (una tarea en curso o una cita) se abre directo.
                        if abierto || (i == 0 && FichaInicio.directa(t, ahora: ahora)) {
                            onAbrir(t)
                        } else {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { abierto = true }
                        }
                    }
            }
        }
        .background(alignment: .topLeading) {
            if let imp = solapa {
                SolapaImportante(tarea: imp)
                    .offset(x: 14, y: -30)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
        .task(id: abierto) {
            guard abierto else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation(.spring(duration: 0.4)) { abierto = false } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(abierto ? "Tocá una tarjeta para abrirla" : "Tocá para ver las próximas")
    }
}

/// Los colores dorados de la importante.
enum Dorado {
    static let borde = RGB(0xD9B26E)
    static let fondo = RGB(0xF1E3C2)
    static let texto = RGB(0x7A5E22)
}

/// La solapa dorada que asoma detrás del fichero: "★ 11:00 · Armar 2 láminas".
struct SolapaImportante: View {
    let tarea: Tarea
    var body: some View {
        HStack(spacing: 5) {
            Text("★").font(.caption)
            Text(Formato.hora(tarea.inicio)).font(.caption.weight(.semibold))
            Text("· \(tarea.tituloVisible)").font(.caption).lineLimit(1)
        }
        .foregroundStyle(Dorado.texto.color)
        .padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 14)
        .background(Dorado.fondo.color, in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12).stroke(Dorado.borde.color))
        .frame(maxWidth: 260, alignment: .leading)
        .accessibilityLabel("La importante: \(tarea.titulo) a las \(Formato.hora(tarea.inicio))")
    }
}

/// Una tarjeta del fichero: categoría en su color, título, cuenta regresiva y, en la primera, lugar y notas.
struct FichaInicio: View {
    let tarea: Tarea
    let ahora: Date
    var primera = false
    /// Terminar antes: "Terminé" en una tarea en curso, "Ya terminó" en una cita que empezó.
    var onTermine: (() -> Void)? = nil
    @Environment(\.paleta) private var paleta

    /// Lo que está pasando ahora se abre directo al tocarlo: una tarea en curso o una cita que ya empezó.
    static func directa(_ t: Tarea, ahora: Date) -> Bool { t.estado == .enCurso || (t.esCita && t.inicio <= ahora) }

    var body: some View {
        let t = tarea
        // Para una cita con viaje, la cuenta regresiva es hasta la hora de salir.
        let objetivo = t.salida ?? t.inicio
        let enCurso = t.estado == .enCurso
        let empezo = t.esCita && t.inicio <= ahora
        let finCita = t.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60)
        let detalle = enCurso
            ? "Empezaste \(Formato.hora(t.inicioReal ?? t.inicio)) · tocá para ver los pasos"
            : (t.esCita && t.salida != nil
                ? "\(Formato.diaYHora(t.inicio, ahora: ahora)) · salí \(Formato.hora(objetivo)) (\(t.minutosViaje) min de viaje)"
                : "\(Formato.diaYHora(t.inicio, ahora: ahora)) · \(Formato.minutos(t.duracionMinutos))")
        let etiqueta = enCurso ? "en curso" : (empezo ? "ahora" : (primera ? "lo próximo" : nil))
        TarjetaBanda(categoria: t.categoria, paleta: paleta) {
            VStack(alignment: .leading, spacing: 3) {
                if t.importante {
                    Text("★ LA IMPORTANTE" + (etiqueta.map { " · \($0.uppercased())" } ?? ""))
                        .font(.caption2.weight(.bold)).tracking(0.6)
                        .foregroundStyle(Dorado.texto.color)
                } else {
                    EtiquetaCategoria(categoria: t.categoria, paleta: paleta,
                                      extra: [t.proyecto?.titulo, etiqueta].compactMap { $0 }.joined(separator: " · ").nilSiVacio)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(t.tituloVisible).font(.serif(19, relativoA: .headline)).lineLimit(2)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        if enCurso {
                            Text(Formato.cuenta(Int((t.finPrevisto ?? ahora).timeIntervalSince(ahora)))).font(.serif(18, relativoA: .headline)).monospacedDigit()
                            Text("quedan").font(.caption2).foregroundStyle(paleta.secundario.color)
                        } else if empezo {
                            Text(Formato.cuenta(Int(finCita.timeIntervalSince(ahora)))).font(.serif(18, relativoA: .headline)).monospacedDigit()
                            Text("para que termine").font(.caption2).foregroundStyle(paleta.secundario.color)
                        } else {
                            Text(Formato.cuenta(Int(objetivo.timeIntervalSince(ahora)))).font(.serif(18, relativoA: .headline)).monospacedDigit()
                            Text(t.salida != nil ? "para salir" : "para empezar").font(.caption2).foregroundStyle(paleta.secundario.color)
                        }
                    }
                    .foregroundStyle(paleta.primario.color)
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(detalle).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
                    if let terminar = onTermine, enCurso || empezo {
                        Spacer(minLength: 4)
                        Button(enCurso ? "Terminé" : "Ya terminó", action: terminar)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(paleta.primario.color)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(paleta.superficie.color, in: Capsule())
                            .overlay(Capsule().stroke(paleta.primario.color.opacity(0.45)))
                            .buttonStyle(.plain)
                    }
                }
                if primera {
                    if let p = t.proyecto { BarraProyecto(proyecto: p, ahora: ahora, mostrarNombre: false).padding(.top, 6) }
                    NotasTarea(tarea: t)
                }
            }
        }
        .overlay {
            if enCurso {
                RoundedRectangle(cornerRadius: 18).stroke(paleta.energia.color, lineWidth: 2)
            } else if t.importante {
                RoundedRectangle(cornerRadius: 18).stroke(Dorado.borde.color, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension String {
    var nilSiVacio: String? { isEmpty ? nil : self }
}
