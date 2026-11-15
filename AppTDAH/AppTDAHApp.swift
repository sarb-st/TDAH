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
            return try ModelContainer(for: Tarea.self, Paso.self, SlotRegistro.self, Proyecto.self, Etapa.self, Captura.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: enMemoria))
        } catch {
            Registro.anotar("No se pudo abrir la base de datos: \(error.localizedDescription)")
            return try! ModelContainer(for: Tarea.self, Paso.self, SlotRegistro.self, Proyecto.self, Etapa.self, Captura.self,
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

    @State private var cargarAMano: Categoria?
    @State private var captura = CapturaInicio()
    @State private var ajustes = DatosDemo.pantalla == "ajustes"
    @State private var proyectoDemo = DatosDemo.pantalla == "proyecto"
    @Query private var proyectos: [Proyecto]
    @State private var lista = DatosDemo.pantalla == "lista" || DatosDemo.pantalla == "proyectos"
    @State private var calendario = DatosDemo.pantalla == "calendario"
    @State private var cajon = DatosDemo.pantalla == "cajon"
    @State private var abierta: Tarea?
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
            try? await Task.sleep(for: .seconds(t == .movida ? 1.8 : 3.2 + CelebracionView.segundosMensaje))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.6)) { transicion = nil } }
        }
        .sheet(item: $cargarAMano) { c in CargarAMano(categoria: c).environment(\.paleta, paleta) }
        .sheet(isPresented: $captura.escribiendo) { CapturaView(paleta: paleta) { cargarAMano = $0 } }
        .sheet(isPresented: $captura.revisando) {
            RevisionView(propuestas: $captura.propuestas, paleta: paleta) { captura.revisando = false }
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $ajustes) { AjustesView() }
        .sheet(isPresented: $lista) { ListaView(paleta: paleta, pestanaInicial: DatosDemo.pantalla == "proyectos" ? .proyectos : .hoy) }
        .sheet(isPresented: $calendario) { CalendarioView(paleta: paleta) }
        .sheet(isPresented: $cajon) { CajonView(paleta: paleta) }
        .sheet(item: $abierta) { t in HojaTarea(tarea: t, paleta: paleta) { terminar($0) } }
        .alert(captura.aviso ?? "", isPresented: Binding(get: { captura.aviso != nil }, set: { if !$0 { captura.aviso = nil } })) {
            Button("Listo", role: .cancel) {}
        }
        .sheet(isPresented: $proyectoDemo) {
            NavigationStack { if let p = proyectos.first { ProyectoDetalleView(proyecto: p, paleta: paleta) } }
                .environment(\.paleta, paleta)
        }
        .onChange(of: fase) { _, nueva in
            if nueva == .background {
                captura.dictado.detener()
                CopiaSeguridad.guardar(ctx)
            }
            if nueva == .active && DatosDemo.pantalla == nil {
                Alarmas.detenerSonando()
                Acciones.mantenimiento(ctx: ctx)
                Salidas.recalcular(ctx)
            }
        }
        .task {
            guard DatosDemo.pantalla == nil else { return }
            Firma.programarAviso()
            Alarmas.detenerSonando()
            Alarmas.cancelarTodas()
            Acciones.mantenimiento(ctx: ctx)
            Salidas.recalcular(ctx)
        }
    }

    private var navegacion: Navegacion {
        Navegacion(ajustes: { ajustes = true }, lista: { lista = true }, calendario: { calendario = true }, cajon: { cajon = true })
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
        // Aparece de golpe (sin fundido) para que no se vea nada de lo que viene debajo.
        var sinAnimar = Transaction()
        sinAnimar.disablesAnimations = true
        withTransaction(sinAnimar) {
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
            InicioView(tareas: [], ahora: ahora, navegacion: navegacion, captura: captura) { abierta = $0 }
        case .espera(let lista):
            InicioView(tareas: lista, ahora: ahora, navegacion: navegacion, captura: captura) { abierta = $0 }
        case .enCurso(let t):
            // Con algo en curso, la pantalla principal sigue siendo Inicio (se puede capturar);
            // la tarea es la primera tarjeta y al tocarla se ven la cuenta y los pasos.
            InicioView(tareas: [t] + MotorSlots.proximas(tareas, ahora: ahora, cantidad: 2), ahora: ahora,
                       navegacion: navegacion, captura: captura) { abierta = $0 }
        case .decidir(let t):
            DecidirView(tarea: t,
                        onEmpiezo: { Acciones.empezar(t, ctx: ctx) },
                        onAhoraNo: {
                            var sinAnimar = Transaction()
                            sinAnimar.disablesAnimations = true
                            withTransaction(sinAnimar) { transicion = .movida }
                            Acciones.ahoraNo(t, ctx: ctx)
                        })
                .id(t.uid)
        case .cuando(let t, let sinRespuesta):
            CuandoView(tarea: t, ahora: ahora, otras: tareas, sinRespuesta: sinRespuesta,
                       onAgendar: { Acciones.reprogramar(t, a: $0, ctx: ctx) },
                       onArchivar: { Acciones.archivar(t, ctx: ctx) })
                .id(t.uid)
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
                            var sinAnimar = Transaction()
                            sinAnimar.disablesAnimations = true
                            withTransaction(sinAnimar) { transicion = .movida }
                            Acciones.pararPorHoy(t, ctx: ctx)
                        })
                .id(t.uid)
        }
    }
}
