import SwiftUI
import SwiftData

/// Barra fina del tiempo que queda hasta el deadline de un proyecto.
struct BarraProyecto: View {
    let proyecto: Proyecto
    var ahora: Date = .now
    @Environment(\.paleta) private var paleta

    var body: some View {
        let dias = max(0, Calendar.current.dateComponents([.day], from: ahora, to: proyecto.deadline).day ?? 0)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(proyecto.titulo, systemImage: "square.stack.3d.up").font(.caption.weight(.semibold))
                Spacer()
                Text(dias == 0 ? "vence hoy" : "faltan \(dias) días").font(.caption).monospacedDigit()
            }
            .foregroundStyle(paleta.secundario.color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(paleta.linea.color)
                    Capsule().fill(proyecto.atrasado(ahora: ahora) == nil ? paleta.primario.color.opacity(0.6) : Paleta.aviso.color)
                        .frame(width: geo.size.width * proyecto.avanceTiempo(ahora: ahora))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TarjetaProyecto: View {
    let proyecto: Proyecto
    let paleta: Paleta

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proyecto.titulo).font(.serif(20, relativoA: .headline))
            if let actual = proyecto.etapaActual {
                Text("Ahora: \(actual.titulo)").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            BarraProyecto(proyecto: proyecto)
            if let atraso = proyecto.atrasado() {
                Label("Va atrasada: \(atraso.titulo)", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Paleta.aviso.color)
            }
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.linea.color))
        .contentShape(Rectangle())
    }
}

