import SwiftUI
import SwiftData

// MARK: - Espera

/// Solo el próximo slot. Deslizando al costado se ven los dos siguientes; a los 6 s vuelve solo.
struct EsperaView: View {
    let tareas: [Tarea]
    let ahora: Date
    var onNueva: () -> Void
    var onAjustes: () -> Void
    var onEditar: (Tarea) -> Void
    var onBorrar: (Tarea) -> Void

    @Environment(\.paleta) private var paleta
    @State private var pagina = 0
    @ScaledMetric(relativeTo: .largeTitle) private var tamanoNumero: CGFloat = 46

    private let etiquetas = ["Lo próximo", "Después", "Más tarde"]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $pagina) {
                ForEach(Array(tareas.enumerated()), id: \.element.uid) { i, t in
                    vistaPagina(t, etiqueta: etiquetas[min(i, 2)]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            BotonesSuperiores(onNueva: onNueva, onAjustes: onAjustes)

            if tareas.count > 1 {
                HStack(spacing: 7) {
                    ForEach(tareas.indices, id: \.self) { i in
                        Circle().fill(paleta.secundario.color.opacity(i == pagina ? 0.9 : 0.3)).frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            }
        }
        .task(id: pagina) {
            guard pagina != 0 else { return }
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { withAnimation { pagina = 0 } }
        }
    }

    private func vistaPagina(_ t: Tarea, etiqueta: String) -> some View {
        LienzoCirculo {
            Encabezado(etiqueta: etiqueta, titulo: t.titulo,
                       detalle: "\(Formato.diaYHora(t.inicio, ahora: ahora)) · \(t.duracionMinutos) min")
                .padding(.trailing, 70)
        } centro: {
            CirculoQueRespira(halo: paleta.halo, fondo: paleta.fondo) {
                VStack(spacing: 2) {
                    Text("comienza en").font(.footnote).foregroundStyle(paleta.secundario.color)
                    Text(Formato.cuenta(Int(t.inicio.timeIntervalSince(ahora))))
                        .font(.numero(t.inicio.timeIntervalSince(ahora) >= 3600 ? tamanoNumero * 0.7 : tamanoNumero))
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        } abajo: {
            EmptyView()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Editar") { onEditar(t) }
            Button("Borrar", role: .destructive) { onBorrar(t) }
        }
    }
}

struct BotonesSuperiores: View {
    var onNueva: () -> Void
    var onAjustes: () -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onNueva) {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Nueva tarea")
            Button(action: onAjustes) {
                Image(systemName: "gearshape").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Ajustes")
        }
        .font(.title3)
        .foregroundStyle(paleta.primario.color)
        .padding(.trailing, 12)
    }
}

struct VacioView: View {
    var onNueva: () -> Void
    var onAjustes: () -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LienzoCirculo {
                Encabezado(etiqueta: "Lo próximo", titulo: "Nada a la vista", detalle: "Cuando agregues algo, aparece acá.")
            } centro: {
                CirculoQueRespira(halo: paleta.halo, fondo: paleta.fondo) {
                    Button(action: onNueva) {
                        Image(systemName: "plus").font(.largeTitle.weight(.light)).foregroundStyle(paleta.primario.color)
                            .frame(width: 120, height: 120)
                    }
                    .accessibilityLabel("Agregar lo próximo")
                }
            } abajo: {
                EmptyView()
            }
            BotonesSuperiores(onNueva: onNueva, onAjustes: onAjustes)
        }
    }
}

// MARK: - Decidir

/// Apretar y deslizar hacia arriba: Empiezo. Apretar y quedarse quieto 1,5 s: Ahora no.
struct DecidirView: View {
    let tarea: Tarea
    var onEmpiezo: () -> Void
    var onAhoraNo: () -> Void

    @Environment(\.paleta) private var paleta
    @State private var desplazamiento: CGFloat = 0
    @State private var progreso: CGFloat = 0
    @State private var tocando = false
    @State private var seMovio = false
    @State private var trabajo: DispatchWorkItem?
    @State private var decidido = 0
    @AppStorage("vecesDecidir") private var veces = 0

    private let distanciaEmpezar: CGFloat = 90

    private var subida: Double { Double(min(1, max(0, -desplazamiento / distanciaEmpezar))) }

    var body: some View {
        LienzoCirculo {
            Encabezado(etiqueta: "Es la hora", titulo: tarea.titulo,
                       detalle: "\(Formato.hora(tarea.inicio)) · \(tarea.duracionMinutos) min")
        } centro: {
            circulo
        } abajo: {
            if veces <= 5 {
                HStack(spacing: 22) {
                    Label("deslizá: empiezo", systemImage: "arrow.up")
                    Label("mantené: ahora no", systemImage: "circle.circle")
                }
                .font(.footnote)
                .foregroundStyle(paleta.secundario.color)
                .frame(maxWidth: .infinity)
                .opacity(1 - max(subida, Double(progreso)))
            }
        }
        .overlay(paleta.energia.color.opacity(subida * 0.3).ignoresSafeArea().allowsHitTesting(false))
        .sensoryFeedback(.success, trigger: decidido)
        .onAppear { veces += 1 }
    }

    private var circulo: some View {
        ZStack {
            CirculoQueRespira(halo: paleta.halo, fondo: paleta.fondo) {
                ZStack {
                    PuntoQueLate().opacity(1 - max(subida, Double(progreso)))
                    Text("Empiezo").font(.pregunta).foregroundStyle(paleta.primario.color).opacity(subida)
                    Text("Ahora no").font(.pregunta).foregroundStyle(paleta.secundario.color).opacity(Double(progreso))
                }
            }
            Circle()
                .trim(from: 0, to: progreso)
                .stroke(paleta.secundario.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Medidas.circulo + 12, height: Medidas.circulo + 12)
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .offset(y: desplazamiento)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(cambio)
                .onEnded(fin)
        )
        .accessibilityElement()
        .accessibilityLabel("Decidir: \(tarea.titulo)")
        .accessibilityHint("Deslizá hacia arriba para empezar o mantené apretado para posponer.")
        .accessibilityAction(named: "Empiezo", onEmpiezo)
        .accessibilityAction(named: "Ahora no", onAhoraNo)
    }

    private func cambio(_ v: DragGesture.Value) {
        if !tocando {
            tocando = true
            seMovio = false
            let w = DispatchWorkItem {
                guard !seMovio else { return }
                decidido += 1
                onAhoraNo()
            }
            trabajo = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
            withAnimation(.linear(duration: 1.28).delay(0.22)) { progreso = 1 }
        }
        if !seMovio && hypot(v.translation.width, v.translation.height) > 10 {
            seMovio = true
            trabajo?.cancel()
            sinAnimacion { progreso = 0 }
        }
        if seMovio {
            let dy = v.translation.height
            desplazamiento = dy < 0 ? dy : dy * 0.25
        }
    }

    private func fin(_ v: DragGesture.Value) {
        trabajo?.cancel()
        tocando = false
        if seMovio && v.translation.height < -distanciaEmpezar {
            decidido += 1
            withAnimation(.easeIn(duration: 0.4)) { desplazamiento = -700 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onEmpiezo() }
        } else {
            withAnimation(.spring(duration: 0.4)) { desplazamiento = 0 }
            sinAnimacion { progreso = 0 }
        }
    }

    private func sinAnimacion(_ cambio: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, cambio)
    }
}

