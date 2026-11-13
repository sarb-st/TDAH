import SwiftUI
import SwiftData

// MARK: - Listado en tarjetas

/// Todas las tareas como tarjetas, agrupadas por día. Fuera de la pantalla principal, para no romper
/// "una sola cosa a la vista": se abre a propósito.
struct ListaView: View {
    @Environment(\.dismiss) private var cerrar
    @Query(sort: \Tarea.inicio) private var tareas: [Tarea]
    @Query(sort: \Proyecto.deadline) private var proyectos: [Proyecto]
    @Query(sort: \Captura.creada, order: .reverse) private var capturas: [Captura]
    @Environment(\.modelContext) private var ctx
    @State private var verHechas = false
    @State private var creandoProyecto = false
    @State private var pasarATarea: Captura?
    @State private var clasificando: UUID?
    @State private var mensaje: String?
    let paleta: Paleta

    private var inbox: [Captura] { capturas.filter { $0.tipo == "inbox" && !$0.archivada } }
    private var ideas: [Captura] { capturas.filter { $0.tipo == "idea" && !$0.archivada } }
    private var activos: [Proyecto] { proyectos.filter { !$0.archivado } }

    private var visibles: [Tarea] {
        let hoy = Calendar.current.startOfDay(for: .now)
        return tareas.filter { t in
            switch t.estado {
            case .programada, .enCurso, .pausada, .faltaHora: true
            case .terminada: verHechas || (t.inicioReal ?? t.inicio) >= hoy
            case .archivada: verHechas
            }
        }
    }

    private struct Grupo: Identifiable {
        let dia: Date
        let tareas: [Tarea]
        var id: Date { dia }
    }

