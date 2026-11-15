import SwiftUI
import SwiftData

// MARK: - Armar o rearmar las etapas

@MainActor
enum PlanProyecto {
    /// Archiva el proyecto y sus sesiones pendientes (sin avisos ni calendario). Se puede recuperar.
    static func archivar(_ p: Proyecto, ctx: ModelContext) {
        p.archivado = true
        for t in p.tareas where t.estado != .terminada && t.estado != .archivada { Acciones.archivar(t, ctx: ctx) }
        Acciones.guardar(ctx)
    }

    /// Borra el proyecto, sus etapas y sus sesiones. No se puede deshacer.
    static func borrar(_ p: Proyecto, ctx: ModelContext) {
        for t in p.tareas { Acciones.borrar(t, ctx: ctx) }
        ctx.delete(p)
        Acciones.guardar(ctx)
    }

    /// Arma las etapas con la IA según el nombre y las notas.
    /// - `todo`: rearmar todo (por ejemplo, al cambiar el nombre). Las sesiones pendientes del plan anterior se archivan;
    ///   lo terminado queda. Si no, se conservan las etapas cumplidas o con sesiones y las sueltas pasan a la primera nueva.
    static func rearmar(_ p: Proyecto, todo: Bool, ctx: ModelContext) async throws {
        let cal = Calendar.current
        let inicioPlan = max(cal.startOfDay(for: .now), cal.startOfDay(for: p.inicioEfectivo))
        let plan = try await ClienteClaude.armarEtapas(titulo: p.titulo, notas: p.notas,
                                                       inicio: inicioPlan, fin: max(inicioPlan, cal.startOfDay(for: p.ultimoDia)))
        if todo {
            for t in p.tareas where t.estado != .terminada && t.estado != .archivada { Acciones.archivar(t, ctx: ctx) }
        }
        let conservadas = p.etapasOrdenadas.filter { e in
            e.cumplida || e.tareas.contains { todo ? $0.estado == .terminada : $0.estado != .archivada }
        }
        for e in p.etapasOrdenadas where !conservadas.contains(where: { $0.uid == e.uid }) {
            for t in e.tareas { t.etapa = nil }
            ctx.delete(e)
        }
        let desde = max(conservadas.last?.fechaObjetivo ?? p.inicioEfectivo, p.inicioEfectivo)
        let pesos = plan.etapas.map { max(0.05, $0.dias) }
        if p.deadline.timeIntervalSince(desde) < Plan.minimo * Double(max(1, pesos.count)) {
            p.deadline = cal.date(byAdding: .day, value: max(1, Int(pesos.reduce(0, +).rounded(.up))), to: cal.startOfDay(for: desde)) ?? p.deadline
        }
        let fines = Plan.repartir(inicio: desde, fin: p.deadline, pesos: pesos)
        var primera: Etapa?
        for (k, ep) in plan.etapas.enumerated() {
            let e = Etapa(titulo: ep.titulo, fechaObjetivo: fines.indices.contains(k) ? fines[k] : p.deadline, orden: conservadas.count + k)
            ctx.insert(e)
            e.proyecto = p
            if k == 0 { primera = e }
        }
        for (k, e) in conservadas.enumerated() { e.orden = k }
        let sueltas = p.tareas.filter { $0.etapa == nil && $0.estado != .archivada }
        for t in sueltas { t.etapa = primera }
        // Si no queda nada pendiente, las sesiones de la primera etapa nueva se agendan en huecos libres.
        let pendientes = p.tareas.contains { $0.estado == .programada || $0.estado == .faltaHora }
        if !pendientes, let primera {
            let todas = (try? ctx.fetch(FetchDescriptor<Tarea>())) ?? []
            var ocupado = Guardado.ocupados(todas)
            var hora = max(Date.now, p.inicioEfectivo)
            for tp in plan.tareas_primera_etapa {
                let dur = max(10, tp.duracion_min)
                let hueco = Guardado.huecos(duracion: dur, desde: hora, ocupados: ocupado)
                let t = Tarea(titulo: tp.titulo, inicio: hueco ?? .now, duracionMinutos: dur)
                t.estado = hueco == nil ? .faltaHora : .programada
                ctx.insert(t)
                t.proyecto = p
                t.etapa = primera
                if let hueco {
                    ocupado.append(DateInterval(start: hueco, duration: Double(dur) * 60))
                    hora = hueco.addingTimeInterval(Double(dur) * 60)
                    Avisos.programarInicio(t)
                    Calendario.sincronizar(t)
                }
            }
        }
        Acciones.guardar(ctx)
        Registro.anotar("Etapas rearmadas (\(plan.etapas.count)).")
    }
}

// MARK: - Barras de tiempo

/// La línea de tiempo del proyecto: de la fecha de inicio a la final. Las divisiones son las etapas y la marca es hoy.
struct BarraTiempoProyecto: View {
    let proyecto: Proyecto
    var ahora: Date = .now
    var conFechas = true
    @Environment(\.paleta) private var paleta