// MARK: - ¿Cuándo, entonces?

/// Después de "Ahora no" o "Paro por hoy": tres huecos concretos, otra hora o archivar.
struct CuandoView: View {
    let tarea: Tarea
    let ahora: Date
    let otras: [Tarea]
    let calma: String
    var onAgendar: (Date) -> Void
    var onArchivar: () -> Void

    @Environment(\.paleta) private var paleta
    @State private var elegida = 0
    @State private var otraFecha: Date?

    private static let otra = 99

    private var sugerencias: [Sugerencia] {
        let ocupados = otras
            .filter { $0.uid != tarea.uid && ($0.estado == .programada || $0.estado == .enCurso) }
            .map { DateInterval(start: $0.inicioReal ?? $0.inicio, duration: Double($0.duracionMinutos + $0.minutosExtra) * 60) }
        return MotorSlots.sugerencias(duracion: tarea.duracionMinutos, ocupados: ocupados, desde: ahora)
    }

    var body: some View {
        let lista = sugerencias
        VStack(alignment: .leading, spacing: 6) {
            Text(tarea.titulo).font(.tituloTarea).lineLimit(3).padding(.top, 12)
            Text(calma).font(.system(.title3, design: .serif).italic()).foregroundStyle(paleta.primario.color)
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Text("¿Cuándo, entonces?")
                    .font(.pregunta)
                    .foregroundStyle(paleta.primario.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(titulo).font(.system(sel ? .title : .title3, design: .serif))
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
            Text("Otra hora").font(.system(sel ? .title : .title3, design: .serif))
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
    var onTerminarAntes: () -> Void

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
            VStack(spacing: 6) {
                if !tarea.pasos.isEmpty {
                    Ruleta(pasos: tarea.pasosOrdenados) { paso in
                        paso.hecho.toggle()
                        Acciones.guardar(ctx)
                    }
                }
                Button("Terminé antes", action: onTerminarAntes)
                    .font(.footnote)
                    .foregroundStyle(paleta.secundario.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        let animo = Self.animos[abs(tarea.uid.uuidString.hashValue) % Self.animos.count]
        let hechos = tarea.pasos.filter(\.hecho).count
        VStack(spacing: 6) {
            Text("\(Formato.hora(tarea.finPrevisto ?? ahora)) · \(tarea.titulo)".uppercased())
                .font(.caption.weight(.semibold)).tracking(1)
                .foregroundStyle(paleta.secundario.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Recompensa().padding(.top, 8)
            Text("\(minutosReales) \(animo.0)")
                .font(.pregunta)
                .multilineTextAlignment(.center)
            Text(tarea.pasos.isEmpty ? animo.1 : "\(animo.1) \(hechos) de \(tarea.pasos.count) pasos tachados.")
                .font(.subheadline)
                .foregroundStyle(paleta.secundario.color)
                .multilineTextAlignment(.center)
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text("¿Cómo seguimos?").font(.system(.title3, design: .serif)).foregroundStyle(paleta.primario.color)
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
    @Environment(\.paleta) private var paleta
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var animar = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(paleta.energia.color, lineWidth: 1.5)
                    .scaleEffect(animar ? 1.6 : 0.4)
                    .opacity(animar ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.8).delay(Double(i) * 0.25), value: animar)
            }
            Circle().fill(paleta.energia.mezcla(paleta.fondo, 0.65).color).frame(width: 58, height: 58)
            Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(paleta.primario.color)
        }
        .frame(width: 84, height: 84)
        .onAppear { if !reducirMovimiento { animar = true } }
        .accessibilityHidden(true)
    }
}
