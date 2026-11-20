import SwiftUI
import SwiftData

// MARK: - Piezas comunes

/// Lugar y notas de una tarea: lo que no hay que olvidar, distinto de los pasos.
struct NotasTarea: View {
    let tarea: Tarea
    @Environment(\.paleta) private var paleta
    @Environment(\.openURL) private var abrir

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tarea.lugar.isEmpty || !tarea.direccion.isEmpty {
                Button {
                    if let url = tarea.mapa { abrir(url) }
                } label: {
                    Label(tarea.lugar.isEmpty ? tarea.direccion : tarea.lugar, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(paleta.primario.color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(tarea.mapa == nil)
            }
            if !tarea.notas.isEmpty {
                Text(tarea.notas)
                    .font(.callout)
                    .foregroundStyle(paleta.secundario.color)
                    .lineLimit(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(paleta.halo.color).frame(width: 2) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Hojas que se abren desde el fichero

/// Lo que se abre al tocar una tarjeta: la tarea en curso (cuenta y pasos), una cita (cuánto falta) o el detalle.
struct HojaTarea: View {
    let tarea: Tarea
    let paleta: Paleta
    var onTermine: (Tarea) -> Void

    @Environment(\.dismiss) private var cerrar

    var body: some View {
        Group {
            if tarea.estado == .enCurso {
                TimelineView(.periodic(from: .now, by: 1)) { linea in
                    let sigue = (tarea.finPrevisto ?? .distantFuture) > linea.date
                    EnCursoView(tarea: tarea, ahora: linea.date) {
                        let t = tarea
                        cerrar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onTermine(t) }
                    }
                    // Cuando se cumple el tiempo, la pantalla principal pregunta "¿Cómo seguimos?".
                    .onChange(of: sigue) { _, s in if !s { cerrar() } }
                }
            } else if tarea.esCita {
                TimelineView(.periodic(from: .now, by: 1)) { linea in
                    HojaCita(tarea: tarea, ahora: linea.date)
                }
            } else {
                NavigationStack { DetalleTareaView(tarea: tarea, paleta: paleta) }
            }
        }
        .environment(\.paleta, paleta)
        .foregroundStyle(paleta.texto.color)
        .tint(paleta.primario.color)
        .background(paleta.fondo.color.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

/// Una cita abierta: cuánto falta para salir o para que empiece, o cuánto queda si ya empezó; lugar y notas.
struct HojaCita: View {
    let tarea: Tarea
    let ahora: Date
    @Environment(\.paleta) private var paleta
    @Environment(\.openURL) private var abrir
    @ScaledMetric(relativeTo: .largeTitle) private var tamanoNumero: CGFloat = 46

    var body: some View {
        let t = tarea
        let fin = t.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60)
        let empezo = t.inicio <= ahora
        let objetivo = empezo ? fin : (t.salida.map { $0 > ahora ? $0 : t.inicio } ?? t.inicio)
        let leyenda = empezo ? "para que termine" : (t.salida.map { $0 > ahora } == true ? "para salir" : "para que empiece")
        LienzoCirculo {
            VStack(alignment: .leading, spacing: 0) {
                Encabezado(etiqueta: empezo ? "Cita · ahora" : "Cita", titulo: t.titulo,
                           detalle: "\(Formato.hora(t.inicio)) a \(Formato.hora(fin))")
                NotasTarea(tarea: t)
            }
        } centro: {
            CirculoQueRespira(halo: paleta.halo.mezcla(Categoria.cita.rgb, 0.4), fondo: paleta.fondo) {
                VStack(spacing: 2) {
                    let segundos = Int(objetivo.timeIntervalSince(ahora))
                    Text(Formato.cuenta(segundos)).font(.numero(segundos >= 3600 ? tamanoNumero * 0.7 : tamanoNumero)).monospacedDigit()
                    Text(leyenda).font(.footnote).foregroundStyle(paleta.secundario.color)
                }
            }
            .accessibilityElement(children: .combine)
        } abajo: {
            if let url = t.mapa {
                Button { abrir(url) } label: { Label("Abrir en Mapas", systemImage: "map") }
                    .buttonStyle(BotonPrimario(paleta: paleta))
            }
        }
    }
}

// MARK: - Decidir

/// El círculo sigue al dedo con un elástico de costado. Hacia arriba: la pantalla se va llenando de verde y al
/// llegar arriba (o al soltar pasada la mitad) empieza. Hacia abajo hasta el borde y sostener 2 s: Ahora no
/// (la pantalla se llena de salvia apagada).
struct DecidirView: View {
    let tarea: Tarea
    var onEmpiezo: () -> Void
    var onAhoraNo: () -> Void

    @Environment(\.paleta) private var paleta
    @State private var arrastre: CGSize = .zero
    @State private var rellenoArriba: Double = 0
    @State private var enBorde = false
    @State private var sostenDesde: Date?
    @State private var trabajo: DispatchWorkItem?
    @State private var decidido = false
    @State private var golpe = 0
    @AppStorage("vecesDecidir") private var veces = 0

    private let distanciaPosponer: CGFloat = 170
    private let elastico: CGFloat = 60
    /// Decirle "Ahora no" a la importante en modo firme cuesta más: 4 s en vez de 2.
    private var segundosSosten: Double { tarea.importante && Perfil.actual.firme ? 4 : 2 }

    var body: some View {
        GeometryReader { geo in
            let alto = geo.size.height
            let centro = CGPoint(x: geo.size.width / 2, y: alto * Medidas.alturaCentro)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: sostenDesde == nil)) { linea in
                let sosten = sostenDesde.map { min(1, linea.date.timeIntervalSince($0) / segundosSosten) } ?? 0
                let bajada = Double(min(1, max(0, arrastre.height / distanciaPosponer)))
                let rellenoNo = enBorde ? sosten : 0
                let relleno = max(rellenoArriba, rellenoNo)
                let colorRelleno = rellenoNo > rellenoArriba ? paleta.ahoraNo : paleta.energia
                // Primero se pinta el círculo (el primer cuarto del gesto) y recién después el color sale a la pantalla.
                let pintado = min(1, relleno / 0.25)
                let expansion = max(0, (relleno - 0.2) / 0.8)
                let radioMax = hypot(geo.size.width, alto) * 1.15
                ZStack {
                    LienzoCirculo {
                        VStack(alignment: .leading, spacing: 0) {
                            if tarea.importante { EtiquetaImportante().padding(.bottom, 12) }
                            Encabezado(etiqueta: "Es la hora", titulo: tarea.titulo,
                                       detalle: "\(Formato.hora(tarea.inicio)) · \(Formato.minutos(tarea.duracionMinutos))")
                            if let p = tarea.proyecto { BarraProyecto(proyecto: p).padding(.top, 10) }
                            NotasTarea(tarea: tarea)
                        }
                    } centro: {
                        Color.clear.frame(width: Medidas.circulo, height: Medidas.circulo)
                    } abajo: {
                        if veces <= 5 {
                            HStack(spacing: 22) {
                                Label("deslizá: empiezo", systemImage: "chevron.up")
                                Label(segundosSosten > 2 ? "bajá y sostené 4 s: ahora no" : "bajá y sostené: ahora no", systemImage: "chevron.down")
                            }
                            .font(.footnote)
                            .foregroundStyle(paleta.secundario.color)
                            .frame(maxWidth: .infinity)
                            .opacity(1 - max(rellenoArriba, bajada))
                        }
                    }

                    // La pantalla se llena de color desde el círculo.
                    Circle()
                        .fill(colorRelleno.color)
                        .frame(width: radioMax * 2 * expansion, height: radioMax * 2 * expansion)
                        .blur(radius: 24)
                        .position(x: centro.x + arrastre.width, y: centro.y + arrastre.height)
                        .opacity(expansion > 0.001 ? 1 : 0)
                        .allowsHitTesting(false)

                    // Mientras se pinta, el halo toma el mismo color y el borde claro de adentro se apaga:
                    // lleno, ya no se nota la circunferencia.
                    CirculoQueRespira(halo: paleta.halo.mezcla(colorRelleno, pintado), fondo: paleta.fondo,
                                      intensidad: (enBorde ? 0.3 + 0.7 * sosten : bajada * 0.3) * (1 - pintado),
                                      interior: 1 - pintado) {
                        VStack(spacing: 10) {
                            Image(systemName: "chevron.up")
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(paleta.primario.color)
                        .opacity(max(0, 1 - max(pintado * 1.6, bajada)))
                        .frame(width: Medidas.circulo, height: Medidas.circulo)
                        .background(Circle().fill(colorRelleno.color).padding(-6).opacity(pintado))
                    }
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { cambio($0, alto: alto) }
                                .onEnded(fin))
                    .offset(arrastre)
                    .position(centro)
                    .accessibilityElement()
                    .accessibilityLabel("Decidir: \(tarea.titulo)")
                    .accessibilityHint("Deslizá hacia arriba para empezar, o hacia abajo y sostené para posponer.")
                    .accessibilityAction(named: "Empiezo") { onEmpiezo() }
                    .accessibilityAction(named: "Ahora no") { onAhoraNo() }

                    // Las palabras quedan fijas en el centro, en el blanco cálido de la app.
                    Text("Empiezo")
                        .font(.serif(32, relativoA: .largeTitle))
                        .foregroundStyle(Paleta.blancoCalido.color)
                        .opacity(rellenoNo > rellenoArriba ? 0 : min(1, max(0, (expansion - 0.15) / 0.3)))
                        .position(x: centro.x, y: alto * 0.46)
                        .allowsHitTesting(false)
                    Text("Ahora no")
                        .font(.serif(32, relativoA: .largeTitle))
                        .foregroundStyle(Paleta.blancoCalido.color)
                        .opacity(enBorde ? 0.5 + 0.5 * sosten : bajada * 0.5)
                        .position(x: centro.x, y: alto * 0.46)
                        .allowsHitTesting(false)
                }
            }
        }
        .sensoryFeedback(.success, trigger: golpe)
        .sensoryFeedback(.impact(weight: .light), trigger: enBorde)
        .onAppear { veces += 1 }
    }

    private func cambio(_ v: DragGesture.Value, alto: CGFloat) {
        guard !decidido else { return }
        let dx = v.translation.width
        let x = (dx < 0 ? -1 : 1) * elastico * (1 - exp(-abs(dx) / (elastico * 1.6)))
        let dy = v.translation.height
        arrastre = CGSize(width: x, height: dy)
        let recorrido = max(80, alto * 0.46 - 40)
        rellenoArriba = dy < 0 ? Double(min(1, -dy / recorrido)) : 0
        if rellenoArriba >= 1 { empezar(); return }
        let llego = dy > distanciaPosponer
        if llego && !enBorde {
            enBorde = true
            sostenDesde = .now
            let w = DispatchWorkItem { aMover() }
            trabajo = w
            DispatchQueue.main.asyncAfter(deadline: .now() + segundosSosten, execute: w)
            vibrarMientrasSostiene()
        } else if !llego && enBorde {
            enBorde = false
            sostenDesde = nil
            trabajo?.cancel()
        }
    }

    private func fin(_ v: DragGesture.Value) {
        guard !decidido else { return }
        trabajo?.cancel()
        let estabaEnBorde = enBorde
        enBorde = false
        sostenDesde = nil
        if !estabaEnBorde && rellenoArriba >= 0.55 && v.translation.height < 0 {
            empezar()
        } else {
            withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                arrastre = .zero
                rellenoArriba = 0
            }
        }
    }

    /// Mientras se sostiene "Ahora no", el iPhone vibra cada vez más fuerte.
    private func vibrarMientrasSostiene() {
        let total = segundosSosten
        Task { @MainActor in
            while enBorde && !decidido, let desde = sostenDesde {
                let p = Date.now.timeIntervalSince(desde) / total
                if p >= 1 { break }
                Haptica.sosten(p)
                try? await Task.sleep(for: .milliseconds(Int(380 - 250 * min(1, p))))
            }
        }
    }

    private func empezar() {
        guard !decidido else { return }
        decidido = true
        trabajo?.cancel()
        Haptica.empiezo()
        golpe += 1
        withAnimation(.easeOut(duration: 0.4)) { rellenoArriba = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onEmpiezo() }
    }

    private func aMover() {
        guard !decidido else { return }
        decidido = true
        Haptica.ahoraNo()
        golpe += 1
        onAhoraNo()
    }
}

// MARK: - ¿Cuándo, entonces?

/// Después de "Ahora no" o "Paro por hoy": la pregunta como protagonista y tres huecos concretos.
struct CuandoView: View {
    let tarea: Tarea
    let ahora: Date
    let otras: [Tarea]
    let sinRespuesta: Bool
    var onAgendar: (Date) -> Void
    var onArchivar: () -> Void

    @Environment(\.paleta) private var paleta
    @State private var elegida = 0
    @State private var otraFecha: Date?

    private static let otra = 99

    private var soloHoy: Bool { tarea.importante && Perfil.actual.firme }

    private var sugerencias: [Sugerencia] {
        let perfil = Perfil.actual
        let ocupados = otras.filter { $0.uid != tarea.uid && $0.ocupaAgenda }.flatMap(\.intervalosOcupados)
            + Calendario.ocupados(desde: ahora) + perfil.ocupados(desde: ahora)
        let lista: [Sugerencia]
        if tarea.apertura >= 0 && tarea.cierre > tarea.apertura {
            lista = MotorSlots.sugerencias(duracion: tarea.duracionMinutos, ocupados: ocupados, desde: ahora,
                                           apertura: tarea.apertura, cierre: tarea.cierre, soloDiasHabiles: tarea.soloDiasHabiles,
                                           cantidad: soloHoy ? 6 : 3)
        } else {
            lista = MotorSlots.sugerencias(duracion: tarea.duracionMinutos, ocupados: ocupados, desde: ahora,
                                           apertura: perfil.apertura, cierre: perfil.cierre, cantidad: soloHoy ? 6 : 3)
        }
        // La importante en modo firme: solo horas de hoy (si queda alguna).
        if soloHoy {
            let deHoy = lista.filter { Calendar.current.isDate($0.inicio, inSameDayAs: ahora) }
            return Array((deHoy.isEmpty ? lista : deHoy).prefix(3))
        }
        return lista
    }

    var body: some View {
        let lista = sugerencias
        VStack(alignment: .leading, spacing: 0) {
            if tarea.importante { EtiquetaImportante().padding(.top, 14).padding(.bottom, 4) }
            Text(tarea.titulo).font(.serif(32, relativoA: .largeTitle)).lineLimit(3).padding(.top, 12)
            Text(sinRespuesta ? "No llegaste a decidir. No pasa nada." : "Lo movemos.")
                .font(.serifItalica(19, relativoA: .title3))
                .foregroundStyle(paleta.secundario.color)
                .padding(.top, 6)
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Text("¿Cuándo, entonces?")
                    .font(.serif(22, relativoA: .title2))
                    .foregroundStyle(paleta.primario.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .padding(.bottom, soloHoy ? 0 : 8)
                if soloHoy {
                    Text("Es la importante: te propongo horas de hoy.")
                        .font(.footnote).foregroundStyle(Dorado.texto.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                }
                ForEach(Array(lista.enumerated()), id: \.offset) { i, s in
                    opcion(i, titulo: Formato.diaYHora(s.inicio, ahora: ahora), motivo: motivo(i, s)) { onAgendar(s.inicio) }
                }
                opcionOtra(lista)
                Button("Ya no la voy a hacer", action: onArchivar)
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(paleta.secundario.color)
                    .padding(.top, 4)
            }
            .padding(18)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 26))
            .overlay { if tarea.importante { RoundedRectangle(cornerRadius: 26).stroke(Dorado.borde.color, lineWidth: 1.5) } }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .onAppear { if lista.isEmpty { elegida = Self.otra } }
    }

    private func motivo(_ i: Int, _ s: Sugerencia) -> String {
        let hasta = Formato.hora(s.libreHasta)
        if Calendar.current.isDate(s.inicio, inSameDayAs: ahora) {
            return i == 0 && s.inicio.timeIntervalSince(ahora) < 45 * 60
                ? "Ahora mismo tenés libre hasta las \(hasta)."
                : "Más tarde hoy, libre hasta las \(hasta)."
        }
        return Calendar.current.component(.hour, from: s.inicio) == 8
            ? "El primer hueco de ese día, libre hasta las \(hasta)."
            : "Libre hasta las \(hasta)."
    }

    private func opcion(_ i: Int, titulo: String, motivo: String, agendar: @escaping () -> Void) -> some View {
        let sel = elegida == i
        return VStack(alignment: .leading, spacing: 8) {
            Text(titulo).font(sel ? .serif(28, relativoA: .title) : .serif(20, relativoA: .title3))
            if sel {
                Text(motivo).font(.subheadline).foregroundStyle(paleta.secundario.color)
                Button("Agendar", action: agendar).buttonStyle(BotonPrimario(paleta: paleta))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(sel ? 16 : 12)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? paleta.primario.color : paleta.linea.color, lineWidth: sel ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { elegida = i } }
    }

    private func opcionOtra(_ lista: [Sugerencia]) -> some View {
        let sel = elegida == Self.otra
        let fecha = Binding<Date>(
            get: { otraFecha ?? lista.first?.inicio ?? ahora.addingTimeInterval(3600) },
            set: { otraFecha = $0 })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Otra hora").font(sel ? .serif(28, relativoA: .title) : .serif(20, relativoA: .title3))
            if sel {
                DatePicker("Cuándo", selection: fecha, in: ahora..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(paleta.primario.color)
                Button("Agendar") { onAgendar(fecha.wrappedValue) }.buttonStyle(BotonPrimario(paleta: paleta))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(sel ? 16 : 12)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? paleta.primario.color : paleta.linea.color, lineWidth: sel ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { elegida = Self.otra } }
    }
}

// MARK: - En curso

struct EnCursoView: View {
    let tarea: Tarea
    let ahora: Date
    var onTermine: () -> Void

    @Environment(\.paleta) private var paleta
    @Environment(\.modelContext) private var ctx
    @ScaledMetric(relativeTo: .largeTitle) private var tamanoNumero: CGFloat = 46

    var body: some View {
        let fin = tarea.finPrevisto ?? ahora
        LienzoCirculo {
            Encabezado(etiqueta: "En curso", titulo: tarea.titulo,
                       detalle: "\(Formato.hora(tarea.inicioReal ?? tarea.inicio)) a \(Formato.hora(fin))")
        } centro: {
            CirculoQueRespira(halo: paleta.energia, fondo: paleta.fondo) {
                VStack(spacing: 2) {
                    Text(Formato.cuenta(Int(fin.timeIntervalSince(ahora)))).font(.numero(tamanoNumero)).monospacedDigit()
                    Text("quedan").font(.footnote).foregroundStyle(paleta.secundario.color)
                }
            }
            .accessibilityElement(children: .combine)
        } abajo: {
            VStack(spacing: 12) {
                if !tarea.pasos.isEmpty {
                    Ruleta(pasos: tarea.pasosOrdenados) { paso in
                        Haptica.tachar()
                        paso.hecho.toggle()
                        Acciones.guardar(ctx)
                    }
                }
                Button(action: onTermine) {
                    Label("Terminé", systemImage: "leaf")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(paleta.superficie.color, in: Capsule())
                        .overlay(Capsule().stroke(paleta.primario.color.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(paleta.primario.color)
            }
        }
    }
}

/// Pasos en forma de ruleta: la última tachada arriba, las siguientes debajo; deslizando se ve todo.
struct Ruleta: View {
    let pasos: [Paso]
    var alTocar: (Paso) -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(pasos, id: \.uid) { paso in
                        fila(paso)
                            .frame(height: 44)
                            .id(paso.uid)
                            .scrollTransition { contenido, fase in
                                contenido
                                    .scaleEffect(fase.isIdentity ? 1 : 0.92, anchor: .leading)
                                    .opacity(fase.isIdentity ? 1 : 0.45)
                            }
                    }
                    Color.clear.frame(height: 88)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 132)
            .mask(LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.15),
                                         .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear {
                if let ultimo = pasos.last(where: \.hecho) { proxy.scrollTo(ultimo.uid, anchor: .top) }
            }
            .onChange(of: pasos.filter(\.hecho).count) {
                if let ultimo = pasos.last(where: \.hecho) {
                    withAnimation { proxy.scrollTo(ultimo.uid, anchor: .top) }
                }
            }
        }
    }

    private func fila(_ paso: Paso) -> some View {
        let siguiente = pasos.first(where: { !$0.hecho })?.uid == paso.uid
        return Button { alTocar(paso) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(paleta.primario.color, lineWidth: 1.5)
                    if paso.hecho { Circle().fill(paleta.primario.color) }
                }
                .frame(width: 24, height: 24)
                Text(paso.texto)
                    .strikethrough(paso.hecho)
                    .foregroundStyle(paso.hecho ? paleta.secundario.color : paleta.texto.color)
                    .fontWeight(siguiente ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(paso.hecho ? "Hecho" : "Pendiente"): \(paso.texto)")
    }
}

// MARK: - Fin del slot

struct FinSlotView: View {
    let tarea: Tarea
    let ahora: Date
    let siguiente: Tarea?
    var onTermine: () -> Void
    var onExtender: (Int) -> Void
    var onCorrerYExtender: (Int, Date) -> Void
    var onParo: () -> Void

    @Environment(\.paleta) private var paleta
    @State private var choque: Int?

    private static let animos = [
        ("minutos de foco. Lo sostuviste.", "Arrancar era lo difícil, y lo hiciste."),
        ("minutos enteros. Lo hiciste.", "Cada slot cumplido le enseña a tu cabeza que arrancar se puede."),
        ("minutos en marcha. Bien ahí.", "Lo que queda ya no pesa lo mismo.")
    ]

    private var minutosReales: Int {
        guard let real = tarea.inicioReal else { return tarea.duracionMinutos }
        return max(1, Int((min(ahora, tarea.finPrevisto ?? ahora).timeIntervalSince(real) / 60).rounded()))
    }

    private var finBase: Date { max(ahora, tarea.finPrevisto ?? ahora) }

    var body: some View {
        let animo = Self.animos[abs(tarea.uid.uuidString.hashValue % Self.animos.count)]
        let hechos = tarea.pasos.filter(\.hecho).count
        VStack(spacing: 6) {
            Text("\(Formato.hora(tarea.finPrevisto ?? ahora)) · \(tarea.titulo)".uppercased())
                .font(.caption.weight(.semibold)).tracking(1)
                .foregroundStyle(paleta.secundario.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Spacer(minLength: 8)
            Recompensa(tamano: 120)
            Text("\(minutosReales) \(animo.0)")
                .font(.pregunta)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text(tarea.pasos.isEmpty ? animo.1 : "\(animo.1) \(hechos) de \(tarea.pasos.count) pasos tachados.")
                .font(.subheadline)
                .foregroundStyle(paleta.secundario.color)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text("¿Cómo seguimos?").font(.serif(20, relativoA: .title3)).foregroundStyle(paleta.primario.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                opcion("Terminé", "Se cierra y queda el tiempo real.", icono: "leaf", accion: onTermine)
                necesitoMas
                if let m = choque, let s = siguiente { avisoChoque(m, s) }
                opcion("Paro por hoy", "Te pregunto cuándo retomás.", icono: "moon.stars", accion: onParo)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func opcion(_ titulo: String, _ detalle: String, icono: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 12) {
                Image(systemName: icono).font(.title3).foregroundStyle(paleta.primario.color).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.body.weight(.semibold))
                    Text(detalle).font(.footnote).foregroundStyle(paleta.secundario.color)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
        }
        .buttonStyle(.plain)
    }

    private var necesitoMas: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock").font(.title3).foregroundStyle(paleta.primario.color).frame(width: 30)
            VStack(alignment: .leading, spacing: 8) {
                Text("Necesito más").font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    ForEach([10, 15, 30], id: \.self) { m in
                        Button("+\(m)") { pedir(m) }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(paleta.linea.color))
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
    }

    private func pedir(_ m: Int) {
        let finNuevo = finBase.addingTimeInterval(Double(m) * 60)
        if MotorSlots.choca(finNuevo: finNuevo, siguiente: siguiente) {
            withAnimation { choque = m }
        } else {
            onExtender(m)
        }
    }

    private func avisoChoque(_ m: Int, _ s: Tarea) -> some View {
        let finNuevo = finBase.addingTimeInterval(Double(m) * 60)
        let corrida = MotorSlots.redondearArriba(finNuevo, minutos: 5)
        let entra = [30, 15, 10].first { !MotorSlots.choca(finNuevo: finBase.addingTimeInterval(Double($0) * 60), siguiente: s) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Con +\(m) pisás “\(s.titulo)” de las \(Formato.hora(s.inicio)).").font(.footnote)
            HStack(spacing: 8) {
                Button("Correrlo a \(Formato.hora(corrida))") { onCorrerYExtender(m, corrida) }
                if let e = entra { Button("Mejor +\(e)") { onExtender(e) } }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(paleta.primario.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Paleta.aviso.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Paleta.aviso.color.opacity(0.4)))
    }
}

struct Recompensa: View {
    var tamano: CGFloat = 84
    @Environment(\.paleta) private var paleta
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var animar = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(paleta.energia.color, lineWidth: 1.5)
                    .scaleEffect(animar ? 1.7 : 0.4)
                    .opacity(animar ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.8).delay(Double(i) * 0.25), value: animar)
            }
            Circle().fill(paleta.energia.mezcla(paleta.fondo, 0.65).color).frame(width: tamano * 0.7, height: tamano * 0.7)
            Image(systemName: "checkmark").font(.system(size: tamano * 0.28, weight: .semibold)).foregroundStyle(paleta.primario.color)
        }
        .frame(width: tamano, height: tamano)
        .onAppear { if !reducirMovimiento { animar = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Transiciones

enum Transicion: Equatable {
    case terminada(titulo: String, minutos: Int, hoy: Int, total: Int)
    case movida
}

/// Al terminar: primero la pantalla entera en verde con un mensaje que va cambiando ("¡Bien ahí!"),
/// después unos segundos de celebración con el halo grande en verde energía y un brote que crece.
struct CelebracionView: View {
    let titulo: String
    let minutos: Int
    let hoy: Int
    let total: Int

    static let mensajes = ["¡Bien ahí!", "¡Eso!", "¡Buena, crack!", "¡Vamos!", "¡Bien metida!"]
    static let segundosMensaje = 1.6

    @Environment(\.paleta) private var paleta
    @State private var aparecer = false
    @State private var enVerde = true
    @State private var mensaje = CelebracionView.mensajes.randomElement() ?? "¡Bien ahí!"
    @State private var escalaMensaje = 0.94

    var body: some View {
        ZStack {
            celebracion
            if enVerde {
                ZStack {
                    paleta.energia.color.ignoresSafeArea()
                    Text(mensaje)
                        .font(.serif(48, relativoA: .largeTitle))
                        .foregroundStyle(Paleta.blancoCalido.color)
                        .multilineTextAlignment(.center)
                        .scaleEffect(escalaMensaje)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { escalaMensaje = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.segundosMensaje) {
                withAnimation(.easeInOut(duration: 0.6)) { enVerde = false }
                withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.3)) { aparecer = true }
            }
        }
    }

    private var celebracion: some View {
        GeometryReader { geo in
            ZStack {
                paleta.fondo.color.ignoresSafeArea()
                CirculoQueRespira(halo: paleta.energia, fondo: paleta.fondo, intensidad: 0.7) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(paleta.primario.color)
                        .scaleEffect(aparecer ? 1 : 0.2, anchor: .bottom)
                        .opacity(aparecer ? 1 : 0)
                }
                .position(x: geo.size.width / 2, y: geo.size.height * Medidas.alturaCentro)
                VStack(spacing: 8) {
                    Text("Listo.").font(.serif(44, relativoA: .largeTitle))
                    Text("\(Formato.minutos(minutos)) de foco en “\(titulo)”.")
                        .font(.body).multilineTextAlignment(.center)
                    Text("Hoy llevás \(Formato.minutos(hoy)) de foco · en total \(Formato.minutos(total))")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .opacity(aparecer ? 1 : 0)
                .frame(maxWidth: .infinity)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.17)
            }
        }
    }
}

/// "Está bien, lo movemos." (u otro texto con la misma calidez) solo y grande sobre la salvia de "Ahora no",
/// antes de preguntar cuándo.
struct MovidaView: View {
    static let mensajes = ["Está bien,\nlo movemos.", "Tranqui, buscamos\notro momento.", "No pasa nada,\nreagendamos.",
                           "Todo bien, va\npara más tarde.", "Dale,\nlo acomodamos."]

    @Environment(\.paleta) private var paleta
    @State private var aparecer = false
    @State private var mensaje = MovidaView.mensajes.randomElement() ?? "Está bien,\nlo movemos."

    var body: some View {
        ZStack {
            paleta.ahoraNo.color.ignoresSafeArea()
            Text(mensaje)
                .font(.serifItalica(40, relativoA: .largeTitle))
                .foregroundStyle(Paleta.blancoCalido.color)
                .multilineTextAlignment(.center)
                .scaleEffect(aparecer ? 1 : 0.94)
                .opacity(aparecer ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { aparecer = true } }
    }
}
