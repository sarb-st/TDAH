import SwiftUI
import SwiftData

/// Lo que la IA propone para un ítem dictado, en una versión editable antes de guardar.
struct Propuesta: Identifiable, Equatable {
    struct EtapaP: Equatable { var titulo: String; var fecha: Date }
    struct TareaP: Equatable { var titulo: String; var duracion: Int }

    let id = UUID()
    var tipo: String
    var alternativa: String
    var titulo: String
    var texto: String
    var fecha: Date?
    var horaPropuesta = false
    var duracion: Int
    var lugar: String
    var direccion: String
    var notas: String
    var pasos: [String]
    var tema: String
    var apertura: Int
    var cierre: Int
    var habiles: Bool
    var deadline: Date?
    var etapas: [EtapaP]
    var tareasEtapa: [TareaP]

    init(ia: PropuestaIA) {
        tipo = ia.tipo
        alternativa = ia.alternativa
        titulo = ia.titulo
        texto = ia.texto_original
        fecha = FechasIA.fechaHora(ia.fecha_hora)
        duracion = ia.duracion_min > 0 ? ia.duracion_min : 30
        lugar = ia.lugar
        direccion = ia.direccion
        notas = ia.notas
        pasos = ia.pasos
        tema = ia.tema
        apertura = ia.horario_apertura
        cierre = ia.horario_cierre
        habiles = ia.solo_dias_habiles
        deadline = FechasIA.dia(ia.deadline)
        etapas = ia.etapas.compactMap { e in FechasIA.dia(e.fecha).map { EtapaP(titulo: e.titulo, fecha: $0) } }
        tareasEtapa = ia.tareas_primera_etapa.map { TareaP(titulo: $0.titulo, duracion: max(10, $0.duracion_min)) }
    }

    var tieneHorario: Bool { apertura >= 0 && cierre > apertura }

    static let tipos: [(String, String)] = [("tarea", "Tarea"), ("cita", "Cita"), ("proyecto", "Proyecto"), ("idea", "Idea"), ("inbox", "Inbox")]
    static func nombre(_ tipo: String) -> String { tipos.first { $0.0 == tipo }?.1 ?? tipo.capitalized }
}

/// Guarda las propuestas revisadas: tareas, citas, proyectos, ideas e inbox.
@MainActor
enum Guardado {
    static func huecos(duracion: Int, desde: Date, ocupados: [DateInterval], p: Propuesta? = nil) -> Date? {
        if let p, p.tieneHorario {
            return MotorSlots.sugerencias(duracion: duracion, ocupados: ocupados, desde: desde, apertura: p.apertura,
                                          cierre: p.cierre, soloDiasHabiles: p.habiles, cantidad: 1).first?.inicio
        }
        return MotorSlots.sugerencias(duracion: duracion, ocupados: ocupados, desde: desde, cantidad: 1).first?.inicio
    }

    static func ocupados(_ tareas: [Tarea]) -> [DateInterval] {
        tareas.filter(\.ocupaAgenda).map(\.intervalo) + Calendario.ocupados()
    }

