import SwiftUI
import SwiftData

/// Un paso en la revisión: de dónde salió y si es una sugerencia que todavía no se sumó.
struct PasoP: Identifiable, Equatable {
    let id = UUID()
    var texto: String
    /// "voz" (lo dictaste), "ia" (sugerido) o "" (escrito a mano).
    var origen: String
    var grande = false
    var sugerido = false
}

/// Lo que la IA propone para un ítem dictado, en una versión editable antes de guardar.
struct Propuesta: Identifiable, Equatable {
    struct EtapaP: Equatable { var titulo: String; var fecha: Date }
    struct TareaP: Equatable { var titulo: String; var duracion: Int }

    let id = UUID()
    var tipo: String
    var alternativa: String
    var titulo: String
    var tituloCorto: String
    var area: String
    var texto: String
    var fecha: Date?
    var horaPropuesta = false
    var duracion: Int
    var lugar: String
    var direccion: String
    var medioViaje = "transit"
    var notas: String
    var pasos: [PasoP]
    var renglones: [String]
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
        tituloCorto = ia.titulo_corto
        area = ia.area
        texto = ia.texto_original
        fecha = FechasIA.fechaHora(ia.fecha_hora)
        duracion = ia.duracion_min > 0 ? ia.duracion_min : 30
        lugar = ia.lugar
        direccion = ia.direccion
        notas = ia.notas
        // Si dictó pasos, los sugeridos de la IA quedan para confirmar; si no dictó ninguno, los propuestos ya cuentan.
        let dicto = ia.pasos.contains(where: \.dicho)
        pasos = ia.pasos.map { PasoP(texto: $0.texto, origen: $0.dicho ? "voz" : "ia", grande: $0.grande, sugerido: dicto && !$0.dicho) }
        renglones = ia.renglones
        tema = ia.tema
        apertura = ia.horario_apertura
        cierre = ia.horario_cierre
        habiles = ia.solo_dias_habiles
        // Las etapas se reparten desde hoy hasta el último día (el que dijo, o lo que suman las etapas).
        let cal = Calendar.current
        let hoy = cal.startOfDay(for: .now)
        let pesos = ia.etapas.map { max(0.05, $0.dias) }
        var ultimo = FechasIA.dia(ia.deadline).map { cal.startOfDay(for: $0) }
        if ultimo == nil && ia.tipo == "proyecto" {
            let dias = max(7, Int(pesos.reduce(0, +).rounded(.up)))
            ultimo = cal.date(byAdding: .day, value: dias - 1, to: hoy)
        }
        deadline = ultimo
        if let u = ultimo, !pesos.isEmpty, let fin = cal.date(byAdding: .day, value: 1, to: max(u, hoy)) {
            let fines = Plan.repartir(inicio: hoy, fin: fin, pesos: pesos)
            etapas = zip(ia.etapas, fines).map { EtapaP(titulo: $0.titulo, fecha: $1) }
        } else {
            etapas = []
        }
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
        let perfil = Perfil.actual
        return MotorSlots.sugerencias(duracion: duracion, ocupados: ocupados, desde: desde,
                                      apertura: perfil.apertura, cierre: perfil.cierre, cantidad: 1).first?.inicio
    }

    /// Convierte lo que devolvió la IA en propuestas editables; a las tareas sin hora les sugiere un hueco libre.
    static func propuestas(_ items: [PropuestaIA], tareas: [Tarea]) -> [Propuesta] {
        let ocupado = ocupados(tareas)
        return items.map { ia in
            var p = Propuesta(ia: ia)
            if p.tipo == "tarea" && p.fecha == nil, let hueco = huecos(duracion: p.duracion, desde: .now, ocupados: ocupado, p: p) {
                p.fecha = hueco
                p.horaPropuesta = true
            }
            return p
        }
    }

    /// Busca en Mapas los lugares y direcciones que se dictaron y los corrige con el nombre y la dirección reales
    /// (solo si el resultado está cerca de donde estás o de tu ciudad).
    static func corregirLugares(_ propuestas: [Propuesta]) async -> [Propuesta] {
        var r = propuestas
        for i in r.indices where r[i].tipo == "tarea" || r[i].tipo == "cita" {
            let consulta = (r[i].direccion.isEmpty ? r[i].lugar : r[i].direccion).trimmingCharacters(in: .whitespaces)
            guard consulta.count >= 3, let item = await Viaje.shared.buscarCerca(consulta) else { continue }
            let direccion = Viaje.direccion(de: item)
            if !direccion.isEmpty { r[i].direccion = direccion }
            if !r[i].lugar.isEmpty, let nombre = item.name, !nombre.isEmpty { r[i].lugar = nombre }
        }
        return r
    }

    /// Lo ocupado: lo agendado, los otros calendarios y los horarios fijos (trabajo, deporte…).
    static func ocupados(_ tareas: [Tarea]) -> [DateInterval] {
        tareas.filter(\.ocupaAgenda).flatMap(\.intervalosOcupados) + Calendario.ocupados() + Perfil.actual.ocupados()
    }

    static func guardar(_ propuestas: [Propuesta], ctx: ModelContext, tareas: [Tarea], audio: String = "") {
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
                t.tituloCorto = p.tituloCorto
                t.area = p.area
                t.lugar = p.lugar
                t.direccion = p.direccion
                t.medioViaje = p.medioViaje
                t.notas = p.notas
                if p.tieneHorario { t.apertura = p.apertura; t.cierre = p.cierre; t.soloDiasHabiles = p.habiles }
                // Las sugerencias que no se sumaron no se guardan.
                for (i, paso) in p.pasos.filter({ !$0.sugerido && !$0.texto.trimmingCharacters(in: .whitespaces).isEmpty }).enumerated() {
                    let nuevo = Paso(texto: paso.texto, orden: i, origen: paso.origen)
                    ctx.insert(nuevo)
                    nuevo.tarea = t
                }
            case "proyecto":
                let cal = Calendar.current
                let inicio = cal.startOfDay(for: .now)
                let ultimo = cal.startOfDay(for: p.deadline ?? .now.addingTimeInterval(29 * 86_400))
                let fin = cal.date(byAdding: .day, value: 1, to: max(ultimo, inicio)) ?? ultimo
                let proyecto = Proyecto(titulo: p.titulo, deadline: fin)
                proyecto.fechaInicio = inicio
                proyecto.notas = p.notas
                ctx.insert(proyecto)
                // Si se cambió la fecha final en la revisión, las etapas se acomodan en proporción.
                let duraciones = Plan.duraciones(inicio: inicio, fines: p.etapas.map(\.fecha))
                let fines = Plan.repartir(inicio: inicio, fin: fin, pesos: duraciones.map { max(1, $0) })
                var primera: Etapa?
                for (i, e) in p.etapas.enumerated() {
                    let etapa = Etapa(titulo: e.titulo, fechaObjetivo: fines.indices.contains(i) ? fines[i] : fin, orden: i)
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
                    t.area = p.area
                    if let inicio { desde = inicio.addingTimeInterval(Double(tp.duracion) * 60) }
                }
            case "idea", "lista":
                let c = Captura(tipo: p.tipo, texto: p.texto.isEmpty ? p.titulo : p.texto, titulo: p.titulo, tema: p.tema)
                c.audio = audio
                ctx.insert(c)
                for (i, t) in (p.tipo == "lista" ? p.pasos.map(\.texto) : p.renglones).enumerated() {
                    let r = Renglon(texto: t, orden: i, origen: "voz")
                    ctx.insert(r)
                    r.captura = c
                }
            default:
                let c = Captura(tipo: "inbox", texto: p.texto.isEmpty ? p.titulo : p.texto, titulo: p.titulo)
                c.audio = audio
                ctx.insert(c)
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

// MARK: - Dictado en la pantalla principal

/// Dictar desde el círculo de la pantalla principal: un toque y escucha; "Listo" (o tocar de nuevo) y se ordena.
/// La captura se guarda al instante en el Inbox; si la IA responde, se reemplaza por lo que propone.
@Observable
@MainActor
final class CapturaInicio {
    let dictado = Dictado()
    var pensando = false
    var propuestas: [Propuesta] = DatosDemo.pantalla == "captura" ? CapturaView.ejemplo : []
    var revisando = DatosDemo.pantalla == "captura"
    var escribiendo = false
    var aviso: String?
    /// Lo que se dijo, para mostrarlo arriba de la revisión.
    var dicho = DatosDemo.pantalla == "captura" ? CapturaView.dichoEjemplo : ""
    /// El audio del último dictado (para ideas e inbox).
    var audio = ""
    @ObservationIgnored private var vigilancia: Task<Void, Never>?

    /// Segundos de silencio después de los que se da por terminado el dictado.
    static let silencioParaTerminar: TimeInterval = 3

    func tocar(ctx: ModelContext) {
        guard !pensando else { return }
        if dictado.escuchando || dictado.reintentando {
            terminar(ctx: ctx)
        } else {
            dictado.texto = ""
            dictado.textoAleman = ""
            dictado.error = nil
            Haptica.dictado()
            Task { await dictado.empezar() }
            vigilar(ctx)
        }
    }

    func terminar(ctx: ModelContext) {
        vigilancia?.cancel()
        vigilancia = nil
        dictado.detener()
        let texto = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let aleman = dictado.textoAleman
        dictado.texto = ""
        dictado.textoAleman = ""
        guard !texto.isEmpty else { return }
        Haptica.dictado()
        audio = dictado.ultimoAudio
        procesar(texto, aleman: aleman, ctx: ctx)
    }

    /// Se da cuenta de que dejaste de hablar (3 s sin voz ni texto nuevo) y se pone a pensar solo.
    /// Si el reconocimiento se corta por su cuenta, también procesa lo que llegó a escuchar.
    private func vigilar(_ ctx: ModelContext) {
        vigilancia?.cancel()
        vigilancia = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                let hayTexto = !self.dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // Mientras se reintenta (se cortó al empezar), sigue esperando.
                if !self.dictado.escuchando && !self.dictado.reintentando {
                    if hayTexto { self.terminar(ctx: ctx) }
                    return
                }
                if hayTexto && Date.now.timeIntervalSince(self.dictado.ultimaVoz) >= CapturaInicio.silencioParaTerminar {
                    self.terminar(ctx: ctx)
                    return
                }
            }
        }
    }

    func procesar(_ texto: String, aleman: String = "", ctx: ModelContext) {
        dicho = texto
        let respaldo = Captura(tipo: "inbox", texto: texto)
        respaldo.audio = audio
        ctx.insert(respaldo)
        Acciones.guardar(ctx)
        guard ClaveIA.hay else {
            aviso = "Quedó guardado en el cajón, en el Inbox. Para que se ordene solo, cargá tu clave en Ajustes → Inteligencia artificial."
            return
        }
        pensando = true
        Task {
            do {
                let items = try await ClienteClaude.clasificar(texto, aleman: aleman)
                let tareas = (try? ctx.fetch(FetchDescriptor<Tarea>())) ?? []
                propuestas = await Guardado.corregirLugares(Guardado.propuestas(items, tareas: tareas))
                ctx.delete(respaldo)
                Acciones.guardar(ctx)
                pensando = false
                if propuestas.isEmpty { aviso = "No encontré nada para guardar. Quedó en el cajón por las dudas." } else { revisando = true }
            } catch {
                pensando = false
                aviso = "\(error.localizedDescription)\n\nNo se perdió nada: quedó guardado en el cajón."
            }
        }
    }
}