    var body: some View {
        let inicio = proyecto.inicioEfectivo
        let total = max(1, proyecto.deadline.timeIntervalSince(inicio))
        let avance = proyecto.avanceTiempo(ahora: ahora)
        let cortes = proyecto.rangos.dropLast().map { min(1, max(0, $0.fin.timeIntervalSince(inicio) / total)) }
        let color = proyecto.atrasado(ahora: ahora) == nil ? Categoria.proyecto.rgb.color : Paleta.aviso.color
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(paleta.linea.color).frame(height: 6)
                    Capsule().fill(color).frame(width: max(6, w * avance), height: 6)
                    ForEach(Array(cortes.enumerated()), id: \.offset) { _, c in
                        Rectangle().fill(paleta.superficie.color).frame(width: 2, height: 10).offset(x: w * c - 1)
                    }
                    RoundedRectangle(cornerRadius: 1.5).fill(paleta.texto.color)
                        .frame(width: 3, height: 14)
                        .offset(x: min(w - 3, max(0, w * avance - 1.5)))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            if conFechas {
                HStack {
                    Text(Formato.diaCorto(inicio))
                    Spacer()
                    Text("hoy")
                    Spacer()
                    Text(Formato.diaCorto(proyecto.ultimoDia))
                }
                .font(.caption2)
                .foregroundStyle(paleta.secundario.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pasó el \(Int(avance * 100)) % del tiempo del proyecto")
    }
}

/// Versión corta para las tarjetas de Inicio y la pantalla de decidir: nombre (opcional), días que faltan y la barra.
struct BarraProyecto: View {
    let proyecto: Proyecto
    var ahora: Date = .now
    var mostrarNombre = true
    @Environment(\.paleta) private var paleta

    var body: some View {
        let dias = proyecto.diasRestantes(ahora: ahora)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if mostrarNombre {
                    Text(proyecto.titulo).font(.caption.weight(.semibold)).foregroundStyle(Categoria.proyecto.texto(en: paleta))
                } else if let actual = proyecto.etapaActual {
                    Text("Etapa: \(actual.titulo)").lineLimit(1)
                }
                Spacer()
                Text(dias == 0 ? "vence hoy" : "faltan \(dias) días").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(paleta.secundario.color)
            BarraTiempoProyecto(proyecto: proyecto, ahora: ahora, conFechas: false)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tarjeta del listado

/// Un proyecto es una sola tarjeta: etapas cumplidas arriba a la derecha, la etapa actual con los días que faltan,
/// la línea de tiempo y la próxima sesión.
struct TarjetaProyecto: View {
    let proyecto: Proyecto
    let paleta: Paleta

    var body: some View {
        let dias = proyecto.diasRestantes()
        TarjetaBanda(categoria: .proyecto, paleta: paleta) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    EtiquetaCategoria(categoria: .proyecto, paleta: paleta)
                    Spacer()
                    Text("\(proyecto.etapasHechas)/\(proyecto.etapas.count)")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(paleta.secundario.color)
                        .accessibilityLabel("\(proyecto.etapasHechas) de \(proyecto.etapas.count) etapas completas")
                }
                Text(proyecto.titulo).font(.serif(21, relativoA: .headline))
                HStack {
                    Text(proyecto.etapaActual.map { "Ahora: \($0.titulo)" } ?? (proyecto.etapas.isEmpty ? "Sin etapas todavía" : "Todas las etapas cumplidas"))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(dias == 0 ? "vence hoy" : "faltan \(dias) días").monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(paleta.secundario.color)
                BarraTiempoProyecto(proyecto: proyecto).padding(.top, 6)
                if let atraso = proyecto.atrasado() {
                    Label("Va atrasada: \(atraso.titulo)", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Paleta.aviso.color)
                }
                if let s = proyecto.proximaSesion {
                    Divider().overlay(paleta.linea.color).padding(.vertical, 4)
                    HStack {
                        Text("Próxima sesión").foregroundStyle(paleta.secundario.color)
                        Spacer(minLength: 8)
                        Text("\(s.titulo) · \(Formato.diaYHora(s.inicio, ahora: .now))").lineLimit(1)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

// MARK: - Dentro del proyecto

/// La carpeta abierta: etapas que se abren (solo la actual muestra sus sesiones), manijas para reordenar y
/// la ficha de cada etapa para cambiarle el nombre o lo que dura.
struct ProyectoDetalleView: View {
    @Bindable var proyecto: Proyecto
    let paleta: Paleta

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var volver
    @State private var abiertas: Set<UUID> = []
    @State private var nuevaSesionEn: Etapa?
    @State private var creandoSesion = false
    @State private var editandoProyecto = false
    @State private var editandoEtapa: Etapa?
    @State private var replanteo: ReplanteoIA?
    @State private var pensando = false
    @State private var mensaje: String?
    @State private var aviso: String?
    @State private var armando = false
    @State private var confirmarBorrado = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    EtiquetaCategoria(categoria: .proyecto, paleta: paleta)
                    Text(proyecto.titulo).font(.tituloTarea)
                    Text("\(Formato.diaSemana(proyecto.inicioEfectivo)) a \(Formato.diaSemana(proyecto.ultimoDia)) · \(Formato.duracion(proyecto.deadline.timeIntervalSince(proyecto.inicioEfectivo)))")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    BarraTiempoProyecto(proyecto: proyecto).padding(.top, 8)
                    if !proyecto.notas.isEmpty {
                        Text(proyecto.notas).font(.callout).foregroundStyle(paleta.secundario.color).padding(.top, 4)
                    }
                }

                if let atraso = proyecto.atrasado() {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("“\(atraso.titulo)” ya tenía que estar. Pasa; replanteamos sin culpa.").font(.subheadline)
                        Button {
                            Task { await replantear() }
                        } label: {
                            if pensando { ProgressView() } else { Label("Replantear", systemImage: "arrow.triangle.2.circlepath") }
                        }
                        .buttonStyle(BotonPrimario(paleta: paleta))
                        .disabled(pensando || !ClaveIA.hay)
                    }
                    .padding(14)
                    .background(Paleta.aviso.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                }

                Text("Etapas").font(.serif(21, relativoA: .title3)).foregroundStyle(paleta.primario.color).padding(.top, 6)
                if proyecto.etapas.isEmpty {
                    Text("Todavía no tiene etapas.").font(.footnote).foregroundStyle(paleta.secundario.color)
                    if ClaveIA.hay {
                        Button { Task { await armarEtapas() } } label: {
                            if armando { ProgressView().tint(paleta.fondo.color) } else { Label("Armar las etapas", systemImage: "sparkles") }
                        }
                        .buttonStyle(BotonPrimario(paleta: paleta))
                        .disabled(armando)
                    }
                }
                ListaReordenable(items: proyecto.rangos.map(FilaPlan.init), movible: { !$0.etapa.cumplida },
                                 alMover: moverEtapa) { fila, manija in
                    etapaView(fila, manija: manija)
                }

                Button { agregarEtapa() } label: { Label("Agregar etapa", systemImage: "plus") }
                    .padding(.top, 2)

                let sueltas = proyecto.tareas.filter { $0.etapa == nil && $0.estado != .archivada }
                if !sueltas.isEmpty {
                    Text("Sesiones sin etapa").font(.serif(19, relativoA: .headline)).padding(.top, 8)
                    Text("Son sesiones del proyecto que no están en ninguna etapa. Con la flecha las pasás a una.")
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                    ForEach(sueltas.sorted { $0.inicio < $1.inicio }, id: \.uid) { t in
                        filaSesion(t, manija: nil)
                            .overlay(alignment: .trailing) {
                                if !proyecto.etapas.isEmpty {
                                    Menu {
                                        ForEach(proyecto.etapasOrdenadas, id: \.uid) { e in
                                            Button(e.titulo) { t.etapa = e; Acciones.guardar(ctx) }
                                        }
                                    } label: {
                                        Image(systemName: "arrow.turn.down.right").frame(width: 36, height: 40)
                                    }
                                    .foregroundStyle(paleta.primario.color)
                                    .accessibilityLabel("Pasar a una etapa")
                                }
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Button("Editar nombre, fechas y notas") { editandoProyecto = true }
                    Button("Archivar proyecto") {
                        PlanProyecto.archivar(proyecto, ctx: ctx)
                        volver()
                    }
                    Button("Borrar proyecto", role: .destructive) { confirmarBorrado = true }
                }
                .padding(.top, 16)
            }
            .padding(20)
        }
        .overlay(alignment: .bottom) {
            if let aviso {
                Text(aviso)
                    .font(.footnote)
                    .foregroundStyle(paleta.fondo.color)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(paleta.texto.color.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .foregroundStyle(paleta.texto.color)
        .tint(paleta.primario.color)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if abiertas.isEmpty, let a = proyecto.etapaActual { abiertas = [a.uid] } }
        .task(id: aviso) {
            guard aviso != nil else { return }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation { aviso = nil }
        }
        .sheet(isPresented: $creandoSesion) {
            NuevaTareaView(tarea: nil, proyectoInicial: proyecto, etapaInicial: nuevaSesionEn).environment(\.paleta, paleta)
        }
        .sheet(isPresented: $editandoProyecto) { EditarProyectoView(proyecto: proyecto).environment(\.paleta, paleta) }
        .sheet(item: $editandoEtapa) { e in EditarEtapaView(etapa: e, proyecto: proyecto).environment(\.paleta, paleta) }
        .alert("Nuevo plan", isPresented: Binding(get: { replanteo != nil }, set: { if !$0 { replanteo = nil } })) {
            Button("Aplicar") { aplicarReplanteo() }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(textoReplanteo)
        }
        .alert(mensaje ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
            Button("Listo", role: .cancel) {}
        }
        .confirmationDialog("¿Borrar “\(proyecto.titulo)”?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Borrar el proyecto y sus sesiones", role: .destructive) {
                let p = proyecto
                volver()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { PlanProyecto.borrar(p, ctx: ctx) }
            }
        } message: {
            Text("No se puede deshacer. Si solo querés sacarlo de la vista, archivalo: se puede recuperar.")
        }
    }

    private func armarEtapas() async {
        armando = true
        defer { armando = false }
        do {
            try await PlanProyecto.rearmar(proyecto, todo: false, ctx: ctx)
            if let a = proyecto.etapaActual { abiertas = [a.uid] }
        } catch {
            mensaje = error.localizedDescription
        }
    }

    struct FilaPlan: Identifiable {
        let etapa: Etapa
        let inicio: Date
        let fin: Date
        var id: UUID { etapa.uid }
        init(_ r: (etapa: Etapa, inicio: Date, fin: Date)) { etapa = r.etapa; inicio = r.inicio; fin = r.fin }
    }

    private func etapaView(_ fila: FilaPlan, manija: Manija) -> some View {
        let etapa = fila.etapa
        let actual = proyecto.etapaActual?.uid == etapa.uid
        let abierta = abiertas.contains(etapa.uid)
        let numero = (proyecto.etapasOrdenadas.firstIndex { $0.uid == etapa.uid } ?? 0) + 1
        let vencida = !etapa.cumplida && etapa.fechaObjetivo < .now
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Categoria.proyecto.rgb.color, lineWidth: 1.5)
                    if etapa.cumplida { Circle().fill(Categoria.proyecto.rgb.color) }
                    Text(etapa.cumplida ? "✓" : "\(numero)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(etapa.cumplida ? Color.white : Categoria.proyecto.texto(en: paleta))
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(etapa.titulo).font(.serif(18, relativoA: .headline))
                        .foregroundStyle(etapa.cumplida ? paleta.secundario.color : paleta.texto.color)
                    Text(Formato.rango(fila.inicio, fila.fin) + (actual ? " · ahora" : ""))
                        .font(.caption)
                        .foregroundStyle(vencida ? Paleta.aviso.color : paleta.secundario.color)
                }
                Spacer(minLength: 4)
                Button { editandoEtapa = etapa } label: {
                    Image(systemName: "pencil").frame(width: 34, height: 40)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(paleta.primario.color)
                .accessibilityLabel("Editar la etapa \(etapa.titulo)")
                manija
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if abierta { abiertas.remove(etapa.uid) } else { abiertas.insert(etapa.uid) }
                }
            }

            if abierta {
                VStack(alignment: .leading, spacing: 0) {
                    let sesiones = ordenSesiones(etapa)
                    if sesiones.isEmpty {
                        Text(etapa.cumplida ? "Terminada." : (actual ? "Todavía no tiene sesiones." : "Las sesiones de esta etapa se arman cuando llegues a ella."))
                            .font(.footnote).italic()
                            .foregroundStyle(paleta.secundario.color)
                            .padding(.vertical, 6)
                    } else {
                        ListaReordenable(items: sesiones, espacio: 0, movible: { $0.estado == .programada },
                                         alMover: { d, h in moverSesion(sesiones, desde: d, hasta: h) }) { t, m in
                            filaSesion(t, manija: m)
                        }
                    }
                    Button { nuevaSesionEn = etapa; creandoSesion = true } label: {
                        Label("Sesión", systemImage: "plus")
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 12)
            }
        }
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(actual ? Categoria.proyecto.rgb.color : paleta.linea.color, lineWidth: actual ? 1.5 : 1))
    }

    private func filaSesion(_ t: Tarea, manija: Manija?) -> some View {
        let hoy = Calendar.current.isDateInToday(t.inicio)
        return HStack(spacing: 8) {
            NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        if t.estado == .faltaHora {
                            Text("Falta hora").foregroundStyle(Paleta.aviso.color)
                        } else {
                            Text(hoy ? "Hoy" : Formato.diaSemana(t.inicio).components(separatedBy: " ").prefix(2).joined(separator: " "))
                            if t.estado != .terminada { Text(Formato.hora(t.inicio)) }
                        }
                    }
                    .font(.serif(14, relativoA: .footnote))
                    .foregroundStyle(hoy ? paleta.primario.color : paleta.secundario.color)
                    .frame(width: 62, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.titulo)
                            .font(.subheadline)
                            .strikethrough(t.estado == .terminada)
                            .foregroundStyle(t.estado == .terminada ? paleta.secundario.color : paleta.texto.color)
                        Text(Formato.minutos(t.duracionMinutos)).font(.caption2).foregroundStyle(paleta.secundario.color)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let manija { manija } else { Color.clear.frame(width: 36, height: 40) }
        }
        .padding(.vertical, 2)
        .background(paleta.superficie.color)
        .overlay(alignment: .top) { Rectangle().fill(paleta.linea.color).frame(height: 1) }
    }

    /// Hechas primero, después las agendadas por hora y al final las que no tienen hora.
    private func ordenSesiones(_ etapa: Etapa) -> [Tarea] {
        let lista = etapa.tareas.filter { $0.estado != .archivada }
        let hechas = lista.filter { $0.estado == .terminada }.sorted { ($0.inicioReal ?? $0.inicio) < ($1.inicioReal ?? $1.inicio) }
        let agendadas = lista.filter { $0.estado == .programada || $0.estado == .enCurso || $0.estado == .pausada }.sorted { $0.inicio < $1.inicio }
        let sinHora = lista.filter { $0.estado == .faltaHora }
        return hechas + agendadas + sinHora
    }

    /// Cada sesión toma el turno (la hora) del lugar al que va.
    private func moverSesion(_ sesiones: [Tarea], desde d: Int, hasta h: Int) {
        let turnos = sesiones.filter { $0.estado == .programada }.map(\.inicio)
        let nuevas = Plan.mover(sesiones, desde: d, hasta: h).filter { $0.estado == .programada }
        for (t, turno) in zip(nuevas, turnos) where t.inicio != turno {
            t.inicio = turno
            Avisos.programarInicio(t)
            Calendario.sincronizar(t)
        }
        Acciones.guardar(ctx)
        withAnimation { aviso = "Cada sesión tomó el horario del lugar al que fue." }
    }

    /// Las etapas mantienen lo que duran y las fechas se reparten de nuevo en el orden nuevo.
    private func moverEtapa(desde d: Int, hasta h: Int) {
        let rangos = proyecto.rangos
        let etapas = Plan.mover(rangos.map(\.etapa), desde: d, hasta: h)
        let duraciones = Plan.mover(rangos.map { $0.fin.timeIntervalSince($0.inicio) }, desde: d, hasta: h)
        let fines = Plan.fines(inicio: proyecto.inicioEfectivo, duraciones: duraciones)
        for (k, e) in etapas.enumerated() {
            e.orden = k
            e.fechaObjetivo = fines[k]
        }
        Acciones.guardar(ctx)
        withAnimation { aviso = "Las fechas de las etapas se repartieron de nuevo." }
    }

    private func agregarEtapa() {
        let ultimoFin = proyecto.rangos.last?.fin ?? proyecto.inicioEfectivo
        var fin = proyecto.deadline
        if proyecto.deadline.timeIntervalSince(ultimoFin) < Plan.minimo {
            fin = ultimoFin.addingTimeInterval(86_400)
            proyecto.deadline = fin
            withAnimation { aviso = "Corrí la fecha final al \(Formato.diaCorto(proyecto.ultimoDia)) para que entre." }
        }
        let e = Etapa(titulo: "Etapa nueva", fechaObjetivo: fin, orden: proyecto.etapas.count)
        ctx.insert(e)
        e.proyecto = proyecto
        Acciones.guardar(ctx)
        editandoEtapa = e
    }

    private var textoReplanteo: String {
        guard let r = replanteo else { return "" }
        let fechas = r.etapas.compactMap { e in FechasIA.dia(e.fecha).map { "\(e.titulo): \(Formato.diaCorto($0))" } }
        return r.explicacion + "\n\n" + fechas.joined(separator: "\n")
    }

    private func replantear() async {
        pensando = true
        defer { pensando = false }
        do { replanteo = try await ClienteClaude.replantear(proyecto) }
        catch { mensaje = error.localizedDescription }
    }

    private func aplicarReplanteo() {
        guard let r = replanteo else { return }
        for e in r.etapas {
            if let fecha = FechasIA.dia(e.fecha), let etapa = proyecto.etapas.first(where: { $0.titulo == e.titulo && !$0.cumplida }) {
                etapa.fechaObjetivo = min(fecha, proyecto.deadline)
            }
        }
        proyecto.replanteos += 1
        Acciones.guardar(ctx)
        Registro.anotar("Proyecto replanteado (\(proyecto.replanteos) seguidos).")
    }
}

// MARK: - Ficha de una etapa

/// Nombre y duración de una etapa (en días o, si es corta, en horas). Si al alargarla el plan se pasa de la
/// fecha final, ofrece correr la fecha final o achicar las etapas que siguen.
struct EditarEtapaView: View {
    let etapa: Etapa
    let proyecto: Proyecto

    enum Unidad: String, CaseIterable { case dias = "Días", horas = "Horas" }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta
    @State private var titulo = ""
    @State private var unidad: Unidad = .dias
    @State private var cantidad = 1
    @State private var cumplida = false
    @State private var excede: [Date]?
    @State private var confirmarBorrado = false

    private var indice: Int { proyecto.etapasOrdenadas.firstIndex { $0.uid == etapa.uid } ?? 0 }
    private var rango: (inicio: Date, fin: Date) {
        let r = proyecto.rangos
        return r.indices.contains(indice) ? (r[indice].inicio, r[indice].fin) : (proyecto.inicioEfectivo, etapa.fechaObjetivo)
    }
    private var nuevaDuracion: TimeInterval { Double(cantidad) * (unidad == .dias ? 86_400 : 3600) }
    private var finesNuevos: [Date] {
        Plan.cambiarDuracion(inicio: proyecto.inicioEfectivo, fines: proyecto.etapasOrdenadas.map(\.fechaObjetivo),
                             indice: indice, a: nuevaDuracion)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre de la etapa", text: $titulo).font(.serif(20, relativoA: .title3))
                }
                Section {
                    Picker("Unidad", selection: $unidad) {
                        ForEach(Unidad.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unidad) { _, u in cantidad = u == .dias ? max(1, cantidad / 24) : min(72, cantidad * 24) }
                    Stepper(value: $cantidad, in: 1...(unidad == .dias ? 365 : 72)) {
                        Text(unidad == .dias ? (cantidad == 1 ? "1 día" : "\(cantidad) días") : (cantidad == 1 ? "1 hora" : "\(cantidad) horas"))
                            .font(.serif(20, relativoA: .title3))
                    }
                    let fines = finesNuevos
                    if fines.indices.contains(indice) {
                        Text(Formato.rango(rango.inicio, fines[indice]))
                            .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    }
                } header: {
                    Text("Cuánto dura")
                } footer: {
                    Text("Las etapas que siguen se corren y mantienen lo que duran.")
                }
                Section {
                    Toggle("Etapa terminada", isOn: $cumplida).tint(paleta.primario.color)
                }
                Section {
                    Button("Borrar etapa", role: .destructive) { confirmarBorrado = true }
                } footer: {
                    Text("Sus sesiones quedan en el proyecto, sin etapa.")
                }
            }
            .navigationTitle("Etapa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar).disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: cargar)
            .confirmationDialog(textoExcede, isPresented: Binding(get: { excede != nil }, set: { if !$0 { excede = nil } }),
                                titleVisibility: .visible) {
                if let fines = excede, let ultimo = fines.last {
                    Button("Correr la fecha final al \(Formato.diaCorto(ultimo.addingTimeInterval(-60)))") {
                        aplicar(fines, deadline: ultimo)
                    }
                    if let achicadas = Plan.achicar(inicio: proyecto.inicioEfectivo, fines: fines, despuesDe: indice, limite: proyecto.deadline) {
                        Button("Achicar las etapas que siguen") { aplicar(achicadas, deadline: nil) }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog("¿Borrar la etapa “\(etapa.titulo)”?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { borrar() }
            }
        }
        .tint(paleta.primario.color)
    }

    private var textoExcede: String {
        guard let ultimo = excede?.last else { return "" }
        let diferencia = ultimo.timeIntervalSince(proyecto.deadline)
        return "Así el plan se pasa de la fecha final (\(Formato.diaCorto(proyecto.ultimoDia))) por \(Formato.duracion(diferencia))."
    }

    private func cargar() {
        titulo = etapa.titulo
        cumplida = etapa.cumplida
        let d = rango.fin.timeIntervalSince(rango.inicio)
        if d < 86_400 * 0.95 {
            unidad = .horas
            cantidad = max(1, min(72, Int((d / 3600).rounded())))
        } else {
            unidad = .dias
            cantidad = max(1, Int((d / 86_400).rounded()))
        }
    }

    private func guardar() {
        let fines = finesNuevos
        if let ultimo = fines.last, ultimo > proyecto.deadline.addingTimeInterval(60) {
            excede = fines
            return
        }
        aplicar(fines, deadline: nil)
    }

    private func aplicar(_ fines: [Date], deadline: Date?) {
        etapa.titulo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        if cumplida && !etapa.cumplida && etapa.fechaObjetivo >= Calendar.current.startOfDay(for: .now) {
            // Un hito cumplido a tiempo resetea el contador de replanteos.
            proyecto.replanteos = 0
        }
        etapa.cumplida = cumplida
        for (e, f) in zip(proyecto.etapasOrdenadas, fines) { e.fechaObjetivo = f }
        if let deadline { proyecto.deadline = deadline }
        Acciones.guardar(ctx)
        cerrar()
    }

    private func borrar() {
        for t in etapa.tareas { t.etapa = nil }
        ctx.delete(etapa)
        for (k, e) in proyecto.etapasOrdenadas.filter({ $0.uid != etapa.uid }).enumerated() { e.orden = k }
        Acciones.guardar(ctx)
        cerrar()
    }
}

// MARK: - Fechas: dos campos y un calendario para marcar el rango

/// "Empieza" y "Termina". Al tocar un campo se abre el calendario y se va marcando el rango, con lo que dura.
struct SelectorRango: View {
    @Binding var inicio: Date
    @Binding var fin: Date

    @Environment(\.paleta) private var paleta
    @State private var abierto = false
    @State private var eligiendoFin = false
    @State private var mes = Date.now

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                campo("Empieza", inicio, activo: abierto && !eligiendoFin) { abrir(eligiendoFin: false, en: inicio) }
                campo("Termina", fin, activo: abierto && eligiendoFin) { abrir(eligiendoFin: true, en: fin) }
            }
            Text("Dura \(Formato.duracion(cal.date(byAdding: .day, value: 1, to: fin)!.timeIntervalSince(inicio)))")
                .font(.subheadline)
                .foregroundStyle(paleta.secundario.color)
            if abierto { calendario }
        }
    }

    private func abrir(eligiendoFin e: Bool, en fecha: Date) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if abierto && eligiendoFin == e { abierto = false; return }
            eligiendoFin = e
            mes = fecha
            abierto = true
        }
    }

