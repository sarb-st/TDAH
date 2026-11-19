import SwiftUI
import SwiftData

// MARK: - Lista

/// Una lista para ordenarse punteando cosas: tachar, agregar adentro de un renglón (un nivel), mover con las rayitas.
/// Tachar todo lo de adentro tacha el de arriba. Cuando se completa: archivarla, usarla de nuevo o dejarla así.
struct ListaFichaView: View {
    @Bindable var captura: Captura
    @Environment(\.modelContext) private var ctx
    @Environment(\.paleta) private var paleta
    @Environment(\.dismiss) private var volver
    @State private var adentroDe: UUID?
    @State private var convirtiendo = false
    @State private var saltito: UUID?

    private let color = ColoresCajon.lista

    var body: some View {
        let principales = captura.principales
        let hechos = principales.filter(\.hecho).count
        let completa = !principales.isEmpty && hechos == principales.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CabeceraFicha(color: color) {
                    ChipTema(texto: "☰ Lista", color: color)
                    TextField("Título", text: $captura.titulo, axis: .vertical).font(.serif(28, relativoA: .largeTitle))
                    HStack(spacing: 14) {
                        anillo(hechos: hechos, total: principales.count, completa: completa)
                        Text(.init(frase(hechos: hechos, total: principales.count))).font(.footnote).foregroundStyle(paleta.secundario.color)
                    }
                    if completa {
                        HStack(spacing: 8) {
                            boton("Archivarla", primario: true) { captura.archivada = true; Acciones.guardar(ctx); volver() }
                            boton("Usarla de nuevo") { for r in captura.renglones { r.hecho = false }; Acciones.guardar(ctx) }
                            boton("Dejarla así") { volver() }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ListaReordenable(items: principales, espacio: 6, movible: { _ in true },
                                     alMover: { d, h in Orden.mover(principales, desde: d, hasta: h, ctx: ctx) }) { r, manija in
                        grupo(r, manija: manija)
                    }
                    CampoSumar(placeholder: "Sumar un renglón", color: color, siguiente: true, conMicrofono: true) { t, origen in
                        let r = Renglon(texto: t, orden: (principales.map(\.orden).max() ?? -1) + 1, origen: origen)
                        ctx.insert(r)
                        r.captura = captura
                        Acciones.guardar(ctx)
                    }
                    .padding(.top, 6)
                    Button("Convertir…") { convirtiendo = true }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(color.mezcla(RGB(0x2C2A25), 0.3).color, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: completa)
        .sheet(isPresented: $convirtiendo) { ConvertirHoja(captura: captura).environment(\.paleta, paleta).presentationDetents([.medium, .large]) }
        .onChange(of: captura.titulo) { _, _ in Acciones.guardar(ctx) }
    }

    private func frase(hechos: Int, total: Int) -> String {
        guard total > 0 else { return "**De a un renglón.**" }
        if hechos == total { return "**¡Lista completa!** ¿Qué hacemos con ella?" }
        if hechos * 2 >= total { return "**Más de la mitad.** Quedan \(total - hechos)." }
        return hechos > 0 ? "**Arrancaste.** Van \(hechos), quedan \(total - hechos)." : "**De a un renglón.**"
    }

    private func anillo(hechos: Int, total: Int, completa: Bool) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.6), lineWidth: 6)
            Circle().trim(from: 0, to: total == 0 ? 0 : CGFloat(hechos) / CGFloat(total))
                .stroke(ColoresCajon.listaTinta.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5, bounce: 0.3), value: hechos)
            if completa { Image(systemName: "checkmark").font(.headline) } else { Text("\(hechos)/\(total)").font(.serif(16, relativoA: .body)) }
        }
        .frame(width: 60, height: 60)
        .scaleEffect(completa ? 1.06 : 1)
    }

    private func boton(_ t: String, primario: Bool = false, _ accion: @escaping () -> Void) -> some View {
        Button(t, action: accion)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(primario ? .white : paleta.texto.color)
            .background(primario ? ColoresCajon.listaTinta.color : paleta.superficie.color, in: Capsule())
            .buttonStyle(.plain)
    }

    private func grupo(_ r: Renglon, manija: Manija) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fila(r, manija: manija, chico: false)
            let hijos = r.hijosOrdenados
            if !hijos.isEmpty || adentroDe == r.uid {
                VStack(alignment: .leading, spacing: 4) {
                    ListaReordenable(items: hijos, espacio: 4, movible: { _ in true },
                                     alMover: { d, h in Orden.mover(hijos, desde: d, hasta: h, ctx: ctx) }) { h, m in
                        fila(h, manija: m, chico: true)
                    }
                    if adentroDe == r.uid {
                        CampoSumar(placeholder: "Adentro de “\(r.texto)”", color: color, siguiente: true) { t, origen in
                            let h = Renglon(texto: t, orden: (hijos.map(\.orden).max() ?? -1) + 1, origen: origen)
                            ctx.insert(h)
                            h.padre = r
                            r.hecho = false
                            Acciones.guardar(ctx)
                        }
                    }
                }
                .padding(.leading, 26)
                .overlay(alignment: .leading) { Rectangle().fill(color.color.opacity(0.5)).frame(width: 2).padding(.leading, 14) }
            }
        }
    }

    private func fila(_ r: Renglon, manija: Manija, chico: Bool) -> some View {
        HStack(spacing: 8) {
            manija.frame(width: 26)
            Button { tachar(r) } label: {
                ZStack {
                    Circle().stroke(color.mezcla(RGB(0x2C2A25), 0.2).color, lineWidth: 1.8)
                    if r.hecho { Circle().fill(color.mezcla(RGB(0x2C2A25), 0.15).color); Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.white) }
                }
                .frame(width: chico ? 20 : 24, height: chico ? 20 : 24)
                .scaleEffect(saltito == r.uid ? 1.3 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(r.hecho ? "Destachar" : "Tachar")
            TextField("Renglón", text: Binding(get: { r.texto }, set: { r.texto = $0 }), axis: .vertical)
                .font(chico ? .subheadline : .body)
                .strikethrough(r.hecho)
                .foregroundStyle(r.hecho ? paleta.secundario.color : paleta.texto.color)
                .onSubmit { Acciones.guardar(ctx) }
            if !chico {
                Button { withAnimation { adentroDe = adentroDe == r.uid ? nil : r.uid } } label: {
                    Image(systemName: "plus").font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(color.mezcla(RGB(0x2C2A25), 0.45).color)
                        .background(color.mezcla(paleta.fondo, 0.7).color, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Agregar adentro")
            }
            Button { borrar(r) } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)) }
                .foregroundStyle(paleta.secundario.color)
                .buttonStyle(.plain)
                .accessibilityLabel("Quitar")
        }
        .padding(.vertical, chico ? 6 : 9).padding(.trailing, 10)
        .background((r.hecho ? paleta.superficie.color.opacity(0.6) : paleta.superficie.color), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tachar(_ r: Renglon) {
        Haptica.tachar()
        r.hecho.toggle()
        if r.padre == nil {
            // El de arriba arrastra a lo de adentro.
            for h in r.hijos { h.hecho = r.hecho }
        } else if let p = r.padre {
            // Si se tacha todo lo de adentro, se tacha solo el de arriba (con un saltito); si se destacha uno, se destacha.
            let todos = p.hijos.allSatisfy(\.hecho)
            if todos && !p.hecho { p.hecho = true; salto(p.uid) } else if !todos { p.hecho = false }
        }
        salto(r.uid)
        Acciones.guardar(ctx)
    }

    private func salto(_ uid: UUID) {
        withAnimation(.spring(duration: 0.25, bounce: 0.6)) { saltito = uid }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { if saltito == uid { saltito = nil } } }
    }

    private func borrar(_ r: Renglon) {
        let padre = r.padre
        ctx.delete(r)
        if let p = padre, !p.hijos.isEmpty { p.hecho = p.hijos.allSatisfy(\.hecho) }
        Acciones.guardar(ctx)
    }
}

