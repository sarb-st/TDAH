import SwiftUI
import SwiftData

// MARK: - Listado con pestañas

enum PestanaLista: String, CaseIterable, Identifiable {
    case hoy = "Hoy", tareas = "Tareas", citas = "Citas", proyectos = "Proyectos"
    var id: String { rawValue }
}

/// Todo lo agendado en tarjetas, con pestañas: Hoy (todo junto, por hora), Tareas, Citas y Proyectos.
/// Fuera de la pantalla principal, para no romper "una sola cosa a la vista": se abre a propósito.
struct ListaView: View {
    let paleta: Paleta
    var pestanaInicial: PestanaLista = .hoy

    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tarea.inicio) private var tareas: [Tarea]
    @Query(sort: \Proyecto.deadline) private var proyectos: [Proyecto]
    @State private var pestana: PestanaLista = .hoy
    @State private var verHechas = false
    @State private var cargando: Categoria?
    @State private var verArchivados = false
    @AppStorage("hoyHechasPlegado") private var hechasPlegado = false

    private var activos: [Proyecto] { proyectos.filter { !$0.archivado } }
    private var cal: Calendar { Calendar.current }

    private func visible(_ t: Tarea) -> Bool {
        switch t.estado {
        case .programada, .enCurso, .pausada, .faltaHora: true
        case .terminada: verHechas || cal.isDateInToday(t.inicioReal ?? t.inicio)
        case .archivada: verHechas
        }
    }

    private struct Grupo: Identifiable {
        let dia: Date
        let tareas: [Tarea]
        var id: Date { dia }
    }

    private func grupos(_ lista: [Tarea]) -> [Grupo] {
        let pendientes = lista.filter { $0.estado == .faltaHora }
        let conDia = Dictionary(grouping: lista.filter { $0.estado != .faltaHora }) { cal.startOfDay(for: $0.inicioReal ?? $0.inicio) }
        var r = conDia.keys.sorted().map { dia in
            Grupo(dia: dia, tareas: (conDia[dia] ?? []).sorted { ($0.inicioReal ?? $0.inicio) < ($1.inicioReal ?? $1.inicio) })
        }
        if !pendientes.isEmpty { r.insert(Grupo(dia: .distantPast, tareas: pendientes), at: 0) }
        return r
    }

    private var listaPestana: [Tarea] {
        switch pestana {
        case .hoy:
            return tareas.filter { t in
                t.estado == .faltaHora || (t.estado != .archivada && cal.isDateInToday(t.inicioReal ?? t.inicio))
            }
        case .tareas: return tareas.filter { visible($0) && !$0.esCita && $0.proyecto == nil }
        case .citas: return tareas.filter { visible($0) && $0.esCita }
        case .proyectos: return []
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                selector
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            if pestana == .proyectos { vistaProyectos } else if pestana == .hoy { vistaHoy } else { vistaTareas }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                    // En "Hoy" se abre mirando por dónde va el día: la línea "Ahora".
                    .onAppear { irAAhora(proxy) }
                    .onChange(of: pestana) { _, p in if p == .hoy { irAAhora(proxy) } }
                }
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Listado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // En "Hoy" puede ser cualquier cosa: pregunta qué cargar. En las otras pestañas, esa categoría.
                    if pestana == .hoy {
                        Menu {
                            Button { cargando = .tarea } label: { Label("Tarea", systemImage: "checkmark.circle") }
                            Button { cargando = .cita } label: { Label("Cita", systemImage: "calendar") }
                            Button { cargando = .proyecto } label: { Label("Proyecto", systemImage: "square.stack.3d.up") }
                            Button { cargando = .idea } label: { Label("Idea", systemImage: "lightbulb") }
                        } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Cargar a mano")
                    } else {
                        Button {
                            cargando = pestana == .proyectos ? .proyecto : (pestana == .citas ? .cita : .tarea)
                        } label: { Image(systemName: "plus") }
                        .accessibilityLabel(pestana == .proyectos ? "Nuevo proyecto" : (pestana == .citas ? "Nueva cita" : "Nueva tarea"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } }
            }
            .sheet(item: $cargando) { c in CargarAMano(categoria: c).environment(\.paleta, paleta) }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
        .onAppear { pestana = pestanaInicial }
    }

    private var selector: some View {
        HStack(spacing: 4) {
            ForEach(PestanaLista.allCases) { p in
                Button { withAnimation(.easeInOut(duration: 0.2)) { pestana = p } } label: {
                    Text(p.rawValue)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(pestana == p ? paleta.primario.color : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(pestana == p ? paleta.fondo.color : paleta.texto.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pestana == p ? .isSelected : [])
            }
        }
        .padding(3)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 13))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var vistaTareas: some View {
        let lista = listaPestana
        if lista.isEmpty {
            Text(pestana == .hoy ? "Nada más para hoy." : "No hay nada acá todavía.")
                .foregroundStyle(paleta.secundario.color).padding(.top, 40)
                .frame(maxWidth: .infinity)
        }
        ForEach(grupos(lista)) { grupo in
            Text(titulo(grupo.dia))
                .font(.serif(22, relativoA: .title3))
                .foregroundStyle(paleta.primario.color)
                .padding(.top, 10)
            ForEach(grupo.tareas, id: \.uid) { t in
                NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: { TarjetaTarea(tarea: t, paleta: paleta) }
                    .buttonStyle(.plain)
            }
        }
        if pestana != .hoy {
            Toggle("Mostrar hechas y archivadas", isOn: $verHechas)
                .tint(paleta.primario.color)
                .padding(.top, 20)
        }
    }

    private func irAAhora(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if pestana == .hoy { proxy.scrollTo("ahora", anchor: UnitPoint(x: 0.5, y: 0.06)) }
        }
    }

    /// Hoy: lo hecho arriba (plegable), la línea "Ahora", lo que falta elegir hora y lo que viene.
    @ViewBuilder
    private var vistaHoy: some View {
        let deHoy = tareas.filter { t in
            t.estado != .archivada && t.estado != .faltaHora && cal.isDateInToday(t.inicioReal ?? t.inicio)
        }
        let hechas = deHoy.filter { $0.estado == .terminada }
        let resto = deHoy.filter { $0.estado != .terminada }.sorted { ($0.inicioReal ?? $0.inicio) < ($1.inicioReal ?? $1.inicio) }
        let sinHora = tareas.filter { $0.estado == .faltaHora }
        if !hechas.isEmpty {
            Button { withAnimation(.easeInOut(duration: 0.25)) { hechasPlegado.toggle() } } label: {
                HStack {
                    Text("Hecho hoy · \(hechas.count)").font(.serif(20, relativoA: .title3))
                    Spacer()
                    Image(systemName: hechasPlegado ? "chevron.down" : "chevron.up").font(.subheadline)
                }
                .foregroundStyle(paleta.primario.color)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityHint(hechasPlegado ? "Mostrar lo hecho" : "Plegar lo hecho")
            if !hechasPlegado {
                ForEach(hechas, id: \.uid) { t in
                    NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: { TarjetaTarea(tarea: t, paleta: paleta) }
                        .buttonStyle(.plain)
                }
            }
        }
        HStack(spacing: 6) {
            Circle().fill(paleta.primario.color).frame(width: 8, height: 8)
            Text("Ahora · \(Formato.hora(.now))").font(.caption.weight(.bold)).foregroundStyle(paleta.primario.color)
            Rectangle().fill(paleta.primario.color).frame(height: 1.5)
        }
        .padding(.vertical, 8)
        .id("ahora")
        if !sinHora.isEmpty {
            Text("Falta elegir hora").font(.serif(20, relativoA: .title3)).foregroundStyle(paleta.primario.color)
            ForEach(sinHora, id: \.uid) { t in
                NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: { TarjetaTarea(tarea: t, paleta: paleta) }
                    .buttonStyle(.plain)
            }
        }
        if resto.isEmpty && sinHora.isEmpty {
            Text("Nada más por hoy.").foregroundStyle(paleta.secundario.color).padding(.top, 20).frame(maxWidth: .infinity)
        }
        ForEach(resto, id: \.uid) { t in
            NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: { TarjetaTarea(tarea: t, paleta: paleta) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var vistaProyectos: some View {
        if activos.isEmpty {
            Text("Ningún proyecto por ahora. Dictá uno o tocá “Nuevo proyecto”.")
                .font(.subheadline).foregroundStyle(paleta.secundario.color).padding(.top, 30)
        }
        ForEach(activos, id: \.uid) { p in
            NavigationLink { ProyectoDetalleView(proyecto: p, paleta: paleta) } label: { TarjetaProyecto(proyecto: p, paleta: paleta) }
                .buttonStyle(.plain)
        }
        Button { cargando = .proyecto } label: {
            Label("Nuevo proyecto", systemImage: "plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
        }
        .foregroundStyle(paleta.primario.color)
        .padding(.top, 6)
        let archivados = proyectos.filter(\.archivado)
        if !archivados.isEmpty {
            Toggle("Mostrar archivados (\(archivados.count))", isOn: $verArchivados)
                .tint(paleta.primario.color)
                .padding(.top, 16)
            if verArchivados {
                ForEach(archivados, id: \.uid) { p in
                    HStack {
                        Text(p.titulo).font(.serif(17, relativoA: .body)).foregroundStyle(paleta.secundario.color)
                        Spacer()
                        Button("Recuperar") { p.archivado = false; Acciones.guardar(ctx) }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(paleta.superficie.color.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func titulo(_ dia: Date) -> String {
        if dia == .distantPast { return "Falta elegir hora" }
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
        let t = tarea
        let apagada = t.estado == .terminada || t.estado == .archivada
        TarjetaBanda(categoria: t.categoria, paleta: paleta) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    EtiquetaCategoria(categoria: t.categoria, paleta: paleta, extra: t.proyecto?.titulo)
                    Spacer()
                    if t.estado != .programada {
                        Text(t.estado.nombre)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(t.estado == .faltaHora ? Paleta.aviso.color : paleta.secundario.color)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(t.titulo)
                        .font(.serif(18, relativoA: .headline))
                        .strikethrough(t.estado == .terminada)
                        .foregroundStyle(apagada ? paleta.secundario.color : paleta.texto.color)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(t.estado == .faltaHora ? "—" : Formato.hora(t.inicioReal ?? t.inicio))
                        .font(.serif(17, relativoA: .headline))
                        .monospacedDigit()
                }
                Text(detalle).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
            }
        }
        .opacity(apagada ? 0.55 : 1)
    }

    private var detalle: String {
        var partes = [Formato.minutos(tarea.duracionMinutos)]
        if let s = tarea.salida { partes.append("salí \(Formato.hora(s))") }
        if !tarea.lugar.isEmpty { partes.append(tarea.lugar) }
        if !tarea.pasos.isEmpty { partes.append("\(tarea.pasos.filter(\.hecho).count)/\(tarea.pasos.count) pasos") }
        if tarea.pasos.isEmpty && !tarea.notas.isEmpty { partes.append(tarea.notas) }
        return partes.joined(separator: " · ")
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
                        HStack(spacing: 2) {
                            ForEach(categorias(d), id: \.self) { c in Circle().fill(c.rgb.color).frame(width: 5, height: 5) }
                        }
                        .frame(height: 5)
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
                    .fill(paleta.fondo.color)
                    .overlay(Rayado().stroke(Categoria.tarea.rgb.color.opacity(0.55), lineWidth: 1.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Categoria.tarea.rgb.color.opacity(0.6), lineWidth: 1))
                    .overlay(alignment: .leading) {
                        Text("\(r.titulo) · slot cerrado")
                            .font(.caption).foregroundStyle(paleta.secundario.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(paleta.fondo.color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .padding(.leading, 6)
                            .lineLimit(1)
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
                    .padding(.leading, 4)
                    .background(t.categoria.fondo(en: paleta).opacity(t.estado == .terminada ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(t.categoria.rgb.color).frame(width: 3).padding(.vertical, 5).padding(.leading, 3)
                    }
                    .overlay {
                        if t.estado == .enCurso { RoundedRectangle(cornerRadius: 10).stroke(paleta.energia.color, lineWidth: 1.5) }
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

    /// Las categorías de lo que hay ese día, para los puntitos de color de la semana (como máximo tres).
    private func categorias(_ d: Date) -> [Categoria] {
        let delDia = tareas.filter { ($0.ocupaAgenda || $0.estado == .terminada) && cal.isDate($0.inicioReal ?? $0.inicio, inSameDayAs: d) }
        return Categoria.allCases.filter { c in delDia.contains { $0.categoria == c } }.prefix(3).map { $0 }
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