    private var grupos: [Grupo] {
        let cal = Calendar.current
        let pendientes = visibles.filter { $0.estado == .faltaHora }
        let conDia = Dictionary(grouping: visibles.filter { $0.estado != .faltaHora }) { cal.startOfDay(for: $0.inicioReal ?? $0.inicio) }
        var r = conDia.keys.sorted().map { dia in
            Grupo(dia: dia, tareas: (conDia[dia] ?? []).sorted { ($0.inicioReal ?? $0.inicio) < ($1.inicioReal ?? $1.inicio) })
        }
        if !pendientes.isEmpty { r.insert(Grupo(dia: .distantPast, tareas: pendientes), at: 0) }
        return r
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    if !inbox.isEmpty {
                        encabezado("Inbox · \(inbox.count)")
                        ForEach(inbox, id: \.uid) { filaInbox($0) }
                    }
                    HStack {
                        encabezado("Proyectos")
                        Spacer()
                        Button { creandoProyecto = true } label: { Image(systemName: "plus") }.padding(.top, 14)
                            .accessibilityLabel("Nuevo proyecto")
                    }
                    if activos.isEmpty {
                        Text("Ninguno por ahora. Dictá uno o tocá el +.").font(.footnote).foregroundStyle(paleta.secundario.color)
                    }
                    ForEach(activos, id: \.uid) { p in
                        NavigationLink { ProyectoDetalleView(proyecto: p, paleta: paleta) } label: { TarjetaProyecto(proyecto: p, paleta: paleta) }
                            .buttonStyle(.plain)
                    }
                    if visibles.isEmpty {
                        Text("No hay tareas todavía.").foregroundStyle(paleta.secundario.color).padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(grupos) { grupo in
                        Text(titulo(grupo.dia))
                            .font(.serif(22, relativoA: .title3))
                            .foregroundStyle(paleta.primario.color)
                            .padding(.top, 14)
                        ForEach(grupo.tareas, id: \.uid) { t in
                            NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: { TarjetaTarea(tarea: t, paleta: paleta) }
                                .buttonStyle(.plain)
                        }
                    }
                    if !ideas.isEmpty {
                        encabezado("Ideas")
                        ForEach(ideas, id: \.uid) { idea in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb").foregroundStyle(paleta.primario.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(idea.tituloVisible).font(.serif(17, relativoA: .body))
                                    if !idea.tema.isEmpty { Text(idea.tema).font(.caption).foregroundStyle(paleta.secundario.color) }
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                            .contextMenu {
                                Button("Pasar a tarea") { pasarATarea = idea }
                                Button("Archivar") { idea.archivada = true; Acciones.guardar(ctx) }
                            }
                        }
                    }
                    Toggle("Mostrar hechas y archivadas", isOn: $verHechas)
                        .tint(paleta.primario.color)
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Tareas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .sheet(isPresented: $creandoProyecto) { EditarProyectoView(proyecto: nil) }
            .sheet(item: $pasarATarea) { c in
                NuevaTareaView(tarea: nil, tituloInicial: c.tituloVisible) {
                    c.archivada = true
                    Acciones.guardar(ctx)
                }
            }
            .alert(mensaje ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
                Button("Listo", role: .cancel) {}
            }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
    }

    private func encabezado(_ texto: String) -> some View {
        Text(texto).font(.serif(22, relativoA: .title3)).foregroundStyle(paleta.primario.color).padding(.top, 14)
    }

    /// Lo que no se clasificó: se puede mandar a Claude de nuevo, pasar a tarea a mano o archivar.
    private func filaInbox(_ c: Captura) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.tituloVisible).font(.serif(17, relativoA: .body))
            Text(c.creada.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Locale(identifier: "es"))))
                .font(.caption).foregroundStyle(paleta.secundario.color)
            HStack(spacing: 14) {
                Button {
                    Task { await clasificar(c) }
                } label: {
                    if clasificando == c.uid { ProgressView() } else { Label("Ordenar con Claude", systemImage: "sparkles") }
                }
                .disabled(clasificando != nil || !ClaveIA.hay)
                Button("Pasar a tarea") { pasarATarea = c }
                Spacer()
                Button { c.archivada = true; Acciones.guardar(ctx) } label: { Image(systemName: "archivebox") }
                    .accessibilityLabel("Archivar")
            }
            .font(.footnote)
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.halo.color))
    }

    private func clasificar(_ c: Captura) async {
        clasificando = c.uid
        defer { clasificando = nil }
        do {
            let items = try await ClienteClaude.clasificar(c.texto)
            let utiles = items.map { Propuesta(ia: $0) }.filter { $0.tipo != "inbox" }
            guard !utiles.isEmpty else { mensaje = "Claude tampoco pudo decidir qué es. Queda en el Inbox."; return }
            Guardado.guardar(utiles, ctx: ctx, tareas: tareas)
            c.archivada = true
            Acciones.guardar(ctx)
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func titulo(_ dia: Date) -> String {
        if dia == .distantPast { return "Falta elegir hora" }
        let cal = Calendar.current
        if cal.isDateInToday(dia) { return "Hoy" }
        if cal.isDateInTomorrow(dia) { return "Mañana" }
        if cal.isDateInYesterday(dia) { return "Ayer" }
        return Formato.primeraMayuscula(dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es"))))
    }
}

struct TarjetaTarea: View {
    let tarea: Tarea
    let paleta: Paleta

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tarea.estado == .faltaHora ? "—" : Formato.hora(tarea.inicioReal ?? tarea.inicio))
                    .font(.numero(20)).monospacedDigit()
                Text("\(tarea.duracionMinutos) min").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(tarea.titulo).font(.serif(19, relativoA: .headline))
                    .strikethrough(tarea.estado == .terminada)
                    .foregroundStyle(tarea.estado == .terminada || tarea.estado == .archivada ? paleta.secundario.color : paleta.texto.color)
                    .multilineTextAlignment(.leading)
                if let p = tarea.proyecto {
                    Label(p.titulo, systemImage: "square.stack.3d.up").font(.caption).foregroundStyle(paleta.secundario.color)
                }
                if !tarea.lugar.isEmpty {
                    Label(tarea.lugar, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(paleta.secundario.color)
                }
                if !tarea.notas.isEmpty {
                    Text(tarea.notas).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if tarea.esCita { Chip(texto: "Cita", paleta: paleta) }
                    Chip(texto: tarea.estado.nombre, paleta: paleta, destacado: tarea.estado == .enCurso || tarea.estado == .faltaHora)
                    if !tarea.pasos.isEmpty {
                        Text("\(tarea.pasos.filter(\.hecho).count)/\(tarea.pasos.count) pasos")
                            .font(.caption).foregroundStyle(paleta.secundario.color)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color).padding(.top, 6)
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.linea.color))
        .contentShape(Rectangle())
    }
}