// MARK: - Idea

/// Una idea: tu audio, lo que dijiste como cita y "Lo que la mueve" (una sola lista que se abre y se reordena).
/// Los pasos que propone la app quedan en un recuadro; los que sumás entran a la lista.
struct IdeaFichaView: View {
    @Bindable var captura: Captura
    @Environment(\.modelContext) private var ctx
    @Environment(\.paleta) private var paleta
    @State private var abriendo: UUID?
    @State private var sugeridos: [String] = []
    @State private var buscandoPasos = false
    @State private var convirtiendo = false
    @State private var aviso: String?

    private let color = Categoria.idea.rgb
    private static let temas = ["diseño", "casa", "rugby", "viajes", "trabajo", "deporte", "familia", "otros"]

    var body: some View {
        let renglones = captura.principales
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CabeceraFicha(color: color) {
                    Menu {
                        ForEach(Self.temas, id: \.self) { t in Button(t.capitalized) { captura.tema = t; Acciones.guardar(ctx) } }
                    } label: { ChipTema(texto: "✎ " + (captura.tema.isEmpty ? "Sin tema" : captura.tema), color: color) }
                    TextField("Título", text: $captura.titulo, axis: .vertical).font(.serif(28, relativoA: .largeTitle))
                    Text("\(captura.audio.isEmpty ? "Escrita" : "Dictada") \(captura.creada.formatted(.relative(presentation: .named).locale(Locale(identifier: "es")))) · tocá cualquier texto para cambiarlo")
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                    if !captura.audio.isEmpty { PildoraAudio(nombre: captura.audio, color: color) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Lo que se te ocurrió", text: $captura.texto, axis: .vertical)
                        .font(.serif(16, relativoA: .body))
                        .padding(.vertical, 14).padding(.trailing, 16).padding(.leading, 34)
                        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topLeading) { Text("“").font(.serif(38, relativoA: .largeTitle)).foregroundStyle(color.color).padding(.leading, 10) }
                        .padding(.top, 14)
                    HStack {
                        Text("Lo que la mueve").font(.serif(19, relativoA: .title3))
                        Spacer()
                        HStack(spacing: 10) {
                            Label("dijiste", systemImage: "waveform")
                            Label("sugerido", systemImage: "sparkle")
                        }
                        .labelStyle(EtiquetaChica())
                        .font(.caption2).foregroundStyle(paleta.secundario.color)
                    }
                    .padding(.top, 14)
                    ListaReordenable(items: renglones, espacio: 6, movible: { _ in true },
                                     alMover: { d, h in Orden.mover(renglones, desde: d, hasta: h, ctx: ctx) }) { r, manija in
                        grupo(r, manija: manija)
                    }
                    CampoSumar(placeholder: "Sumar un renglón", color: color) { t, origen in
                        agregar(t, origen: origen)
                    }
                    .padding(.top, 4)
                    if !sugeridos.isEmpty { recuadroSugeridos }
                    if sugeridos.isEmpty {
                        Button { Task { await pedirPasos(renglones) } } label: {
                            HStack(spacing: 10) {
                                Group { if buscandoPasos { ProgressView() } else { Image(systemName: "sparkle") } }
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(Paleta.ia.color)
                                    .background(paleta.superficie.color, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(renglones.contains { $0.origen == "ia" } ? "¿Te propongo algunos más?" : "¿Vamos con algunos pasos?").font(.subheadline.weight(.semibold))
                                    Text("Te propongo pasos; los que sumes entran en la lista de arriba.").font(.caption).foregroundStyle(paleta.secundario.color)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(Paleta.iaFondo.color, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(Paleta.iaTexto.color)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ClaveIA.hay || buscandoPasos)
                        .padding(.top, 10)
                    }
                    if let a = aviso { Text(a).font(.caption).foregroundStyle(paleta.secundario.color) }
                    Button("Convertir…") { convirtiendo = true }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(color.mezcla(RGB(0x2C2A25), 0.3).color, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { captura.archivada = true; Acciones.guardar(ctx) } label: { Image(systemName: "archivebox") }.accessibilityLabel("Archivar")
            }
        }
        .sheet(isPresented: $convirtiendo) { ConvertirHoja(captura: captura).environment(\.paleta, paleta).presentationDetents([.medium, .large]) }
        .onDisappear { Acciones.guardar(ctx) }
    }

    private func agregar(_ t: String, origen: String) {
        let r = Renglon(texto: t, orden: (captura.principales.map(\.orden).max() ?? -1) + 1, origen: origen)
        ctx.insert(r)
        r.captura = captura
        Acciones.guardar(ctx)
    }

    private func grupo(_ r: Renglon, manija: Manija) -> some View {
        let hijos = r.hijosOrdenados
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                manija.frame(width: 26)
                MarcaOrigen(origen: r.origen, color: color)
                TextField("Renglón", text: Binding(get: { r.texto }, set: { r.texto = $0 }), axis: .vertical)
                if abriendo == r.uid { ProgressView().controlSize(.small) } else {
                    Button { Task { await abrir(r) } } label: {
                        Label("abrir", systemImage: "sparkle").labelStyle(EtiquetaChica())
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .foregroundStyle(Paleta.ia.color)
                            .background(Paleta.iaFondo.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ClaveIA.hay)
                }
                Button { ctx.delete(r); Acciones.guardar(ctx) } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)) }
                    .foregroundStyle(paleta.secundario.color).buttonStyle(.plain)
            }
            .padding(.vertical, 9).padding(.trailing, 10)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            if !hijos.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ListaReordenable(items: hijos.filter { !$0.sugerido }, espacio: 4, movible: { _ in true },
                                     alMover: { d, h in Orden.mover(hijos.filter { !$0.sugerido }, desde: d, hasta: h, ctx: ctx) }) { h, m in
                        HStack(spacing: 8) {
                            m.frame(width: 26)
                            MarcaOrigen(origen: h.origen, color: color)
                            TextField("", text: Binding(get: { h.texto }, set: { h.texto = $0 }), axis: .vertical).font(.subheadline)
                            Button { ctx.delete(h); Acciones.guardar(ctx) } label: { Image(systemName: "xmark").font(.caption2) }
                                .foregroundStyle(paleta.secundario.color).buttonStyle(.plain)
                        }
                        .padding(.vertical, 7).padding(.trailing, 10)
                        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(hijos.filter(\.sugerido), id: \.uid) { h in
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle").font(.caption).foregroundStyle(Paleta.ia.color).frame(width: 16).padding(.leading, 10)
                            Text(h.texto).font(.subheadline).foregroundStyle(Paleta.iaTexto.color)
                            Spacer(minLength: 4)
                            Button("Sumar") { h.sugerido = false; Acciones.guardar(ctx) }
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Paleta.ia.color, in: Capsule()).buttonStyle(.plain)
                            Button { ctx.delete(h); Acciones.guardar(ctx) } label: { Image(systemName: "xmark").font(.caption2) }
                                .foregroundStyle(paleta.secundario.color).buttonStyle(.plain)
                        }
                        .padding(.vertical, 7).padding(.trailing, 10)
                        .background(Paleta.iaFondo.color, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.leading, 24)
                .overlay(alignment: .leading) { Rectangle().fill(color.color.opacity(0.4)).frame(width: 2).padding(.leading, 12) }
            }
        }
    }

    private var recuadroSugeridos: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Te propongo estos. Los que sumes entran en la lista.", systemImage: "sparkle")
                .font(.caption.weight(.semibold)).foregroundStyle(Paleta.iaTexto.color)
            ForEach(sugeridos, id: \.self) { t in
                HStack(spacing: 8) {
                    Text(t).font(.subheadline).foregroundStyle(Paleta.iaTexto.color)
                    Spacer(minLength: 4)
                    Button("Sumar") { agregar(t, origen: "ia"); sugeridos.removeAll { $0 == t } }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Paleta.ia.color, in: Capsule()).buttonStyle(.plain)
                    Button { sugeridos.removeAll { $0 == t } } label: { Image(systemName: "xmark").font(.caption2) }
                        .foregroundStyle(paleta.secundario.color).buttonStyle(.plain)
                }
                .padding(10)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(10)
        .background(Paleta.iaFondo.color, in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 10)
    }

    private func abrir(_ r: Renglon) async {
        abriendo = r.uid
        defer { abriendo = nil }
        do {
            let partes = try await ClienteClaude.abrirRenglon(idea: captura.tituloVisible, renglon: r.texto)
            let base = (r.hijos.map(\.orden).max() ?? -1) + 1
            for (i, t) in partes.enumerated() {
                let h = Renglon(texto: t, orden: base + i, origen: "ia", sugerido: true)
                ctx.insert(h)
                h.padre = r
            }
            Acciones.guardar(ctx)
        } catch { aviso = error.localizedDescription }
    }

    private func pedirPasos(_ renglones: [Renglon]) async {
        buscandoPasos = true
        defer { buscandoPasos = false }
        do {
            sugeridos = try await ClienteClaude.pasosIdea(idea: captura.tituloVisible + ". " + captura.texto, renglones: renglones.map(\.texto))
        } catch { aviso = error.localizedDescription }
    }
}