/// Colores de lo sugerido (las estrellitas).
extension Paleta {
    static let ia = RGB(0xB08A3E)
    static let iaFondo = RGB(0xF5ECD9)
    static let iaTexto = RGB(0x6A5730)
}

/// Lo que se entendió del dictado, para revisar y cambiar antes de guardar.
struct RevisionView: View {
    @Binding var propuestas: [Propuesta]
    let paleta: Paleta
    var dicho: String = ""
    var audio: String = ""
    var onListo: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query private var tareas: [Tarea]
    @State private var dichoAbierto = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !dicho.isEmpty {
                        Text("RECIÉN DICTASTE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color)
                    }
                    Text("Revisá antes de guardar").font(.serif(26, relativoA: .title))
                    if !dicho.isEmpty { loDicho }
                    if propuestas.count > 1 {
                        Text("Entendí \(propuestas.count) cosas. Nada se guarda hasta que toques Guardar.")
                            .font(.subheadline).foregroundStyle(paleta.secundario.color)
                    }
                    ForEach($propuestas) { $p in
                        TarjetaPropuesta(p: $p, paleta: paleta, ocupados: Guardado.ocupados(tareas)) {
                            propuestas.removeAll { $0.id == p.id }
                        }
                    }
                }
                .padding(20)
            }
            Button(propuestas.isEmpty ? "Cerrar" : "Guardar") {
                if !propuestas.isEmpty { Guardado.guardar(propuestas, ctx: ctx, tareas: tareas, audio: audio) }
                propuestas = []
                onListo()
            }
            .buttonStyle(BotonPrimario(paleta: paleta))
            .padding(20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
    }

    /// Lo que dijiste, en dos renglones; al tocarlo se lee entero.
    private var loDicho: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { dichoAbierto.toggle() } } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(paleta.primario.color)
                    .frame(width: 32, height: 32)
                    .background(paleta.primario.color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("“\(dicho)”")
                        .font(.serifItalica(15, relativoA: .subheadline))
                        .foregroundStyle(paleta.secundario.color)
                        .lineLimit(dichoAbierto ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Text(dichoAbierto ? "Mostrar menos" : "Ver todo lo que dijiste")
                        .font(.caption.weight(.semibold)).foregroundStyle(paleta.primario.color)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Escribir en vez de dictar

/// Escribir (o dictar) lo que hay en la cabeza; la IA lo separa y clasifica, y el usuario revisa antes de guardar.
/// Se abre manteniendo apretado el círculo de la pantalla principal.
struct CapturaView: View {
    let paleta: Paleta
    var onCargarAMano: (Categoria) -> Void

    enum Estado: Equatable { case captura, procesando, revision, aviso(String) }

    @Environment(\.dismiss) private var cerrar
    @Environment(\.modelContext) private var ctx
    @Query private var tareas: [Tarea]
    @State private var dictado = Dictado()
    @State private var eligiendoTipo = false
    @FocusState private var escribiendo: Bool
    @State private var estado: Estado = .captura
    @State private var propuestas: [Propuesta] = []
    @State private var dicho = ""

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
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { escribiendo = true } }
        .confirmationDialog("¿Qué querés cargar?", isPresented: $eligiendoTipo, titleVisibility: .visible) {
            ForEach([Categoria.tarea, .cita, .proyecto, .idea]) { c in
                Button(c.nombre) {
                    cerrar()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onCargarAMano(c) }
                }
            }
        }
    }

    private var vistaCaptura: some View {
        VStack(spacing: 18) {
            Text("Contame en qué estás")
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
                .focused($escribiendo)
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
            Button("Cargar a mano, con todos los campos") { dictado.detener(); eligiendoTipo = true }
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
        RevisionView(propuestas: $propuestas, paleta: paleta, dicho: dicho) { cerrar() }
    }

    /// La captura se guarda al instante en el Inbox; si la IA responde, se reemplaza por lo clasificado.
    private func procesar() {
        let texto = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        dictado.detener()
        dicho = texto
        let aleman = dictado.textoAleman
        let respaldo = Captura(tipo: "inbox", texto: texto)
        ctx.insert(respaldo)
        Acciones.guardar(ctx)
        guard ClaveIA.hay else {
            estado = .aviso("Quedó guardado en el cajón, en el Inbox. Para que se ordene solo, cargá tu clave en Ajustes → Inteligencia artificial.")
            return
        }
        estado = .procesando
        Task {
            do {
                let items = try await ClienteClaude.clasificar(texto, aleman: aleman)
                propuestas = await Guardado.corregirLugares(Guardado.propuestas(items, tareas: tareas))
                ctx.delete(respaldo)
                Acciones.guardar(ctx)
                estado = propuestas.isEmpty ? .aviso("No encontré nada para guardar. Quedó en el cajón por las dudas.") : .revision
            } catch {
                estado = .aviso("\(error.localizedDescription)\n\nNo se perdió nada: quedó guardado en el cajón.")
            }
        }
    }

    static let dichoEjemplo = "Mañana a las diez llamar al banco por lo de la tarjeta. Antes buscar el número de cliente, que está en un mail viejo, y anotar lo que me digan así no tengo que volver a llamar. Ah, y el jueves dentista a las once."

    static var ejemplo: [Propuesta] {
        let base = PropuestaIA(tipo: "tarea", alternativa: "ninguna", titulo: "Llamar al banco", titulo_corto: "", area: "Trámites y papeles",
                               texto_original: "llamar al banco mañana", fecha_hora: "", duracion_min: 30, lugar: "Banco", direccion: "", notas: "",
                               pasos: [.init(texto: "Buscar el número de cliente", dicho: true, grande: false),
                                       .init(texto: "Preparar los papeles", dicho: true, grande: true),
                                       .init(texto: "Tener a mano el último resumen", dicho: false, grande: false),
                                       .init(texto: "Anotar lo que te digan", dicho: true, grande: false)],
                               renglones: [], tema: "", horario_apertura: 9, horario_cierre: 16, solo_dias_habiles: true, deadline: "", etapas: [], tareas_primera_etapa: [])
        var banco = Propuesta(ia: base)
        banco.fecha = Date.now.addingTimeInterval(20 * 3600)
        var cita = Propuesta(ia: base)
        cita.tipo = "cita"; cita.titulo = "Dentista"; cita.pasos = []; cita.lugar = "Consultorio"; cita.apertura = -1
        cita.fecha = Date.now.addingTimeInterval(44 * 3600); cita.duracion = 45
        return [banco, cita]
    }
}

