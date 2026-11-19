import SwiftUI
import SwiftData
import AVFoundation

/// Los colores del cajón.
enum ColoresCajon {
    static let lista = RGB(0x9DB5AC)
    static let listaTinta = RGB(0x5E8378)
}

// MARK: - Cajón

/// Lo que todavía no tiene forma: Listas ("pongámoslo en papel"), Ideas ("cosas para pelotear") e Inbox ("dame más data").
struct CajonView: View {
    let paleta: Paleta

    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Captura.creada, order: .reverse) private var capturas: [Captura]
    @State private var verArchivadas = false

    private var listas: [Captura] { capturas.filter { $0.tipo == "lista" && !$0.archivada } }
    private var ideas: [Captura] { capturas.filter { $0.tipo == "idea" && !$0.archivada } }
    private var inbox: [Captura] { capturas.filter { $0.tipo == "inbox" && !$0.archivada } }
    private var archivadas: [Captura] { capturas.filter(\.archivada) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    seccion("Listas", "pongámoslo en papel", ColoresCajon.lista)
                    if listas.isEmpty { vacio("Ninguna lista todavía. Tocá + para empezar una.") }
                    ForEach(listas, id: \.uid) { c in enlace(c) }
                    seccion("Ideas", "cosas para pelotear", Categoria.idea.rgb)
                    if ideas.isEmpty { vacio("Ninguna idea guardada. Dictá una cuando se te ocurra.") }
                    ForEach(ideas, id: \.uid) { c in enlace(c) }
                    seccion("Inbox", "dame más data", Categoria.inbox.rgb)
                    if inbox.isEmpty { vacio("Nada para aclarar.") }
                    ForEach(inbox, id: \.uid) { c in enlace(c) }
                    if !archivadas.isEmpty {
                        Toggle("Mostrar archivadas (\(archivadas.count))", isOn: $verArchivadas).padding(.top, 18)
                        if verArchivadas {
                            ForEach(archivadas, id: \.uid) { c in
                                HStack {
                                    Text(c.tituloVisible).font(.serif(16, relativoA: .body)).foregroundStyle(paleta.secundario.color).lineLimit(1)
                                    Spacer()
                                    Button("Recuperar") { c.archivada = false; c.creada = .now; Acciones.guardar(ctx) }
                                        .font(.subheadline).buttonStyle(.borderless)
                                }
                                .padding(12)
                                .background(paleta.superficie.color.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Cajón")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { uid in
                if let c = capturas.first(where: { $0.uid == uid }) { ficha(c) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button { nueva("lista") } label: { Label("Nueva lista", systemImage: "list.bullet") }
                        Button { nueva("idea") } label: { Label("Nueva idea", systemImage: "lightbulb") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Agregar")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
    }

    @ViewBuilder
    private func ficha(_ c: Captura) -> some View {
        switch c.tipo {
        case "lista": ListaFichaView(captura: c)
        case "idea": IdeaFichaView(captura: c)
        default: InboxFichaView(captura: c)
        }
    }

    private func nueva(_ tipo: String) {
        let c = Captura(tipo: tipo, texto: "", titulo: tipo == "lista" ? "Lista nueva" : "Idea nueva")
        ctx.insert(c)
        Acciones.guardar(ctx)
    }

    private func seccion(_ t: String, _ sub: String, _ color: RGB) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Circle().fill(color.color).frame(width: 10, height: 10)
                Text(t).font(.serif(20, relativoA: .title3))
            }
            Text(sub).font(.serifItalica(13, relativoA: .footnote)).foregroundStyle(paleta.secundario.color).padding(.leading, 18)
        }
        .padding(.top, 16).padding(.bottom, 4)
    }

    private func vacio(_ t: String) -> some View {
        Text(t).font(.footnote).foregroundStyle(paleta.secundario.color)
    }

    private func enlace(_ c: Captura) -> some View {
        NavigationLink(value: c.uid) { FilaCajon(captura: c) }.buttonStyle(.plain)
    }
}

/// Una ficha en la lista del cajón.
struct FilaCajon: View {
    let captura: Captura
    @Environment(\.paleta) private var paleta

    var body: some View {
        let c = captura
        let color = c.tipo == "lista" ? ColoresCajon.lista : (c.tipo == "idea" ? Categoria.idea.rgb : Categoria.inbox.rgb)
        let total = c.principales.count
        let hechos = c.principales.filter(\.hecho).count
        VStack(alignment: .leading, spacing: 3) {
            if c.tipo == "idea" && !c.tema.isEmpty {
                Text(c.tema.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(color.mezcla(RGB(0x2C2A25), 0.4).color)
            }
            Text(c.tituloVisible).font(.serif(17, relativoA: .body)).lineLimit(2).foregroundStyle(paleta.texto.color)
            Text(detalle(total: total, hechos: hechos)).font(.caption).foregroundStyle(paleta.secundario.color)
            if c.tipo == "lista" && total > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(paleta.linea.color)
                        Capsule().fill(color.color).frame(width: g.size.width * CGFloat(hechos) / CGFloat(max(1, total)))
                    }
                }
                .frame(height: 4)
                .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10).padding(.leading, 17).padding(.trailing, 12)
        .background(paleta.superficie.color)
        .overlay(alignment: .leading) { Rectangle().fill(color.color).frame(width: 6) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func detalle(total: Int, hechos: Int) -> String {
        let cuando = captura.creada.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "es")))
        switch captura.tipo {
        case "lista": return total == 0 ? "vacía" : "\(hechos) de \(total)"
        case "idea": return total == 0 ? cuando : "\(total) renglón\(total == 1 ? "" : "es")"
        default: return cuando
        }
    }
}

// MARK: - Piezas comunes