    static func guardar(_ propuestas: [Propuesta], ctx: ModelContext, tareas: [Tarea]) {
        var ocupado = ocupados(tareas)
        var nuevas: [Tarea] = []

        func crearTarea(_ titulo: String, inicio: Date?, duracion: Int) -> Tarea {
            let t = Tarea(titulo: titulo, inicio: inicio ?? .now, duracionMinutos: max(5, duracion))
            t.estado = inicio == nil ? .faltaHora : .programada
            ctx.insert(t)
            if let inicio { ocupado.append(DateInterval(start: inicio, duration: Double(duracion) * 60)) }
            nuevas.append(t)
            return t
        }

        for p in propuestas {
            switch p.tipo {
            case "tarea", "cita":
                let t = crearTarea(p.titulo, inicio: p.fecha, duracion: p.duracion)
                t.esCita = p.tipo == "cita"
                t.lugar = p.lugar
                t.direccion = p.direccion
                t.notas = p.notas
                if p.tieneHorario { t.apertura = p.apertura; t.cierre = p.cierre; t.soloDiasHabiles = p.habiles }
                for (i, texto) in p.pasos.enumerated() {
                    let paso = Paso(texto: texto, orden: i)
                    ctx.insert(paso)
                    paso.tarea = t
                }
            case "proyecto":
                let proyecto = Proyecto(titulo: p.titulo, deadline: p.deadline ?? .now.addingTimeInterval(30 * 86_400))
                proyecto.notas = p.notas
                ctx.insert(proyecto)
                var primera: Etapa?
                for (i, e) in p.etapas.enumerated() {
                    let etapa = Etapa(titulo: e.titulo, fechaObjetivo: e.fecha, orden: i)
                    ctx.insert(etapa)
                    etapa.proyecto = proyecto
                    if i == 0 { primera = etapa }
                }
                // Las tareas de la primera etapa se agendan solas en huecos libres; se pueden mover después.
                var desde = Date.now
                for tp in p.tareasEtapa {
                    let inicio = huecos(duracion: tp.duracion, desde: desde, ocupados: ocupado)
                    let t = crearTarea(tp.titulo, inicio: inicio, duracion: tp.duracion)
                    t.proyecto = proyecto
                    t.etapa = primera
                    if let inicio { desde = inicio.addingTimeInterval(Double(tp.duracion) * 60) }
                }
            case "idea":
                ctx.insert(Captura(tipo: "idea", texto: p.texto.isEmpty ? p.titulo : p.texto, titulo: p.titulo, tema: p.tema))
            default:
                ctx.insert(Captura(tipo: "inbox", texto: p.texto.isEmpty ? p.titulo : p.texto, titulo: p.titulo))
            }
        }
        Acciones.guardar(ctx)
        for t in nuevas where t.estado == .programada {
            Avisos.programarInicio(t)
            Calendario.sincronizar(t)
        }
        Acciones.guardar(ctx)
        Avisos.pedirPermiso()
        Registro.anotar("Captura guardada: \(propuestas.count) ítems.")
    }
}

// MARK: - Pantalla de captura

/// Dictar (o escribir) lo que hay en la cabeza; Claude lo separa y clasifica, y el usuario revisa antes de guardar.
struct CapturaView: View {
    let paleta: Paleta
    var onEscribirAMano: () -> Void

    enum Estado: Equatable { case captura, procesando, revision, aviso(String) }

    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var ctx
    @Query private var tareas: [Tarea]
    @State private var dictado = Dictado()
    @State private var estado: Estado = DatosDemo.pantalla == "captura" ? .revision : .captura
    @State private var propuestas: [Propuesta] = DatosDemo.pantalla == "captura" ? CapturaView.ejemplo : []

    var body: some View {
        NavigationStack {
            Group {
                switch estado {
                case .captura: vistaCaptura
                case .procesando: vistaProcesando
                case .revision: vistaRevision
                case .aviso(let texto): vistaAviso(texto)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paleta.fondo.color.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dictado.detener(); cerrar() } }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
        .onDisappear { dictado.detener() }
    }

    private var vistaCaptura: some View {
        VStack(spacing: 18) {
            Text("¿Qué tenés en la cabeza?")
                .font(.serif(30, relativoA: .largeTitle))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            CirculoQueRespira(halo: dictado.escuchando ? paleta.energia : paleta.halo, fondo: paleta.fondo,
                              diametro: 140, intensidad: dictado.escuchando ? 0.45 : 0) {
                Button { dictado.alternar() } label: {
                    Image(systemName: dictado.escuchando ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(paleta.primario.color)
                        .frame(width: 120, height: 120)
                }
                .accessibilityLabel(dictado.escuchando ? "Dejar de escuchar" : "Dictar")
            }
            .padding(.vertical, 40)
            Text(dictado.escuchando ? "Te escucho… podés decir varias cosas juntas." : "Tocá el círculo y hablá, o escribí abajo.")
                .font(.subheadline).foregroundStyle(paleta.secundario.color)
            TextField("Llamar al banco mañana, el jueves dentista a las 10, idea para el portfolio…", text: $dictado.texto, axis: .vertical)
                .lineLimit(3...8)
                .padding(14)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
            if let error = dictado.error {
                Text(error).font(.footnote).foregroundStyle(Paleta.aviso.color)
            }
            Spacer(minLength: 0)
            Button("Listo", action: procesar)
                .buttonStyle(BotonPrimario(paleta: paleta))
                .disabled(dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cargar una tarea a mano") { dictado.detener(); cerrar(); onEscribirAMano() }
                .font(.subheadline)
                .foregroundStyle(paleta.secundario.color)
        }
        .padding(20)
    }

    private var vistaProcesando: some View {
        VStack(spacing: 30) {
            CirculoQueRespira(halo: paleta.halo, fondo: paleta.fondo, diametro: 120) { ProgressView() }
            Text("Ordenando lo que dijiste…").font(.serif(22, relativoA: .title3))
        }
    }

    private func vistaAviso(_ texto: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40)).foregroundStyle(paleta.primario.color)
            Text(texto).multilineTextAlignment(.center)
            Button("Cerrar") { cerrar() }.buttonStyle(BotonPrimario(paleta: paleta)).padding(.top, 10)
        }
        .padding(30)
    }

