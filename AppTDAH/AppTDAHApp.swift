import SwiftUI
import SwiftData

@main
struct AppTDAHApp: App {
    init() {
        Tipografia.registrar()
    }

    let contenedor: ModelContainer = {
        let enMemoria = DatosDemo.pantalla != nil
        do {
            return try ModelContainer(for: Tarea.self, Paso.self, SlotRegistro.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: enMemoria))
        } catch {
            Registro.anotar("No se pudo abrir la base de datos: \(error.localizedDescription)")
            return try! ModelContainer(for: Tarea.self, Paso.self, SlotRegistro.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()

    var body: some Scene {
        WindowGroup {
            RaizView()
                .onAppear {
                    Registro.anotar("App abierta (\(BuildInfo.commit ?? "local")).")
                    DatosDemo.cargar(en: contenedor.mainContext)
                }
        }
        .modelContainer(contenedor)
    }
}

/// Decide qué pantalla mostrar cada segundo: lo pendiente de resolver primero, si no, lo próximo.
struct RaizView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var fase
    @Query(sort: \Tarea.inicio) private var tareas: [Tarea]
    @Query private var registros: [SlotRegistro]
    @AppStorage("apariencia") private var apariencia = Apariencia.automatico.rawValue

    @State private var creando = false
    @State private var ajustes = DatosDemo.pantalla == "ajustes"
    @State private var lista = DatosDemo.pantalla == "lista"
    @State private var calendario = DatosDemo.pantalla == "calendario"
    @State private var transicion: Transicion? = RaizView.transicionDemo

    private static var transicionDemo: Transicion? {
        switch DatosDemo.pantalla {
        case "celebracion": .terminada(titulo: "Llamar al banco", minutos: 45, hoy: 80, total: 312)
        case "movida": .movida
        default: nil
        }
    }

    private var paleta: Paleta {
        Paleta.para(Apariencia(rawValue: apariencia) ?? .automatico, hora: DatosDemo.hora ?? Paleta.hora(de: .now))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { linea in
            let ahora = linea.date
            let paleta = Paleta.para(Apariencia(rawValue: apariencia) ?? .automatico,
                                     hora: DatosDemo.hora ?? Paleta.hora(de: ahora))
            ZStack {
                pantalla(ahora: ahora)
                if let t = transicion {
                    vistaTransicion(t)
                        .transition(.opacity)
                        .zIndex(1)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.5)) { transicion = nil } }
                }
            }
            .environment(\.paleta, paleta)
            .foregroundStyle(paleta.texto.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paleta.fondo.color.ignoresSafeArea())
            .preferredColorScheme(paleta.esOscura ? .dark : .light)
        }
        .task(id: transicion) {
            guard let t = transicion, DatosDemo.pantalla == nil else { return }
            try? await Task.sleep(for: .seconds(t == .movida ? 1.8 : 3.2))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.6)) { transicion = nil } }
        }
        .sheet(isPresented: $creando) { NuevaTareaView(tarea: nil) }
        .sheet(isPresented: $ajustes) { AjustesView() }
        .sheet(isPresented: $lista) { ListaView(paleta: paleta) }
        .sheet(isPresented: $calendario) { CalendarioView(paleta: paleta) }
        .onChange(of: fase) { _, nueva in
            if nueva == .background { CopiaSeguridad.guardar(ctx) }
        }
        .task {
            guard DatosDemo.pantalla == nil else { return }
            Firma.programarAviso()
        }
    }

    private var navegacion: Navegacion {
        Navegacion(nueva: { creando = true }, ajustes: { ajustes = true },
                   lista: { lista = true }, calendario: { calendario = true })
    }

    @ViewBuilder
    private func vistaTransicion(_ t: Transicion) -> some View {
        switch t {
        case .terminada(let titulo, let minutos, let hoy, let total):
            CelebracionView(titulo: titulo, minutos: minutos, hoy: hoy, total: total)
        case .movida:
            MovidaView()
        }
    }

    /// Minutos de foco de hoy y de siempre, sumando el slot que se acaba de cerrar.
    private func celebrar(_ t: Tarea, minutos: Int) {
        let conFoco = registros.filter { MotorSlots.resultadosConFoco.contains($0.resultado) }
        let hoy = conFoco.filter { Calendar.current.isDateInToday($0.fin ?? .distantPast) }.map(\.minutosReales).reduce(0, +)
        let total = conFoco.map(\.minutosReales).reduce(0, +)
        // El registro recién creado puede no estar todavía en la consulta.
        let incluido = conFoco.contains { $0.uidTarea == t.uid && ($0.fin ?? .distantPast) > Date.now.addingTimeInterval(-5) }
        let extra = incluido ? 0 : minutos
        withAnimation(.easeInOut(duration: 0.5)) {
            transicion = .terminada(titulo: t.titulo, minutos: minutos, hoy: hoy + extra, total: total + extra)
        }
    }

    private func terminar(_ t: Tarea) {
        let minutos = Acciones.terminar(t, ctx: ctx)
        celebrar(t, minutos: minutos)
    }

    @ViewBuilder
    private func pantalla(ahora: Date) -> some View {
        switch MotorSlots.pantalla(tareas, ahora: ahora) {
        case .vacio:
            VacioView(navegacion: navegacion)
        case .espera(let lista):
            EsperaView(tareas: lista, ahora: ahora, navegacion: navegacion)
        case .decidir(let t):
            DecidirView(tarea: t,
                        onEmpiezo: { Acciones.empezar(t, ctx: ctx) },
                        onAhoraNo: {
                            withAnimation(.easeInOut(duration: 0.4)) { transicion = .movida }
                            Acciones.ahoraNo(t, ctx: ctx)
                        })
                .id(t.uid)
        case .cuando(let t, let sinRespuesta):
            CuandoView(tarea: t, ahora: ahora, otras: tareas, sinRespuesta: sinRespuesta,
                       onAgendar: { Acciones.reprogramar(t, a: $0, ctx: ctx) },
                       onArchivar: { Acciones.archivar(t, ctx: ctx) })
                .id(t.uid)
        case .enCurso(let t):
            EnCursoView(tarea: t, ahora: ahora, onTermine: { terminar(t) })
        case .fin(let t):
            FinSlotView(tarea: t, ahora: ahora,
                        siguiente: MotorSlots.siguiente(despuesDe: ahora, en: tareas),
                        onTermine: { terminar(t) },
                        onExtender: { Acciones.extender(t, minutos: $0, ctx: ctx) },
                        onCorrerYExtender: { minutos, fecha in
                            if let s = MotorSlots.siguiente(despuesDe: ahora, en: tareas) { Acciones.correr(s, a: fecha, ctx: ctx) }
                            Acciones.extender(t, minutos: minutos, ctx: ctx)
                        },
                        onParo: {
                            withAnimation(.easeInOut(duration: 0.4)) { transicion = .movida }
                            Acciones.pararPorHoy(t, ctx: ctx)
                        })
                .id(t.uid)
        }
    }
}
