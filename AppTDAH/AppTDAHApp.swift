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
    @AppStorage("apariencia") private var apariencia = Apariencia.automatico.rawValue

    @State private var creando = false
    @State private var editando: Tarea?
    @State private var ajustes = DatosDemo.pantalla == "ajustes"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { linea in
            let ahora = linea.date
            let paleta = Paleta.para(Apariencia(rawValue: apariencia) ?? .automatico,
                                     hora: DatosDemo.hora ?? Paleta.hora(de: ahora))
            pantalla(ahora: ahora)
                .environment(\.paleta, paleta)
                .foregroundStyle(paleta.texto.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(paleta.fondo.color.ignoresSafeArea())
                .preferredColorScheme(paleta.esOscura ? .dark : .light)
        }
        .sheet(isPresented: $creando) { NuevaTareaView(tarea: nil) }
        .sheet(item: $editando) { NuevaTareaView(tarea: $0) }
        .sheet(isPresented: $ajustes) { AjustesView() }
        .onChange(of: fase) { _, nueva in
            if nueva == .background { CopiaSeguridad.guardar(ctx) }
        }
        .task {
            guard DatosDemo.pantalla == nil else { return }
            Firma.programarAviso()
        }
    }

    @ViewBuilder
    private func pantalla(ahora: Date) -> some View {
        switch MotorSlots.pantalla(tareas, ahora: ahora) {
        case .vacio:
            VacioView(onNueva: { creando = true }, onAjustes: { ajustes = true })
        case .espera(let lista):
            EsperaView(tareas: lista, ahora: ahora,
                       onNueva: { creando = true }, onAjustes: { ajustes = true },
                       onEditar: { editando = $0 }, onBorrar: { Acciones.borrar($0, ctx: ctx) })
        case .decidir(let t):
            DecidirView(tarea: t,
                        onEmpiezo: { Acciones.empezar(t, ctx: ctx) },
                        onAhoraNo: { Acciones.ahoraNo(t, ctx: ctx) })
                .id(t.uid)
        case .cuando(let t, let sinRespuesta):
            CuandoView(tarea: t, ahora: ahora, otras: tareas,
                       calma: sinRespuesta ? "No llegaste a decidir. Lo movemos." : "Está bien, lo movemos.",
                       onAgendar: { Acciones.reprogramar(t, a: $0, ctx: ctx) },
                       onArchivar: { Acciones.archivar(t, ctx: ctx) })
                .id(t.uid)
        case .enCurso(let t):
            EnCursoView(tarea: t, ahora: ahora, onTerminarAntes: { Acciones.terminarAntes(t, ctx: ctx) })
        case .fin(let t):
            FinSlotView(tarea: t, ahora: ahora,
                        siguiente: MotorSlots.siguiente(despuesDe: ahora, en: tareas),
                        onTermine: { Acciones.terminar(t, ctx: ctx) },
                        onExtender: { Acciones.extender(t, minutos: $0, ctx: ctx) },
                        onCorrerYExtender: { minutos, fecha in
                            if let s = MotorSlots.siguiente(despuesDe: ahora, en: tareas) { Acciones.correr(s, a: fecha, ctx: ctx) }
                            Acciones.extender(t, minutos: minutos, ctx: ctx)
                        },
                        onParo: { Acciones.pararPorHoy(t, ctx: ctx) })
                .id(t.uid)
        }
    }
}