/// La cabecera de color liso de una ficha (lista, idea o inbox).
struct CabeceraFicha<Contenido: View>: View {
    let color: RGB
    @ViewBuilder var contenido: () -> Contenido
    @Environment(\.paleta) private var paleta

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { contenido() }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.mezcla(paleta.fondo, 0.7).color, in: UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26))
    }
}

/// Un chip blanco con el tipo o el tema.
struct ChipTema: View {
    let texto: String
    let color: RGB
    var body: some View {
        Text(texto.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.6)
            .foregroundStyle(color.mezcla(RGB(0x2C2A25), 0.45).color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.white.opacity(0.55), in: Capsule())
    }
}

/// Para volver a escuchar el audio de un dictado.
@Observable
final class Reproductor: NSObject, AVAudioPlayerDelegate {
    var sonando = false
    var duracion: TimeInterval = 0
    @ObservationIgnored private var jugador: AVAudioPlayer?

    func cargar(_ nombre: String) {
        guard !nombre.isEmpty, jugador == nil else { return }
        let url = Dictado.carpetaAudios.appendingPathComponent(nombre)
        jugador = try? AVAudioPlayer(contentsOf: url)
        jugador?.delegate = self
        duracion = jugador?.duration ?? 0
    }

    func alternar() {
        guard let j = jugador else { return }
        if j.isPlaying { j.pause(); sonando = false } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            j.play(); sonando = true
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { sonando = false }
}

struct PildoraAudio: View {
    let nombre: String
    let color: RGB
    @State private var r = Reproductor()

    var body: some View {
        Button { r.alternar() } label: {
            HStack(spacing: 10) {
                Image(systemName: r.sonando ? "pause.fill" : "play.fill").font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color.mezcla(RGB(0x2C2A25), 0.3).color, in: Circle())
                HStack(spacing: 2) {
                    ForEach(Array([6, 12, 8, 16, 10, 5, 13, 9, 15, 7, 11, 6].enumerated()), id: \.offset) { i, h in
                        Capsule().fill(color.mezcla(RGB(0x2C2A25), 0.25).color.opacity(0.7))
                            .frame(width: 2.5, height: CGFloat(h) * (r.sonando ? (i % 2 == 0 ? 0.6 : 1) : 1))
                    }
                }
                .animation(r.sonando ? .easeInOut(duration: 0.45).repeatForever() : .default, value: r.sonando)
                Text("Tu audio · \(Int(r.duracion) / 60):\(String(format: "%02d", Int(r.duracion) % 60))").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .background(.white.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .onAppear { r.cargar(nombre) }
    }
}

/// El campo para sumar un renglón: se confirma con Intro o con el botón Sumar (que aparece al escribir).
struct CampoSumar: View {
    let placeholder: String
    var color: RGB
    var siguiente = false
    var conMicrofono = false
    var alSumar: (String, String) -> Void

    @State private var texto = ""
    @State private var dictado = Dictado()
    @FocusState private var foco: Bool
    @Environment(\.paleta) private var paleta

    var body: some View {
        HStack(spacing: 8) {
            TextField(dictado.escuchando ? "Te escucho…" : placeholder, text: $texto)
                .focused($foco)
                .submitLabel(siguiente ? .next : .done)
                .onSubmit { sumar(origen: "") }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.mezcla(paleta.linea, 0.4).color))
            if !texto.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Sumar") { sumar(origen: "") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(color.mezcla(RGB(0x2C2A25), 0.25).color, in: RoundedRectangle(cornerRadius: 12))
                    .buttonStyle(.plain)
            }
            if conMicrofono {
                Button {
                    if dictado.escuchando {
                        let t = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
                        dictado.detener()
                        if !t.isEmpty { alSumar(t, "voz") }
                    } else { dictado.texto = ""; Task { await dictado.empezar() } }
                } label: {
                    Image(systemName: dictado.escuchando ? "stop.fill" : "mic")
                        .frame(width: 44, height: 44)
                        .foregroundStyle(dictado.escuchando ? .white : color.mezcla(RGB(0x2C2A25), 0.45).color)
                        .background(dictado.escuchando ? color.mezcla(RGB(0x2C2A25), 0.3).color : color.mezcla(paleta.fondo, 0.7).color, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictado.escuchando ? "Terminar de dictar" : "Dictar un renglón")
            }
        }
        .onDisappear { dictado.detener() }
    }

    private func sumar(origen: String) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        alSumar(t, origen)
        texto = ""
        if siguiente { foco = true }
    }
}

/// La marca de dónde salió un renglón o un paso: la onda (lo dijiste), ✦ (sugerido) o un punto (escrito).
struct MarcaOrigen: View {
    let origen: String
    var color: RGB
    var body: some View {
        Group {
            switch origen {
            case "voz": Image(systemName: "waveform").foregroundStyle(color.mezcla(RGB(0x2C2A25), 0.35).color)
            case "ia": Image(systemName: "sparkle").foregroundStyle(Paleta.ia.color)
            default: Circle().fill(color.color).frame(width: 8, height: 8)
            }
        }
        .font(.caption)
        .frame(width: 16)
        .accessibilityLabel(origen == "voz" ? "Lo dijiste" : (origen == "ia" ? "Sugerido" : ""))
    }
}

/// Reordena renglones (de una captura o dentro de uno) al soltar la manija.
@MainActor
enum Orden {
    static func mover(_ lista: [Renglon], desde: Int, hasta: Int, ctx: ModelContext) {
        var l = lista
        let r = l.remove(at: desde)
        l.insert(r, at: hasta)
        for (i, x) in l.enumerated() { x.orden = i }
        Acciones.guardar(ctx)
    }
}