    private var vistaRevision: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(propuestas.count == 1 ? "Entendí esto" : "Entendí \(propuestas.count) cosas")
                        .font(.serif(28, relativoA: .title))
                    Text("Revisá y cambiá lo que quieras. Nada se guarda hasta que toques Guardar.")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    ForEach($propuestas) { $p in
                        TarjetaPropuesta(p: $p, paleta: paleta, ocupados: Guardado.ocupados(tareas)) {
                            propuestas.removeAll { $0.id == p.id }
                        }
                    }
                }
                .padding(20)
            }
            Button(propuestas.isEmpty ? "Cerrar" : "Guardar todo") {
                if !propuestas.isEmpty { Guardado.guardar(propuestas, ctx: ctx, tareas: tareas) }
                cerrar()
            }
            .buttonStyle(BotonPrimario(paleta: paleta))
            .padding(20)
        }
    }

    /// La captura se guarda al instante en el Inbox; si la IA responde, se reemplaza por lo clasificado.
    private func procesar() {
        let texto = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        dictado.detener()
        let respaldo = Captura(tipo: "inbox", texto: texto)
        ctx.insert(respaldo)
        Acciones.guardar(ctx)
        guard ClaveIA.hay else {
            estado = .aviso("Quedó guardado en el Inbox. Para que Claude lo ordene solo, cargá tu clave en Ajustes → Inteligencia artificial.")
            return
        }
        estado = .procesando
        Task {
            do {
                let items = try await ClienteClaude.clasificar(texto)
                let ocupado = Guardado.ocupados(tareas)
                propuestas = items.map { ia in
                    var p = Propuesta(ia: ia)
                    if p.tipo == "tarea" && p.fecha == nil, let hueco = Guardado.huecos(duracion: p.duracion, desde: .now, ocupados: ocupado, p: p) {
                        p.fecha = hueco
                        p.horaPropuesta = true
                    }
                    return p
                }
                ctx.delete(respaldo)
                Acciones.guardar(ctx)
                estado = propuestas.isEmpty ? .aviso("No encontré nada para guardar. Quedó en el Inbox por las dudas.") : .revision
            } catch {
                estado = .aviso("\(error.localizedDescription)\n\nNo se perdió nada: quedó guardado en el Inbox.")
            }
        }
    }

    static var ejemplo: [Propuesta] {
        let base = PropuestaIA(tipo: "tarea", alternativa: "ninguna", titulo: "Llamar al banco", texto_original: "llamar al banco mañana",
                               fecha_hora: "", duracion_min: 20, lugar: "", direccion: "", notas: "", pasos: ["Buscar el número de cliente", "Llamar"],
                               tema: "", horario_apertura: 9, horario_cierre: 16, solo_dias_habiles: true, deadline: "", etapas: [], tareas_primera_etapa: [])
        var banco = Propuesta(ia: base)
        banco.fecha = Date.now.addingTimeInterval(20 * 3600)
        banco.horaPropuesta = true
        var cita = Propuesta(ia: base)
        cita.tipo = "cita"; cita.titulo = "Dentista"; cita.pasos = []; cita.lugar = "Consultorio"; cita.apertura = -1
        cita.fecha = Date.now.addingTimeInterval(44 * 3600); cita.duracion = 45
        var idea = Propuesta(ia: base)
        idea.tipo = "idea"; idea.alternativa = "tarea"; idea.titulo = "Lámpara que respira"; idea.tema = "diseño"; idea.pasos = []; idea.apertura = -1
        return [banco, cita, idea]
    }
}