    private func campo(_ nombre: String, _ fecha: Date, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre).font(.caption).foregroundStyle(paleta.secundario.color)
                Text(Formato.diaSemana(fecha)).font(.serif(18, relativoA: .headline)).foregroundStyle(paleta.texto.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(activo ? Categoria.proyecto.rgb.color : paleta.linea.color, lineWidth: activo ? 1.5 : 1))
        }
        .buttonStyle(.borderless)
    }

    private var calendario: some View {
        let primero = cal.date(from: cal.dateComponents([.year, .month], from: mes)) ?? mes
        let dias = cal.range(of: .day, in: .month, for: primero)?.count ?? 30
        let desfase = (cal.component(.weekday, from: primero) + 5) % 7
        let columnas = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return VStack(spacing: 8) {
            HStack {
                Button { mover(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 32) }
                    .accessibilityLabel("Mes anterior")
                Spacer()
                Text(Formato.primeraMayuscula(primero.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es")))))
                    .font(.serif(17, relativoA: .headline))
                Spacer()
                Button { mover(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 32) }
                    .accessibilityLabel("Mes siguiente")
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: columnas, spacing: 2) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption2).foregroundStyle(paleta.secundario.color)
                }
                ForEach(0..<(desfase + dias), id: \.self) { k in
                    if k < desfase {
                        Color.clear.frame(height: 34)
                    } else if let dia = cal.date(byAdding: .day, value: k - desfase, to: primero) {
                        celda(dia)
                    }
                }
            }
            Text(eligiendoFin ? "Tocá el último día." : "Tocá el primer día.")
                .font(.caption).foregroundStyle(paleta.secundario.color)
        }
        .padding(10)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func celda(_ dia: Date) -> some View {
        let esInicio = cal.isDate(dia, inSameDayAs: inicio)
        let esFin = cal.isDate(dia, inSameDayAs: fin)
        let adentro = dia > inicio && dia < fin
        let hoy = cal.isDateInToday(dia)
        let color = Categoria.proyecto.rgb.color
        return Button { tocar(dia) } label: {
            Text("\(cal.component(.day, from: dia))")
                .font(.subheadline.weight(hoy ? .bold : .regular))
                .underline(hoy)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(adentro ? color.opacity(0.28) : .clear)
                .background {
                    if esInicio || esFin { Capsule().fill(color) }
                }
                .foregroundStyle(esInicio || esFin ? Color.white : paleta.texto.color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func tocar(_ dia: Date) {
        let d = cal.startOfDay(for: dia)
        if !eligiendoFin || d < inicio {
            inicio = d
            fin = d
            eligiendoFin = true
        } else {
            fin = d
            eligiendoFin = false
        }
    }

    private func mover(_ meses: Int) {
        if let m = cal.date(byAdding: .month, value: meses, to: mes) { mes = m }
    }
}

// MARK: - Crear o editar un proyecto

/// Nombre, fechas de inicio y fin, notas. Al crearlo, "Armar las etapas" las reparte entre las dos fechas;
/// después se renombran, se reordenan o se agregan a mano.
struct EditarProyectoView: View {
    var proyecto: Proyecto?

    struct Borrador: Identifiable {
        let id = UUID()
        var titulo: String
        var peso: Double
    }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta
    @Query private var tareas: [Tarea]
    @State private var titulo = ""
    @State private var inicio = Calendar.current.startOfDay(for: .now)
    @State private var fin = Calendar.current.startOfDay(for: .now.addingTimeInterval(27 * 86_400))
    @State private var notas = ""
    @State private var etapas: [Borrador] = []
    @State private var primeras: [PropuestaIA.TareaIA] = []
    @State private var armando = false
    @State private var armadoCon = ""
    @State private var preguntarRearmar = false
    @State private var mensaje: String?
    @FocusState private var foco: Bool

    private var claveArmado: String { titulo.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + notas.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var finExclusivo: Date { Calendar.current.date(byAdding: .day, value: 1, to: fin) ?? fin }
    private var fines: [Date] { Plan.repartir(inicio: inicio, fin: finExclusivo, pesos: etapas.map(\.peso)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Nombre del proyecto", text: $titulo, axis: .vertical)
                        .font(.serif(24, relativoA: .title2))
                        .focused($foco)
                        .padding(12)
                        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                    SelectorRango(inicio: $inicio, fin: $fin)
                    TextField("Notas (opcional)", text: $notas, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($foco)
                        .padding(12)
                        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                    if proyecto == nil { seccionEtapas }
                    else {
                        Text("Si cambiás las fechas, las etapas se acomodan a las fechas nuevas manteniendo sus proporciones.")
                            .font(.footnote).foregroundStyle(paleta.secundario.color)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle(proyecto == nil ? "Nuevo proyecto" : "Editar proyecto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(proyecto == nil ? "Crear" : "Guardar", action: guardar)
                        .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { foco = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                }
            }
            .onAppear(perform: cargar)
            .overlay {
                if armando && proyecto != nil {
                    ZStack {
                        paleta.fondo.color.opacity(0.85).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Rearmando las etapas…").font(.subheadline).foregroundStyle(paleta.secundario.color)
                        }
                    }
                }
            }
            .confirmationDialog("¿Rearmo las etapas para el nombre nuevo?", isPresented: $preguntarRearmar, titleVisibility: .visible) {
                Button("Sí, rearmar las etapas") { Task { await rearmarExistente() } }
                Button("No, dejarlas como están", role: .cancel) { cerrar() }
            } message: {
                Text("Se reemplazan las etapas y las sesiones que no empezaste. Lo que ya terminaste queda.")
            }
            .onChange(of: foco) { _, enfocado in
                // Si cambiaste el nombre o las notas después de armar las etapas, se vuelven a armar.
                if !enfocado && proyecto == nil && !etapas.isEmpty && !armando && claveArmado != armadoCon && ClaveIA.hay {
                    Task { await armar() }
                }
            }
            .alert(mensaje ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
                Button("Listo", role: .cancel) {}
            }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
    }

    @ViewBuilder
    private var seccionEtapas: some View {
        Button { Task { await armar() } } label: {
            if armando { ProgressView().tint(paleta.fondo.color) } else { Label("Armar las etapas", systemImage: "sparkles") }
        }
        .buttonStyle(BotonPrimario(paleta: paleta))
        .disabled(armando || titulo.trimmingCharacters(in: .whitespaces).isEmpty || !ClaveIA.hay)
        if !ClaveIA.hay {
            Text("Para armarlas solas hace falta la clave de la IA (Ajustes). Mientras, podés agregarlas a mano.")
                .font(.footnote).foregroundStyle(paleta.secundario.color)
        } else if armando && !etapas.isEmpty {
            Text("Rearmando las etapas con el nombre nuevo…").font(.footnote).foregroundStyle(paleta.secundario.color)
        } else if etapas.isEmpty {
            Text("Si ya sabés las etapas, escribilas en las notas y las uso.").font(.footnote).foregroundStyle(paleta.secundario.color)
        }
        if !etapas.isEmpty {
            Text("Etapas").font(.serif(21, relativoA: .title3)).foregroundStyle(paleta.primario.color).padding(.top, 4)
            let f = fines
            ListaReordenable(items: etapas, espacio: 6, movible: { _ in true },
                             alMover: { d, h in etapas = Plan.mover(etapas, desde: d, hasta: h) }) { b, manija in
                let i = etapas.firstIndex { $0.id == b.id } ?? 0
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Etapa", text: Binding(get: { etapas.first { $0.id == b.id }?.titulo ?? "" },
                                                         set: { nuevo in if let k = etapas.firstIndex(where: { $0.id == b.id }) { etapas[k].titulo = nuevo } }))
                            .font(.subheadline)
                            .focused($foco)
                        if f.indices.contains(i) {
                            Text(Formato.rango(i == 0 ? inicio : f[i - 1], f[i]))
                                .font(.caption).foregroundStyle(paleta.secundario.color)
                        }
                    }
                    Button { etapas.removeAll { $0.id == b.id } } label: { Image(systemName: "xmark").font(.caption) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(paleta.secundario.color)
                        .accessibilityLabel("Quitar etapa")
                    manija
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color))
            }
            if !primeras.isEmpty {
                Text("Primeras sesiones (se agendan en huecos libres): " + primeras.map(\.titulo).joined(separator: ", "))
                    .font(.footnote).foregroundStyle(paleta.secundario.color)
            }
        }
        Button {
            etapas.append(Borrador(titulo: "Etapa \(etapas.count + 1)", peso: etapas.isEmpty ? 1 : etapas.map(\.peso).reduce(0, +) / Double(etapas.count)))
        } label: { Label("Agregar etapa", systemImage: "plus") }
        .font(.subheadline)
    }

    private func rearmarExistente() async {
        guard let p = proyecto else { return }
        armando = true
        defer { armando = false }
        do {
            try await PlanProyecto.rearmar(p, todo: true, ctx: ctx)
            cerrar()
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func cargar() {
        guard let p = proyecto, titulo.isEmpty else { return }
        titulo = p.titulo
        notas = p.notas
        inicio = Calendar.current.startOfDay(for: p.inicioEfectivo)
        fin = Calendar.current.startOfDay(for: p.ultimoDia)
    }

    private func armar() async {
        armando = true
        armadoCon = claveArmado
        defer { armando = false }
        do {
            let plan = try await ClienteClaude.armarEtapas(titulo: titulo, notas: notas, inicio: inicio, fin: fin)
            etapas = plan.etapas.map { Borrador(titulo: $0.titulo, peso: max(0.05, $0.dias)) }
            primeras = plan.tareas_primera_etapa
        } catch {
            mensaje = error.localizedDescription
        }
    }

    private func guardar() {
        let nombre = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = proyecto {
            let cambiaron = p.inicioEfectivo != inicio || p.deadline != finExclusivo
            if cambiaron && !p.etapas.isEmpty {
                // Las etapas se acomodan a las fechas nuevas, en proporción.
                let durs = Plan.duraciones(inicio: p.inicioEfectivo, fines: p.etapasOrdenadas.map(\.fechaObjetivo))
                let nuevos = Plan.repartir(inicio: inicio, fin: finExclusivo, pesos: durs.map { max(1, $0) })
                for (e, f) in zip(p.etapasOrdenadas, nuevos) { e.fechaObjetivo = f }
            }
            let cambioNombre = p.titulo != nombre || p.notas != notas
            p.titulo = nombre
            p.notas = notas
            p.fechaInicio = inicio
            p.deadline = finExclusivo
            Acciones.guardar(ctx)
            if cambioNombre && !p.etapas.isEmpty && ClaveIA.hay {
                preguntarRearmar = true
            } else {
                cerrar()
            }
            return
        }
        let p = Proyecto(titulo: nombre, deadline: finExclusivo)
        p.fechaInicio = inicio
        p.notas = notas
        ctx.insert(p)
        var primera: Etapa?
        let limpias = etapas.filter { !$0.titulo.trimmingCharacters(in: .whitespaces).isEmpty }
        let f = Plan.repartir(inicio: inicio, fin: finExclusivo, pesos: limpias.map(\.peso))
        for (i, b) in limpias.enumerated() {
            let e = Etapa(titulo: b.titulo, fechaObjetivo: f[i], orden: i)
            ctx.insert(e)
            e.proyecto = p
            if i == 0 { primera = e }
        }
        // Las sesiones de la primera etapa se agendan solas en huecos libres; se pueden mover después.
        var ocupado = Guardado.ocupados(tareas)
        var desde = max(Date.now, inicio)
        var nuevas: [Tarea] = []
        for tp in primeras {
            let dur = max(10, tp.duracion_min)
            let hueco = Guardado.huecos(duracion: dur, desde: desde, ocupados: ocupado)
            let t = Tarea(titulo: tp.titulo, inicio: hueco ?? .now, duracionMinutos: dur)
            t.estado = hueco == nil ? .faltaHora : .programada
            ctx.insert(t)
            t.proyecto = p
            t.etapa = primera
            if let hueco {
                ocupado.append(DateInterval(start: hueco, duration: Double(dur) * 60))
                desde = hueco.addingTimeInterval(Double(dur) * 60)
            }
            nuevas.append(t)
        }
        Acciones.guardar(ctx)
        for t in nuevas where t.estado == .programada {
            Avisos.programarInicio(t)
            Calendario.sincronizar(t)
        }
        Acciones.guardar(ctx)
        Registro.anotar("Proyecto creado con \(limpias.count) etapas.")
        cerrar()
    }
}