// MARK: - Inbox

/// Lo que no se entendió: la app pregunta qué es y propone opciones; si no es ninguna, le contás más o lo convertís.
struct InboxFichaView: View {
    @Bindable var captura: Captura
    @Environment(\.modelContext) private var ctx
    @Environment(\.paleta) private var paleta
    @Environment(\.dismiss) private var volver
    @Query private var tareas: [Tarea]
    @State private var opciones: [ClienteClaude.Adivinanza] = []
    @State private var buscando = false
    @State private var propuestas: [Propuesta] = []
    @State private var revisando = false
    @State private var convirtiendo = false
    @State private var aviso: String?

    private let color = Categoria.inbox.rgb

    private var diasParaArchivar: Int {
        max(0, 14 - (Calendar.current.dateComponents([.day], from: captura.creada, to: .now).day ?? 0))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CabeceraFicha(color: color) {
                    ChipTema(texto: "Inbox · dame más data", color: color)
                    TextField("Lo que dijiste", text: $captura.texto, axis: .vertical).font(.serif(28, relativoA: .largeTitle))
                    Text("\(captura.audio.isEmpty ? "Anotado" : "Dictado") \(captura.creada.formatted(.relative(presentation: .named).locale(Locale(identifier: "es")))) · si no lo tocás, se archiva solo en \(diasParaArchivar) días")
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                    if !captura.audio.isEmpty { PildoraAudio(nombre: captura.audio, color: color) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkle").foregroundStyle(Paleta.ia.color).padding(.top, 2)
                        Text("No me quedó claro. ¿Qué es \(captura.texto.lowercased().hasPrefix("lo de") ? captura.texto.lowercased() : "esto")?")
                            .font(.serif(16.5, relativoA: .body))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.top, 14)
                    if buscando { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(opciones, id: \.titulo) { o in
                        Button { elegir(o) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(nombre(o.tipo).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(colorTipo(o.tipo).mezcla(RGB(0x2C2A25), 0.35).color)
                                    Text(o.titulo).font(.subheadline.weight(.medium)).foregroundStyle(paleta.texto.color)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color)
                            }
                            .padding(.vertical, 11).padding(.leading, 14).padding(.trailing, 12)
                            .background(paleta.superficie.color)
                            .overlay(alignment: .leading) { Rectangle().fill(colorTipo(o.tipo).color).frame(width: 5) }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
                        }
                        .buttonStyle(.plain)
                    }
                    CampoSumar(placeholder: "O contame más con tus palabras", color: color) { t, _ in
                        Task { await ordenar(captura.texto + ". " + t) }
                    }
                    .padding(.top, 4)
                    if let a = aviso { Text(a).font(.caption).foregroundStyle(paleta.secundario.color) }
                    HStack(spacing: 8) {
                        Button("Convertir…") { convirtiendo = true }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(color.mezcla(RGB(0x2C2A25), 0.3).color, in: RoundedRectangle(cornerRadius: 14))
                        Button("Archivar") { captura.archivada = true; Acciones.guardar(ctx); volver() }
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $convirtiendo) { ConvertirHoja(captura: captura).environment(\.paleta, paleta).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $revisando, onDismiss: { if propuestas.isEmpty { captura.archivada = true; Acciones.guardar(ctx) } }) {
            RevisionView(propuestas: $propuestas, paleta: paleta, dicho: captura.texto) { revisando = false }
        }
        .task {
            guard opciones.isEmpty, ClaveIA.hay else { return }
            buscando = true
            opciones = (try? await ClienteClaude.adivinarInbox(captura.texto)) ?? []
            buscando = false
        }
    }

    private func nombre(_ tipo: String) -> String {
        ["tarea": "Tarea", "cita": "Cita", "idea": "Idea", "lista": "Lista"][tipo] ?? tipo.capitalized
    }

    private func colorTipo(_ tipo: String) -> RGB {
        switch tipo {
        case "cita": Categoria.cita.rgb
        case "idea": Categoria.idea.rgb
        case "lista": ColoresCajon.lista
        default: Categoria.tarea.rgb
        }
    }

    private func elegir(_ o: ClienteClaude.Adivinanza) {
        switch o.tipo {
        case "idea", "lista":
            captura.tipo = o.tipo
            captura.titulo = o.titulo
            captura.creada = .now
            Acciones.guardar(ctx)
            aviso = o.tipo == "idea" ? "Pasó a Ideas." : "Pasó a Listas."
        default:
            Task { await ordenar("\(o.titulo) (\(o.tipo)). Dictado original: \(captura.texto)") }
        }
    }

    private func ordenar(_ texto: String) async {
        guard ClaveIA.hay else { aviso = "Para ordenarlo solo, cargá tu clave en Ajustes."; return }
        buscando = true
        defer { buscando = false }
        do {
            let items = try await ClienteClaude.clasificar(texto)
            propuestas = await Guardado.corregirLugares(Guardado.propuestas(items, tareas: tareas))
            if !propuestas.isEmpty { revisando = true } else { aviso = "Tampoco pude decidir qué es. Queda acá." }
        } catch { aviso = error.localizedDescription }
    }
}

// MARK: - Convertir

/// Convertir una lista, una idea o un inbox: que lo ordene la app, o elegir vos en qué.
struct ConvertirHoja: View {
    @Bindable var captura: Captura
    @Environment(\.modelContext) private var ctx
    @Environment(\.paleta) private var paleta
    @Environment(\.dismiss) private var cerrar
    @Query private var tareas: [Tarea]
    @State private var propuestas: [Propuesta] = []
    @State private var revisando = false
    @State private var ordenando = false
    @State private var destino: Categoria?
    @State private var aviso: String?