struct Chip: View {
    let texto: String
    let paleta: Paleta
    var destacado = false

    var body: some View {
        Text(texto)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(destacado ? paleta.fondo.color : paleta.primario.color)
            .background(destacado ? paleta.primario.color : paleta.halo.color.opacity(0.35), in: Capsule())
    }
}

// MARK: - Calendario por día

/// Un día con sus franjas horarias. Arriba, la semana para saltar de día en día.
struct CalendarioView: View {
    @Environment(\.dismiss) private var cerrar
    @Query(sort: \Tarea.inicio) private var tareas: [Tarea]
    @Query(sort: \SlotRegistro.inicioPlaneado) private var registros: [SlotRegistro]
    @State private var dia = Calendar.current.startOfDay(for: .now)
    let paleta: Paleta

    private let altoHora: CGFloat = 64
    private var cal: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                semana
                Divider().overlay(paleta.linea.color)
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            grilla
                            bloques
                            if cal.isDateInToday(dia) { lineaAhora }
                        }
                        .frame(height: altoHora * 24)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .onAppear { proxy.scrollTo(max(0, cal.component(.hour, from: .now) - 1), anchor: .top) }
                    .onChange(of: dia) { proxy.scrollTo(8, anchor: .top) }
                }
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle(Formato.primeraMayuscula(dia.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es")))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hoy") { withAnimation { dia = cal.startOfDay(for: .now) } }.disabled(cal.isDateInToday(dia))
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
    }

    private var semana: some View {
        let inicio = cal.dateInterval(of: .weekOfYear, for: dia)?.start ?? dia
        let dias = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: inicio) }
        return HStack(spacing: 4) {
            Button { mover(-7) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 44) }
                .accessibilityLabel("Semana anterior")
            ForEach(dias, id: \.self) { d in
                let elegido = cal.isDate(d, inSameDayAs: dia)
                Button { withAnimation { dia = d } } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "es"))).uppercased())
                            .font(.caption2).foregroundStyle(paleta.secundario.color)
                        Text("\(cal.component(.day, from: d))")
                            .font(.numero(18))
                            .frame(width: 34, height: 34)
                            .background(elegido ? paleta.primario.color : .clear, in: Circle())
                            .foregroundStyle(elegido ? paleta.fondo.color : paleta.texto.color)
                        Circle().fill(tieneTareas(d) ? paleta.halo.color : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            Button { mover(7) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 44) }
                .accessibilityLabel("Semana siguiente")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var grilla: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", h)).font(.caption2.monospacedDigit()).foregroundStyle(paleta.secundario.color)
                        .frame(width: 40, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle().fill(paleta.linea.color).frame(height: 1)
                }
                .frame(height: altoHora, alignment: .top)
                .id(h)
            }
        }
    }

    private func y(_ fecha: Date) -> CGFloat {
        let c = cal.dateComponents([.hour, .minute], from: fecha)
        return CGFloat(c.hour ?? 0) * altoHora + CGFloat(c.minute ?? 0) / 60 * altoHora
    }

    private var delDia: [Tarea] {
        tareas.filter { $0.estado != .faltaHora && $0.estado != .archivada && cal.isDate($0.inicioReal ?? $0.inicio, inSameDayAs: dia) }
    }

    /// El rastro de los slots cerrados con "Ahora no": dato neutro, sin culpa.
    private var cerrados: [SlotRegistro] {
        registros.filter { ($0.resultado == "ahora no" || $0.resultado == "sin respuesta") && cal.isDate($0.inicioPlaneado, inSameDayAs: dia) }
    }

    private var bloques: some View {
        ZStack(alignment: .topLeading) {
            ForEach(cerrados, id: \.persistentModelID) { r in
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(paleta.secundario.color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .overlay(alignment: .topLeading) {
                        Text("\(r.titulo) · slot cerrado").font(.caption).foregroundStyle(paleta.secundario.color).padding(6).lineLimit(1)
                    }
                    .frame(height: 30)
                    .padding(.leading, 56)
                    .offset(y: y(r.inicioPlaneado))
            }
            ForEach(delDia, id: \.uid) { t in
                let inicio = t.inicioReal ?? t.inicio
                let alto = max(30, CGFloat(t.duracionMinutos + t.minutosExtra) / 60 * altoHora)
                NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.titulo).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .strikethrough(t.estado == .terminada)
                        if alto > 44 {
                            Text("\(Formato.hora(inicio)) · \(t.duracionMinutos) min").font(.caption).foregroundStyle(paleta.secundario.color)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: alto)
                    .background((t.estado == .enCurso ? paleta.energia : paleta.halo).color.opacity(t.estado == .terminada ? 0.25 : 0.55),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(paleta.primario.color).frame(width: 3).padding(.vertical, 6)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 56)
                .offset(y: y(inicio))
            }
        }
    }

    private var lineaAhora: some View {
        HStack(spacing: 0) {
            Circle().fill(paleta.primario.color).frame(width: 8, height: 8)
            Rectangle().fill(paleta.primario.color).frame(height: 1.5)
        }
        .padding(.leading, 44)
        .offset(y: y(.now) - 4)
        .allowsHitTesting(false)
    }

    private func tieneTareas(_ d: Date) -> Bool {
        tareas.contains { $0.ocupaAgenda && cal.isDate($0.inicioReal ?? $0.inicio, inSameDayAs: d) }
    }

    private func mover(_ dias: Int) {
        if let d = cal.date(byAdding: .day, value: dias, to: dia) { withAnimation { dia = d } }
    }
}