/// El plan completo de un proyecto: etapas con fecha, sus tareas, la barra hasta el deadline y el replanteo.
struct ProyectoDetalleView: View {
    @Bindable var proyecto: Proyecto
    let paleta: Paleta

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var volver
    @State private var nuevaTareaEn: Etapa?
    @State private var creandoTarea = false
    @State private var editando = false
    @State private var replanteo: ReplanteoIA?
    @State private var pensando = false
    @State private var mensaje: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROYECTO").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(paleta.secundario.color)
                    Text(proyecto.titulo).font(.tituloTarea)
                    Text("Fecha final: \(proyecto.deadline.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es"))))")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    BarraProyecto(proyecto: proyecto).padding(.top, 6)
                    if !proyecto.notas.isEmpty { Text(proyecto.notas).font(.callout).foregroundStyle(paleta.secundario.color).padding(.top, 4) }
                }

                if let atraso = proyecto.atrasado() {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("“\(atraso.titulo)” ya tenía que estar. Pasa; replanteamos sin culpa.").font(.subheadline)
                        Button {
                            Task { await replantear() }
                        } label: {
                            if pensando { ProgressView() } else { Label("Replantear con Claude", systemImage: "arrow.triangle.2.circlepath") }
                        }
                        .buttonStyle(BotonPrimario(paleta: paleta))
                        .disabled(pensando)
                    }
                    .padding(14)
                    .background(Paleta.aviso.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                }

                ForEach(proyecto.etapasOrdenadas, id: \.uid) { etapa in etapaView(etapa) }

                let sueltas = proyecto.tareas.filter { $0.etapa == nil }
                if !sueltas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sin etapa").font(.serif(19, relativoA: .headline))
                        ForEach(sueltas, id: \.uid) { filaTarea($0) }
                    }
                }

                Button { nuevaTareaEn = nil; creandoTarea = true } label: { Label("Agregar tarea al proyecto", systemImage: "plus") }
                    .padding(.top, 4)
                Button("Editar proyecto") { editando = true }
                Button("Archivar proyecto", role: .destructive) {
                    proyecto.archivado = true
                    Acciones.guardar(ctx)
                    volver()
                }
            }
            .padding(20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creandoTarea) { NuevaTareaView(tarea: nil, proyectoInicial: proyecto, etapaInicial: nuevaTareaEn) }
        .sheet(isPresented: $editando) { EditarProyectoView(proyecto: proyecto) }
        .alert("Nuevo plan", isPresented: Binding(get: { replanteo != nil }, set: { if !$0 { replanteo = nil } })) {
            Button("Aplicar") { aplicarReplanteo() }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(textoReplanteo)
        }
        .alert(mensaje ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
            Button("Listo", role: .cancel) {}
        }
    }

    private func etapaView(_ etapa: Etapa) -> some View {
        let vencida = !etapa.cumplida && etapa.fechaObjetivo < .now
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    etapa.cumplida.toggle()
                    // Un hito cumplido a tiempo resetea el contador de replanteos.
                    if etapa.cumplida && etapa.fechaObjetivo >= Calendar.current.startOfDay(for: .now) { proyecto.replanteos = 0 }
                    Acciones.guardar(ctx)
                } label: {
                    Image(systemName: etapa.cumplida ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(paleta.primario.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(etapa.cumplida ? "Marcar como pendiente" : "Marcar como cumplida")
                VStack(alignment: .leading, spacing: 2) {
                    Text(etapa.titulo).font(.serif(19, relativoA: .headline)).strikethrough(etapa.cumplida)
                    Text(etapa.fechaObjetivo.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es"))))
                        .font(.caption).foregroundStyle(vencida ? Paleta.aviso.color : paleta.secundario.color)
                }
                Spacer()
                Button { nuevaTareaEn = etapa; creandoTarea = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Agregar tarea a esta etapa")
            }
            ForEach(etapa.tareas.sorted { $0.inicio < $1.inicio }, id: \.uid) { filaTarea($0) }
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .opacity(etapa.cumplida ? 0.7 : 1)
    }

    private func filaTarea(_ t: Tarea) -> some View {
        NavigationLink { DetalleTareaView(tarea: t, paleta: paleta) } label: {
            HStack(spacing: 10) {
                Image(systemName: t.estado == .terminada ? "checkmark" : "circle.dotted").foregroundStyle(paleta.primario.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.titulo).strikethrough(t.estado == .terminada)
                    Text(t.estado == .faltaHora ? "Falta hora" : Formato.diaYHora(t.inicio, ahora: .now))
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            .padding(.leading, 34)
        }
        .buttonStyle(.plain)
    }

    private var textoReplanteo: String {
        guard let r = replanteo else { return "" }
        let fechas = r.etapas.compactMap { e in FechasIA.dia(e.fecha).map { "\(e.titulo): \($0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es"))))" } }
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

/// Crear o editar un proyecto a mano: título, fecha final, notas y etapas.
struct EditarProyectoView: View {
    var proyecto: Proyecto?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @State private var titulo = ""
    @State private var deadline = Date.now.addingTimeInterval(30 * 86_400)
    @State private var notas = ""
    @State private var etapas: [(titulo: String, fecha: Date)] = []
    @FocusState private var foco: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del proyecto", text: $titulo).font(.serif(20, relativoA: .title3)).focused($foco)
                    DatePicker("Fecha final", selection: $deadline, in: Date()..., displayedComponents: .date)
                    TextField("Notas", text: $notas, axis: .vertical).lineLimit(2...5).focused($foco)
                }
                Section("Etapas") {
                    ForEach(etapas.indices, id: \.self) { i in
                        VStack(alignment: .leading) {
                            TextField("Etapa \(i + 1)", text: Binding(get: { etapas[i].titulo }, set: { etapas[i].titulo = $0 })).focused($foco)
                            DatePicker("Para", selection: Binding(get: { etapas[i].fecha }, set: { etapas[i].fecha = $0 }), displayedComponents: .date)
                                .font(.footnote)
                        }
                    }
                    .onDelete { etapas.remove(atOffsets: $0) }
                    Button("Agregar etapa") { etapas.append(("", min(deadline, .now.addingTimeInterval(7 * 86_400)))) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(proyecto == nil ? "Nuevo proyecto" : "Editar proyecto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar).disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { foco = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                }
            }
            .onAppear {
                guard let p = proyecto else { return }
                titulo = p.titulo
                deadline = p.deadline
                notas = p.notas
                etapas = p.etapasOrdenadas.map { ($0.titulo, $0.fechaObjetivo) }
            }
        }
    }

    private func guardar() {
        let p = proyecto ?? Proyecto(titulo: titulo, deadline: deadline)
        if proyecto == nil { ctx.insert(p) }
        p.titulo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        p.deadline = deadline
        p.notas = notas
        let existentes = p.etapasOrdenadas
        for (i, e) in etapas.enumerated() where !e.titulo.trimmingCharacters(in: .whitespaces).isEmpty {
            let etapa = i < existentes.count ? existentes[i] : {
                let nueva = Etapa(titulo: e.titulo, fechaObjetivo: e.fecha, orden: i)
                ctx.insert(nueva)
                nueva.proyecto = p
                return nueva
            }()
            etapa.titulo = e.titulo
            etapa.fechaObjetivo = e.fecha
            etapa.orden = i
        }
        for sobrante in existentes.dropFirst(etapas.count) { ctx.delete(sobrante) }
        Acciones.guardar(ctx)
        cerrar()
    }
}