// MARK: - Una propuesta

/// Qué dato de la tarea se está cambiando.
enum DatoEditable: String, Identifiable {
    case dia, hora, dura, lugar
    var id: String { rawValue }
}

struct TarjetaPropuesta: View {
    @Binding var p: Propuesta
    let paleta: Paleta
    let ocupados: [DateInterval]
    var onDescartar: () -> Void

    @FocusState private var tituloEnfocado: Bool
    @State private var tituloArmado: String?
    @State private var rearmando = false
    @State private var editando: DatoEditable?
    @State private var escribiendoPaso = false
    @State private var nuevoPaso = ""
    @State private var partiendo: UUID?
    @State private var sugiriendo = false
    @State private var avisoPasos: String?
    @FocusState private var pasoEnfocado: Bool

    private var esAgenda: Bool { p.tipo == "tarea" || p.tipo == "cita" }
    private var categoria: Categoria { p.tipo == "cita" ? .cita : (p.tipo == "proyecto" ? .proyecto : (p.tipo == "idea" ? .idea : (p.tipo == "inbox" ? .inbox : .tarea))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectorTipo
            if p.alternativa != "ninguna" {
                HStack(spacing: 6) {
                    Text("¿Es \(Propuesta.nombre(p.tipo).lowercased()) o \(Propuesta.nombre(p.alternativa).lowercased())?")
                        .font(.footnote).foregroundStyle(Paleta.aviso.color)
                    Button("Es \(Propuesta.nombre(p.alternativa).lowercased())") { p.tipo = p.alternativa; p.alternativa = "ninguna" }
                        .font(.footnote.weight(.semibold))
                }
            }
            if esAgenda {
                encabezado
                datos
                if p.tieneHorario {
                    Label("Horario del lugar: \(p.apertura) a \(p.cierre) h\(p.habiles ? ", días hábiles" : "")", systemImage: "clock")
                        .font(.caption).foregroundStyle(paleta.secundario.color)
                }
                pasos
            } else {
                TextField("Título", text: $p.titulo, axis: .vertical)
                    .font(.serif(20, relativoA: .title3))
                    .focused($tituloEnfocado)
                    .onAppear { if tituloArmado == nil { tituloArmado = p.titulo } }
                    .onChange(of: tituloEnfocado) { _, enfocado in
                        // Si le cambiás el nombre a un proyecto, las etapas se vuelven a armar para que correspondan.
                        if !enfocado && p.tipo == "proyecto" && p.titulo != tituloArmado && ClaveIA.hay && !rearmando {
                            Task { await rearmarEtapas() }
                        }
                    }
                if p.tipo == "proyecto" { proyecto }
                if p.tipo == "idea" { TextField("Tema", text: $p.tema).font(.subheadline) }
            }
            if !p.notas.isEmpty {
                TextField("Notas", text: $p.notas, axis: .vertical).font(.footnote)
            }
        }
        .padding(16)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(paleta.linea.color))
        .sheet(item: $editando) { d in
            EditorDato(dato: d, p: $p, ocupados: ocupados)
                .environment(\.paleta, paleta)
                .presentationDetents(d == .dia ? [.large] : [.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var selectorTipo: some View {
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
    }

    /// El título sobre el color de la categoría, liso.
    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(categoria.nombre.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.white.opacity(0.85))
            TextField("Título", text: $p.titulo, axis: .vertical)
                .font(.serif(23, relativoA: .title2))
                .foregroundStyle(.white)
                .tint(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(categoria.rgb.mezcla(RGB(0x2C2A25), 0.08).color, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Cuándo, hora, duración y lugar: grandes y a mano, para corroborar o cambiar de un toque.
    private var datos: some View {
        let cal = Calendar.current
        let dia: (String, String) = {
            guard let f = p.fecha else { return ("Elegir", "sin día todavía") }
            let nombre = f.formatted(.dateTime.weekday(.wide).day().locale(Locale(identifier: "es")))
            if cal.isDateInToday(f) { return ("Hoy", nombre) }
            if cal.isDateInTomorrow(f) { return ("Mañana", nombre) }
            return (Formato.primeraMayuscula(nombre), f.formatted(.dateTime.month(.wide).locale(Locale(identifier: "es"))))
        }()
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            TarjetaDato(icono: "calendar", rotulo: "Cuándo", valor: dia.0, detalle: dia.1) { editando = .dia }
            TarjetaDato(icono: "clock", rotulo: "Hora", valor: p.fecha.map { Formato.hora($0) } ?? "—",
                        detalle: p.horaPropuesta ? "propuesta" : (p.fecha == nil ? "falta" : "lo dijiste")) { editando = .hora }
            TarjetaDato(icono: "hourglass", rotulo: "Dura", valor: Formato.minutos(p.duracion), detalle: "estimado") { editando = .dura }
            TarjetaDato(icono: "mappin.and.ellipse", rotulo: "Dónde", valor: p.lugar.isEmpty ? "—" : p.lugar,
                        detalle: p.lugar.isEmpty ? "sin lugar" : (p.tipo == "cita" ? (p.medioViaje == "auto" ? "en auto" : "en transporte") : "")) { editando = .lugar }
        }
    }

    // MARK: Pasos

    private var pasos: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pasos").font(.serif(16, relativoA: .headline))
                Spacer()
                if !p.pasos.isEmpty {
                    HStack(spacing: 10) {
                        Label("dijiste", systemImage: "waveform")
                        Label("sugerido", systemImage: "sparkle")
                    }
                    .font(.caption2)
                    .foregroundStyle(paleta.secundario.color)
                    .labelStyle(EtiquetaChica())
                }
            }
            .padding(.top, 6)
            ListaReordenable(items: p.pasos, espacio: 4, movible: { _ in true },
                             alMover: { desde, hasta in
                                 let paso = p.pasos.remove(at: desde)
                                 p.pasos.insert(paso, at: hasta)
                             }) { paso, manija in
                filaPaso(paso, manija: manija)
            }
            HStack(spacing: 6) {
                Button { withAnimation { escribiendoPaso.toggle() }; if escribiendoPaso { pasoEnfocado = true } } label: {
                    Text("+ Escribir un paso").frame(maxWidth: .infinity).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .foregroundStyle(paleta.primario.color)
                Button { Task { await sugerirUno() } } label: {
                    Group {
                        if sugiriendo { ProgressView() } else { Label("Sugerime uno", systemImage: "sparkle") }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Paleta.iaFondo.color, in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(Paleta.iaTexto.color)
                .disabled(!ClaveIA.hay || sugiriendo)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            if escribiendoPaso {
                HStack(spacing: 8) {
                    TextField("Escribí un paso", text: $nuevoPaso)
                        .focused($pasoEnfocado)
                        .submitLabel(.next)
                        .onSubmit(sumarEscrito)
                        .padding(10)
                        .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 12))
                    if !nuevoPaso.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Sumar", action: sumarEscrito).font(.subheadline.weight(.semibold))
                    }
                }
            }
            if let a = avisoPasos { Text(a).font(.caption).foregroundStyle(paleta.secundario.color) }
        }
    }

    private func filaPaso(_ paso: PasoP, manija: Manija) -> some View {
        let i = p.pasos.firstIndex { $0.id == paso.id } ?? 0
        let ia = paso.origen == "ia"
        return HStack(spacing: 6) {
            manija.frame(width: 26)
            Text("\(i + 1)")
                .font(.caption2.weight(.bold))
                .frame(width: 19, height: 19)
                .foregroundStyle(ia ? Paleta.ia.color : paleta.primario.color)
                .background((ia ? Paleta.ia.color : paleta.primario.color).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                if paso.sugerido {
                    Text(paso.texto).font(.subheadline).foregroundStyle(Paleta.iaTexto.color)
                } else if p.pasos.indices.contains(i) {
                    TextField("Paso", text: $p.pasos[i].texto, axis: .vertical).font(.subheadline)
                }
                if paso.grande && !paso.sugerido {
                    Button { Task { await partir(paso) } } label: {
                        if partiendo == paso.id { ProgressView().controlSize(.mini) } else {
                            Label("Parece grande · Partir", systemImage: "sparkle")
                                .font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .overlay(Capsule().stroke(Paleta.ia.color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        }
                    }
                    .foregroundStyle(Paleta.ia.color)
                    .buttonStyle(.plain)
                    .disabled(!ClaveIA.hay || partiendo != nil)
                }
            }
            Spacer(minLength: 2)
            Image(systemName: ia ? "sparkle" : (paso.origen == "voz" ? "waveform" : "pencil"))
                .font(.caption)
                .foregroundStyle(ia ? Paleta.ia.color : paleta.primario.color)
                .accessibilityLabel(ia ? "Sugerido" : (paso.origen == "voz" ? "Lo dijiste" : "Escrito"))
            if paso.sugerido {
                Button("Sumar") { if p.pasos.indices.contains(i) { withAnimation { p.pasos[i].sugerido = false } } }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Paleta.ia.color, in: Capsule())
                    .buttonStyle(.plain)
            }
            Button { withAnimation { p.pasos.removeAll { $0.id == paso.id } } } label: {
                Image(systemName: "xmark").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(paleta.secundario.color)
            .buttonStyle(.plain)
            .accessibilityLabel("Quitar paso")
        }
        .padding(.vertical, 5).padding(.trailing, 8)
        .background(paso.sugerido ? Paleta.iaFondo.color : paleta.fondo.color, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sumarEscrito() {
        let t = nuevoPaso.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { escribiendoPaso = false; return }
        withAnimation { p.pasos.append(PasoP(texto: t, origen: "")) }
        nuevoPaso = ""
        pasoEnfocado = true
    }

    private func partir(_ paso: PasoP) async {
        partiendo = paso.id
        defer { partiendo = nil }
        do {
            let partes = try await ClienteClaude.partirPaso(tarea: p.titulo, paso: paso.texto, pasos: p.pasos.map(\.texto))
            guard !partes.isEmpty, let i = p.pasos.firstIndex(where: { $0.id == paso.id }) else { return }
            withAnimation {
                p.pasos.remove(at: i)
                p.pasos.insert(contentsOf: partes.map { PasoP(texto: $0, origen: "ia", sugerido: true) }, at: i)
            }
            avisoPasos = "Entraron como sugeridos: confirmalos con Sumar o sacalos con la cruz."
        } catch {
            avisoPasos = error.localizedDescription
        }
    }

    private func sugerirUno() async {
        sugiriendo = true
        defer { sugiriendo = false }
        do {
            let r = try await ClienteClaude.otroPaso(tarea: p.titulo, pasos: p.pasos.map(\.texto))
            let texto = r.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !texto.isEmpty else { avisoPasos = "No se me ocurre otro paso que tenga sentido para esta tarea."; return }
            let donde = min(max(0, r.despuesDe), p.pasos.count)
            withAnimation { p.pasos.insert(PasoP(texto: texto, origen: "ia", sugerido: true), at: donde) }
            avisoPasos = nil
        } catch {
            avisoPasos = error.localizedDescription
        }
    }

    // MARK: Proyecto

    @ViewBuilder
    private var proyecto: some View {
        DatePicker("Fecha final", selection: Binding(get: { p.deadline ?? .now.addingTimeInterval(30 * 86_400) }, set: { p.deadline = $0 }),
                   displayedComponents: .date)
            .font(.subheadline)
        if rearmando {
            HStack(spacing: 8) {
                ProgressView()
                Text("Rearmando las etapas con el nombre nuevo…").font(.footnote).foregroundStyle(paleta.secundario.color)
            }
        } else if !p.etapas.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("ETAPAS").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(paleta.secundario.color)
                ForEach(Array(p.etapas.enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(e.titulo).font(.footnote)
                        Spacer()
                        Text(Formato.diaCorto(e.fecha.addingTimeInterval(-60)))
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

    private func rearmarEtapas() async {
        rearmando = true
        tituloArmado = p.titulo
        defer { rearmando = false }
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: .now)
        let ultimo = cal.startOfDay(for: p.deadline ?? .now.addingTimeInterval(30 * 86_400))
        guard let plan = try? await ClienteClaude.armarEtapas(titulo: p.titulo, notas: p.texto, inicio: inicio, fin: max(inicio, ultimo)) else { return }
        let fin = cal.date(byAdding: .day, value: 1, to: max(inicio, ultimo)) ?? ultimo
        let fines = Plan.repartir(inicio: inicio, fin: fin, pesos: plan.etapas.map { max(0.05, $0.dias) })
        p.etapas = zip(plan.etapas, fines).map { Propuesta.EtapaP(titulo: $0.titulo, fecha: $1) }
        p.tareasEtapa = plan.tareas_primera_etapa.map { Propuesta.TareaP(titulo: $0.titulo, duracion: max(10, $0.duracion_min)) }
    }
}

/// Ícono y texto chicos, juntos.
struct EtiquetaChica: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// Una de las cuatro tarjetas de datos: rótulo chico, valor grande y un detalle.
struct TarjetaDato: View {
    let icono: String
    let rotulo: String
    let valor: String
    let detalle: String
    var accion: () -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(rotulo.uppercased(), systemImage: icono)
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(paleta.secundario.color)
                        .labelStyle(EtiquetaChica())
                    Text(valor).font(.serif(21, relativoA: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detalle).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rotulo): \(valor), \(detalle)")
    }
}

/// La hoja para cambiar un dato de la propuesta.
struct EditorDato: View {
    let dato: DatoEditable
    @Binding var p: Propuesta
    let ocupados: [DateInterval]
    @Environment(\.paleta) private var paleta
    @Environment(\.dismiss) private var cerrar

    private let duraciones = [10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        let fecha = Binding<Date>(
            get: { p.fecha ?? Guardado.huecos(duracion: p.duracion, desde: .now, ocupados: ocupados, p: p) ?? .now.addingTimeInterval(3600) },
            set: { p.fecha = $0; p.horaPropuesta = false })
        VStack(alignment: .leading, spacing: 14) {
            Text(titulo).font(.serif(24, relativoA: .title2)).padding(.top, 18)
            switch dato {
            case .dia:
                DatePicker("Día", selection: fecha, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
            case .hora:
                DatePicker("Hora", selection: fecha, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            case .dura:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                    ForEach(Array(Set(duraciones + [p.duracion])).sorted(), id: \.self) { m in
                        Button(Formato.minutos(m)) { p.duracion = m; cerrar() }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(p.duracion == m ? paleta.fondo.color : paleta.texto.color)
                            .background(p.duracion == m ? paleta.primario.color : paleta.superficie.color, in: RoundedRectangle(cornerRadius: 12))
                            .buttonStyle(.plain)
                    }
                }
            case .lugar:
                CampoLugar(lugar: $p.lugar, direccion: $p.direccion)
                    .padding(12)
                    .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                if p.tipo == "cita" {
                    Picker("Cómo vas", selection: $p.medioViaje) {
                        Text("Transporte público").tag("transit")
                        Text("Auto").tag("auto")
                    }
                    .pickerStyle(.segmented)
                }
            }
            Spacer(minLength: 0)
            if dato != .dura {
                Button("Listo") {
                    if p.fecha == nil && (dato == .dia || dato == .hora) { p.fecha = fecha.wrappedValue }
                    cerrar()
                }
                .buttonStyle(BotonPrimario(paleta: paleta))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(paleta.fondo.color.ignoresSafeArea())
        .tint(paleta.primario.color)
    }

    private var titulo: String {
        switch dato {
        case .dia: "¿Qué día?"
        case .hora: "¿A qué hora?"
        case .dura: "¿Cuánto dura?"
        case .lugar: "¿Dónde?"
        }
    }
}