    private var renglones: [String] { captura.principales.filter { !$0.hecho && !$0.sugerido }.map(\.texto) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(captura.tipo == "lista" ? "¿Cómo la pasamos a acción?" : "¿En qué la convertimos? Lo que escribiste viaja entero.")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    opcion(paleta.primario, "Que lo ordene la app", "Lee el texto y los renglones y propone qué es", ia: true) {
                        Task { await ordenar(todo: true) }
                    }
                    opcion(Categoria.tarea.rgb, "Una tarea con estos pasos", "Lo que no está tachado va a los pasos") { destino = .tarea }
                    if captura.tipo != "lista" {
                        opcion(Categoria.cita.rgb, "Una cita", "Te pide día y hora") { destino = .cita }
                    }
                    opcion(Categoria.proyecto.rgb, "Un proyecto con estas etapas", "Cada renglón, una etapa, en el mismo orden") { destino = .proyecto }
                    if captura.tipo != "lista" {
                        opcion(ColoresCajon.lista, "Una lista", "Queda en Listas, con los renglones") {
                            captura.tipo = "lista"
                            Acciones.guardar(ctx)
                            cerrar()
                        }
                    }
                    opcion(paleta.primario, "Una acción por renglón", "Cada renglón se ordena por separado", ia: true) {
                        Task { await ordenar(todo: false) }
                    }
                    if ordenando { ProgressView().frame(maxWidth: .infinity) }
                    if let a = aviso { Text(a).font(.caption).foregroundStyle(paleta.secundario.color) }
                }
                .padding(20)
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Convertir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .sheet(item: $destino) { c in
                Group {
                    switch c {
                    case .proyecto: EditarProyectoView(proyecto: nil, tituloInicial: captura.tituloVisible, etapasIniciales: renglones)
                    case .cita: NuevaTareaView(tarea: nil, tituloInicial: captura.tituloVisible, esCitaInicial: true, alGuardar: archivar)
                    default: NuevaTareaView(tarea: nil, tituloInicial: captura.tituloVisible, pasosIniciales: renglones, alGuardar: archivar)
                    }
                }
                .environment(\.paleta, paleta)
            }
            .sheet(isPresented: $revisando, onDismiss: { if propuestas.isEmpty { archivar(); cerrar() } }) {
                RevisionView(propuestas: $propuestas, paleta: paleta, dicho: captura.texto) { revisando = false }
            }
        }
        .tint(paleta.primario.color)
    }

    private func archivar() {
        captura.archivada = true
        Acciones.guardar(ctx)
    }

    private func opcion(_ color: RGB, _ titulo: String, _ sub: String, ia: Bool = false, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Circle().fill(color.color).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo).font(.body.weight(.medium)).foregroundStyle(paleta.texto.color)
                    Text(sub).font(.caption).foregroundStyle(paleta.secundario.color)
                }
                Spacer()
            }
            .padding(12)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ia ? paleta.primario.color : paleta.linea.color))
        }
        .buttonStyle(.plain)
        .disabled(ia && (!ClaveIA.hay || ordenando))
    }

    private func ordenar(todo: Bool) async {
        ordenando = true
        defer { ordenando = false }
        let texto = todo
            ? ([captura.tituloVisible, captura.texto] + renglones.map { "- \($0)" }).filter { !$0.isEmpty }.joined(separator: "\n")
            : renglones.joined(separator: ". ")
        do {
            let items = try await ClienteClaude.clasificar(texto)
            propuestas = await Guardado.corregirLugares(Guardado.propuestas(items, tareas: tareas))
            if propuestas.isEmpty { aviso = "No encontré nada para convertir." } else { revisando = true }
        } catch { aviso = error.localizedDescription }
    }
}