// MARK: - Detalle de una tarea

struct DetalleTareaView: View {
    let tarea: Tarea
    let paleta: Paleta

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var volver
    @Environment(\.openURL) private var abrir
    @State private var editando = false
    @State private var confirmarBorrado = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Chip(texto: tarea.estado.nombre, paleta: paleta, destacado: tarea.estado == .enCurso || tarea.estado == .faltaHora)
                    Text(tarea.titulo).font(.tituloTarea)
                    Text(tarea.estado == .faltaHora ? "Sin hora todavía" :
                            "\(Formato.diaYHora(tarea.inicioReal ?? tarea.inicio, ahora: .now)) · \(tarea.duracionMinutos) min")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color)
                }

                if !tarea.lugar.isEmpty || !tarea.direccion.isEmpty {
                    bloque("Lugar") {
                        VStack(alignment: .leading, spacing: 4) {
                            if !tarea.lugar.isEmpty { Text(tarea.lugar) }
                            if !tarea.direccion.isEmpty { Text(tarea.direccion).foregroundStyle(paleta.secundario.color) }
                            if let url = tarea.mapa {
                                Button { abrir(url) } label: { Label("Abrir en Mapas", systemImage: "map") }.padding(.top, 4)
                            }
                        }
                    }
                }
                if !tarea.notas.isEmpty {
                    bloque("Notas") { Text(tarea.notas) }
                }
                if !tarea.pasos.isEmpty {
                    bloque("Pasos") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(tarea.pasosOrdenados, id: \.uid) { p in
                                Button {
                                    p.hecho.toggle()
                                    Acciones.guardar(ctx)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: p.hecho ? "circle.fill" : "circle").foregroundStyle(paleta.primario.color)
                                        Text(p.texto).strikethrough(p.hecho).foregroundStyle(p.hecho ? paleta.secundario.color : paleta.texto.color)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    if tarea.estado != .enCurso {
                        Button("Editar") { editando = true }.buttonStyle(BotonPrimario(paleta: paleta))
                    }
                    if tarea.estado == .archivada {
                        Button("Recuperar") { Acciones.restaurar(tarea, ctx: ctx); volver() }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else if tarea.estado != .terminada && tarea.estado != .enCurso {
                        Button("Ya no la voy a hacer") { Acciones.archivar(tarea, ctx: ctx); volver() }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    Button("Borrar", role: .destructive) { confirmarBorrado = true }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editando) { NuevaTareaView(tarea: tarea) }
        .confirmationDialog("¿Borrar “\(tarea.titulo)”?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                let t = tarea
                volver()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Acciones.borrar(t, ctx: ctx) }
            }
        } message: {
            Text("No se puede deshacer. Si solo no la vas a hacer, mejor archivala.")
        }
    }

    private func bloque<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(paleta.secundario.color)
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
    }
}