struct TarjetaPropuesta: View {
    @Binding var p: Propuesta
    let paleta: Paleta
    let ocupados: [DateInterval]
    var onDescartar: () -> Void

    private let duraciones = [10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Propuesta.tipos, id: \.0) { tipo, nombre in
                            Button(nombre) { p.tipo = tipo; p.alternativa = "ninguna" }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(p.tipo == tipo ? paleta.fondo.color : paleta.primario.color)
                                .background(p.tipo == tipo ? paleta.primario.color : paleta.halo.color.opacity(0.3), in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
                Button(action: onDescartar) { Image(systemName: "xmark").font(.footnote) }
                    .foregroundStyle(paleta.secundario.color)
                    .accessibilityLabel("Descartar")
            }
            if p.alternativa != "ninguna" {
                HStack(spacing: 6) {
                    Text("¿Es \(Propuesta.nombre(p.tipo).lowercased()) o \(Propuesta.nombre(p.alternativa).lowercased())?")
                        .font(.footnote).foregroundStyle(Paleta.aviso.color)
                    Button("Es \(Propuesta.nombre(p.alternativa).lowercased())") { p.tipo = p.alternativa; p.alternativa = "ninguna" }
                        .font(.footnote.weight(.semibold))
                }
            }
            TextField("Título", text: $p.titulo, axis: .vertical).font(.serif(20, relativoA: .title3))

            if p.tipo == "tarea" || p.tipo == "cita" {
                if let fecha = p.fecha {
                    DatePicker(p.horaPropuesta ? "Propuesta" : "Cuándo",
                               selection: Binding(get: { fecha }, set: { p.fecha = $0; p.horaPropuesta = false }))
                        .font(.subheadline)
                } else {
                    HStack {
                        Text("Sin hora todavía").font(.subheadline).foregroundStyle(paleta.secundario.color)
                        Spacer()
                        Button("Elegir hora") {
                            p.fecha = Guardado.huecos(duracion: p.duracion, desde: .now, ocupados: ocupados, p: p) ?? .now.addingTimeInterval(3600)
                        }
                        .font(.subheadline)
                    }
                }
                Picker("Duración", selection: $p.duracion) {
                    ForEach(Array(Set(duraciones + [p.duracion])).sorted(), id: \.self) { Text("\($0) min").tag($0) }
                }
                .font(.subheadline)
                if p.tieneHorario {
                    Label("Horario del lugar: \(p.apertura) a \(p.cierre) h\(p.habiles ? ", días hábiles" : "")", systemImage: "clock")
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                }
                if !p.lugar.isEmpty || p.tipo == "cita" {
                    TextField("Lugar", text: $p.lugar).font(.subheadline)
                }
                if !p.pasos.isEmpty {
                    Text(p.pasos.map { "· \($0)" }.joined(separator: "\n")).font(.footnote).foregroundStyle(paleta.secundario.color)
                }
            }
            if p.tipo == "proyecto" {
                DatePicker("Fecha final", selection: Binding(get: { p.deadline ?? .now.addingTimeInterval(30 * 86_400) }, set: { p.deadline = $0 }),
                           displayedComponents: .date)
                    .font(.subheadline)
                if !p.etapas.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ETAPAS").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(paleta.secundario.color)
                        ForEach(Array(p.etapas.enumerated()), id: \.offset) { _, e in
                            HStack {
                                Text(e.titulo).font(.footnote)
                                Spacer()
                                Text(e.fecha.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es"))))
                                    .font(.footnote).foregroundStyle(paleta.secundario.color)
                            }
                        }
                    }
                }
                if !p.tareasEtapa.isEmpty {
                    Text("Primeras tareas (se agendan en huecos libres): " + p.tareasEtapa.map(\.titulo).joined(separator: ", "))
                        .font(.footnote).foregroundStyle(paleta.secundario.color)
                }
            }
            if p.tipo == "idea" {
                TextField("Tema", text: $p.tema).font(.subheadline)
            }
            if !p.notas.isEmpty {
                TextField("Notas", text: $p.notas, axis: .vertical).font(.footnote)
            }
        }
        .padding(16)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.linea.color))
    }
}
