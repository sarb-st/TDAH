import SwiftUI
import SwiftData
import UserNotifications

/// El ritual de la noche: a las 20 llega el aviso y, si no se abre, espera esa noche al abrir la app.
/// Los domingos empieza por "¿Qué te toca esta semana?".
enum Ritual {
    static let clave = "preparadoPara"

    static func clave(de dia: Date) -> String { Perfil.claveSemana(Calendar.current.startOfDay(for: dia)) }

    static var manana: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now }

    /// Si toca mostrarlo ahora: de 20 a 3:59, si todavía no se preparó el día siguiente.
    static func toca(ahora: Date = .now) -> Bool {
        let h = Calendar.current.component(.hour, from: ahora)
        guard h >= 20 || h < 4 else { return false }
        let dia = h < 4 ? Calendar.current.startOfDay(for: ahora) : manana
        return UserDefaults.standard.string(forKey: clave) != clave(de: dia)
    }

    static func listo() {
        let h = Calendar.current.component(.hour, from: .now)
        let dia = h < 4 ? Calendar.current.startOfDay(for: .now) : manana
        UserDefaults.standard.set(clave(de: dia), forKey: clave)
    }

    /// El día que se prepara (de madrugada, el mismo día).
    static var dia: Date {
        Calendar.current.component(.hour, from: .now) < 4 ? Calendar.current.startOfDay(for: .now) : manana
    }
}

/// Un renglón de la línea del día.
private struct Evento: Identifiable {
    let id = UUID()
    let hora: Date
    let titulo: String
    let detalle: String
    let color: RGB
    var salida = false
    var fijo = false
    var objetivo: String?
}

/// Preparar mañana en pasos cortos: el día de un vistazo, qué dejar listo, la importante y el cierre con el brote.
struct PrepararMananaView: View {
    let paleta: Paleta
    var alCerrar: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query(sort: \Tarea.inicio) private var tareas: [Tarea]
    @PerfilVivo private var perfil
    @State private var paso = 0
    @State private var elegida: UUID?
    @State private var mover: Date?
    @State private var cargando = false

    private var esDomingo: Bool { Perfil.indiceDia(.now) == 6 && Calendar.current.component(.hour, from: .now) >= 4 }
    private var dia: Date { Ritual.dia }
    private var cal: Calendar { Calendar.current }

    private var delDia: [Tarea] {
        tareas.filter { $0.ocupaAgenda && cal.isDate($0.inicio, inSameDayAs: dia) }.sorted { ($0.salida ?? $0.inicio) < ($1.salida ?? $1.inicio) }
    }

    private var pasos: [Int] { esDomingo ? [9, 0, 1, 2, 3] : [0, 1, 2, 3] }

    var body: some View {
        let actual = pasos[min(paso, pasos.count - 1)]
        VStack(spacing: 0) {
            if actual != 3 {
                HStack {
                    HStack(spacing: 5) {
                        ForEach(0..<(pasos.count - 1), id: \.self) { i in
                            Capsule().fill(i <= paso ? paleta.primario.color : paleta.linea.color).frame(width: 18, height: 4)
                        }
                        Text("\(paso + 1) de \(pasos.count - 1)").font(.caption).foregroundStyle(paleta.secundario.color).padding(.leading, 4)
                    }
                    Spacer()
                    Button("Después") { alCerrar() }.font(.subheadline).foregroundStyle(paleta.secundario.color)
                }
                .padding(.horizontal, 20).padding(.top, 14)
            }
            Group {
                switch actual {
                case 9: EstaSemanaView(paleta: paleta) { siguiente() }
                case 0: pasoDia
                case 1: pasoListo
                case 2: pasoImportante
                default: cierre
                }
            }
            .transition(.opacity)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .foregroundStyle(paleta.texto.color)
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
        .sheet(isPresented: $cargando) { NuevaTareaView(tarea: nil).environment(\.paleta, paleta) }
        .onAppear { elegida = delDia.first(where: \.importante)?.uid }
    }

    private func siguiente() { withAnimation(.easeInOut(duration: 0.35)) { paso += 1 } }

    private var nombreDia: String {
        Formato.primeraMayuscula(dia.formatted(.dateTime.weekday(.wide).day().locale(Locale(identifier: "es"))))
    }

    // MARK: 1. El día de un vistazo

    private var eventos: [Evento] {
        var r: [Evento] = []
        for t in delDia {
            if t.esCita, let s = t.salida {
                r.append(Evento(hora: s, titulo: "Salí para \(t.titulo.lowercased())", detalle: "\(t.minutosViaje) min \(t.medioViaje == "auto" ? "en auto" : "en transporte público")",
                                color: Categoria.cita.rgb, salida: true))
            }
            let fin = t.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60)
            let detalle = t.esCita ? [t.lugar.nilSiVacio, "hasta \(Formato.hora(fin))"].compactMap { $0 }.joined(separator: " · ")
                : [t.proyecto?.titulo, Formato.minutos(t.duracionMinutos)].compactMap { $0 }.joined(separator: " · ")
            let objetivo = perfil.objetivos.contains(t.area) && !t.area.isEmpty ? t.area : nil
            r.append(Evento(hora: t.inicio, titulo: t.titulo, detalle: detalle, color: t.categoria.rgb, objetivo: objetivo))
        }
        if let h = perfil.horarioTrabajo(dia) {
            r.append(Evento(hora: dia.addingTimeInterval(Double(h.inicio) * 60), titulo: "Trabajo", detalle: Perfil.horas(h.inicio, h.fin),
                            color: paleta.secundario, fijo: true))
        }
        let i = Perfil.indiceDia(dia)
        for f in perfil.fijos where f.dias[safe: i] == true {
            r.append(Evento(hora: dia.addingTimeInterval(Double(f.inicio) * 60), titulo: f.titulo, detalle: Perfil.horas(f.inicio, f.fin),
                            color: paleta.secundario, fijo: true))
        }
        return r.sorted { $0.hora < $1.hora }
    }

    private var animo: String {
        let n = delDia.count
        switch n {
        case 0: return "Mañana está libre. **Buen día para algo tuyo, o para descansar.**"
        case 1...3: return "Un día liviano: \(n == 1 ? "una cosa" : "\(n) cosas"). **Buen día para meterle a lo importante.**"
        case 4...5: return "Un día con ritmo: \(n) cosas. **Vamos de a una y sale.**"
        default: return "Mañana viene cargado: \(n) cosas. **Vamos de a una, que ya está todo en su lugar.**"
        }
    }

    private var pasoDia: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mañana, \(nombreDia.lowercased())").font(.serif(27, relativoA: .title)).padding(.top, 14)
                    Text(.init(animo)).font(.subheadline).padding(.top, 12).padding(.bottom, 18)
                    if eventos.isEmpty {
                        Text("Nada agendado.").foregroundStyle(paleta.secundario.color)
                    }
                    ForEach(Array(eventos.enumerated()), id: \.element.id) { i, e in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Formato.hora(e.hora)).font(.serif(16, relativoA: .body)).monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                            ZStack(alignment: .top) {
                                if i < eventos.count - 1 { Rectangle().fill(paleta.linea.color).frame(width: 1.5).padding(.top, 14) }
                                Group {
                                    if e.salida { Circle().stroke(e.color.color, lineWidth: 1.5) }
                                    else if e.fijo { RoundedRectangle(cornerRadius: 3).fill(e.color.color.opacity(0.5)) }
                                    else { Circle().fill(e.color.color) }
                                }
                                .frame(width: 10, height: 10).padding(.top, 5)
                            }
                            .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(e.titulo).font(e.salida || e.fijo ? .subheadline : .body.weight(.medium))
                                        .foregroundStyle(e.salida || e.fijo ? paleta.secundario.color : paleta.texto.color)
                                    if let o = e.objetivo {
                                        Text(o).font(.caption2.weight(.semibold)).foregroundStyle(paleta.primario.color)
                                            .padding(.horizontal, 7).padding(.vertical, 1)
                                            .overlay(Capsule().stroke(paleta.primario.color.opacity(0.4)))
                                    }
                                }
                                Text(e.detalle).font(.caption).foregroundStyle(paleta.secundario.color)
                            }
                            .padding(.bottom, 16)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            Button("Siguiente") { siguiente() }.buttonStyle(BotonPrimario(paleta: paleta)).padding(20)
        }
    }

    // MARK: 2. Qué dejamos listo

    private var paraPreparar: [Tarea] { delDia.filter { !$0.notas.trimmingCharacters(in: .whitespaces).isEmpty } }

    private var pasoListo: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("¿Qué dejamos listo?").font(.serif(27, relativoA: .title)).padding(.top, 14)
                    Text(.init("Tocá **Listo** si ya está, o **Mañana** y te aviso antes.")).font(.subheadline)
                        .foregroundStyle(paleta.secundario.color).padding(.top, 6).padding(.bottom, 10)
                    if paraPreparar.isEmpty {
                        Text("No hay nada para llevar ni dejar listo. Uno menos.").foregroundStyle(paleta.secundario.color).padding(.vertical, 12)
                    }
                    ForEach(paraPreparar, id: \.uid) { t in filaPreparar(t) }
                    Button("+ Agregar algo para mañana") { cargando = true }
                        .foregroundStyle(paleta.primario.color).padding(.vertical, 14)
                }
                .padding(.horizontal, 20)
            }
            Button("Siguiente") { siguiente() }.buttonStyle(BotonPrimario(paleta: paleta)).padding(20)
        }
    }

    private func horaAviso(_ t: Tarea) -> Date { (t.salida ?? t.inicio).addingTimeInterval(-30 * 60) }

    private func filaPreparar(_ t: Tarea) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(t.categoria.rgb.color).frame(width: 8, height: 8)
                Text("\(t.titulo) · \(Formato.hora(t.inicio))").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            HStack(spacing: 10) {
                Text(t.notas).font(.body)
                    .strikethrough(t.preparado == "listo")
                    .foregroundStyle(t.preparado == "listo" ? paleta.secundario.color : paleta.texto.color)
                Spacer(minLength: 4)
                opcion("Listo", activa: t.preparado == "listo") { marcar(t, "listo") }
                opcion("Mañana", activa: t.preparado == "manana") { marcar(t, "manana") }
            }
            if t.preparado == "manana" {
                Text(t.salida != nil ? "Te aviso 30 min antes de salir (\(Formato.hora(horaAviso(t))))." : "Te aviso a las \(Formato.hora(horaAviso(t))).")
                    .font(.caption).foregroundStyle(paleta.primario.color)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(paleta.linea.color).frame(height: 1) }
    }

    private func opcion(_ t: String, activa: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(t, action: accion)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(activa ? paleta.fondo.color : paleta.texto.color)
            .background(activa ? paleta.primario.color : .clear, in: Capsule())
            .overlay(Capsule().stroke(activa ? paleta.primario.color : paleta.linea.color))
            .buttonStyle(.plain)
    }

    private func marcar(_ t: Tarea, _ estado: String) {
        t.preparado = t.preparado == estado ? "" : estado
        let id = "\(t.uid.uuidString)-preparar"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        if t.preparado == "manana", horaAviso(t) > .now {
            Avisos.agregar(id: id, fecha: horaAviso(t), titulo: "Prepará: \(t.notas)", cuerpo: "Para \(t.titulo) de las \(Formato.hora(t.inicio)).")
        }
        Acciones.guardar(ctx)
    }

    // MARK: 3. La importante

    /// Las candidatas: lo de mañana y lo que falta elegir hora; las de los objetivos primero.
    private var candidatas: [Tarea] {
        let sinHora = tareas.filter { $0.estado == .faltaHora }
        let lista = delDia.filter { !$0.esCita } + sinHora
        return lista.sorted { a, b in
            let oa = perfil.objetivos.contains(a.area) && !a.area.isEmpty, ob = perfil.objetivos.contains(b.area) && !b.area.isEmpty
            if oa != ob { return oa }
            return a.inicio < b.inicio
        }
    }

    private var pasoImportante: some View {
        let elegidaTarea = candidatas.first { $0.uid == elegida }
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("La importante de mañana").font(.serif(27, relativoA: .title)).padding(.top, 14)
                    Text(perfil.firme ? "Elegí una para poder cerrar. Las de tus objetivos van primero." : "Si mañana hacés una sola cosa, ¿cuál es? Las de tus objetivos van primero.")
                        .font(.subheadline).foregroundStyle(paleta.secundario.color).padding(.bottom, 8)
                    if candidatas.isEmpty {
                        Text("No hay tareas para mañana todavía.").foregroundStyle(paleta.secundario.color)
                    }
                    ForEach(candidatas, id: \.uid) { t in
                        let sel = elegida == t.uid
                        let objetivo = perfil.objetivos.contains(t.area) && !t.area.isEmpty
                        Button { elegir(t) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                if sel { Text("★ LA IMPORTANTE").font(.caption2.weight(.bold)).foregroundStyle(Dorado.texto.color) }
                                Text(t.titulo).font(.serif(17, relativoA: .headline))
                                Text([t.estado == .faltaHora ? "Falta hora" : Formato.hora(t.inicio), t.area.nilSiVacio].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(paleta.secundario.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(sel ? Dorado.borde.color : paleta.linea.color, lineWidth: sel ? 1.5 : 1))
                            .opacity(objetivo || sel ? 1 : 0.7)
                        }
                        .buttonStyle(.plain)
                    }
                    if let t = elegidaTarea, let m = mover {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A la \(perfil.rinde == "noche" ? "noche" : (perfil.rinde == "tarde" ? "tarde" : "mañana")) rendís mejor. ¿La pasamos a las \(Formato.hora(m))?")
                                .font(.subheadline)
                            HStack(spacing: 16) {
                                Button("Sí, a las \(Formato.hora(m))") { Acciones.reprogramar(t, a: m, ctx: ctx); mover = nil }.fontWeight(.semibold)
                                Button("Dejala como está") { mover = nil }.foregroundStyle(paleta.secundario.color)
                            }
                            .font(.subheadline)
                        }
                        .padding(12)
                        .background(paleta.primario.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 20)
            }
            Button("Siguiente") { siguiente() }
                .buttonStyle(BotonPrimario(paleta: paleta))
                .disabled(perfil.firme && elegida == nil && !candidatas.isEmpty)
                .opacity(perfil.firme && elegida == nil && !candidatas.isEmpty ? 0.45 : 1)
                .padding(20)
        }
    }

    private func elegir(_ t: Tarea) {
        for o in tareas where o.importante && o.uid != t.uid && (cal.isDate(o.inicio, inSameDayAs: dia) || o.estado == .faltaHora) {
            o.importante = false
        }
        t.importante = true
        elegida = t.uid
        Acciones.guardar(ctx)
        Widgets.actualizar(tareas)
        mover = mejorHora(t)
    }

    /// Si rinde mejor en otro momento del día y ahí hay un hueco libre, lo sugiere (sin consecuencias si no).
    private func mejorHora(_ t: Tarea) -> Date? {
        guard t.estado == .programada else { return nil }
        let (desde, hasta): (Int, Int) = perfil.rinde == "noche" ? (19, 23) : (perfil.rinde == "tarde" ? (14, 19) : (max(perfil.apertura, 8), 13))
        let hora = cal.component(.hour, from: t.inicio)
        guard hora < desde || hora >= hasta else { return nil }
        let otras = tareas.filter { $0.uid != t.uid }
        let ocupados = Guardado.ocupados(otras)
        let inicioDia = cal.startOfDay(for: dia)
        return MotorSlots.sugerencias(duracion: t.duracionMinutos, ocupados: ocupados, desde: max(.now, inicioDia),
                                      apertura: desde, cierre: hasta, cantidad: 1)
            .first { cal.isDate($0.inicio, inSameDayAs: dia) }?.inicio
    }

    // MARK: 4. Cierre

    private var cierre: some View {
        let primera = delDia.first
        let imp = tareas.first { $0.importante && ($0.estado == .faltaHora || cal.isDate($0.inicio, inSameDayAs: dia)) }
        return VStack(spacing: 0) {
            Brote().padding(.top, 30)
            VStack(spacing: 6) {
                Text("Mañana está armado.").font(.serif(30, relativoA: .title))
                Text("A descansar, que \(dia.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "es")))) arranca solo.")
                    .font(.subheadline).foregroundStyle(paleta.secundario.color)
            }
            .padding(.top, 6)
            VStack(spacing: 10) {
                if let p = primera {
                    tarjetaCierre("PRIMERA COSA") {
                        Text(p.salida.map { "Salir \(Formato.hora($0)) para \(p.titulo.lowercased())" } ?? "\(Formato.hora(p.inicio)) · \(p.titulo)")
                        if !p.notas.isEmpty {
                            Text(.init("**Llevá:** \(p.notas)")).font(.footnote).foregroundStyle(paleta.secundario.color)
                        }
                    }
                }
                if let t = imp {
                    tarjetaCierre("LA IMPORTANTE") {
                        Text(t.titulo).font(.serif(18, relativoA: .headline))
                        Text(t.estado == .faltaHora ? "falta elegir hora" : Formato.hora(t.inicio)).font(.caption).foregroundStyle(paleta.secundario.color)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            Spacer(minLength: 10)
            Button("Listo") { Ritual.listo(); alCerrar() }.buttonStyle(BotonPrimario(paleta: paleta)).padding(20)
        }
    }

    private func tarjetaCierre<C: View>(_ rotulo: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rotulo).font(.caption2).tracking(0.5).foregroundStyle(paleta.secundario.color)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }
}

/// El brote aprobado de la celebración: el halo verde grande y la hoja que brota desde abajo con un saltito.
struct Brote: View {
    var diametro: CGFloat = 150
    @Environment(\.paleta) private var paleta
    @State private var aparecer = false

    var body: some View {
        CirculoQueRespira(halo: paleta.energia, fondo: paleta.fondo, diametro: diametro, intensidad: 0.7) {
            Image(systemName: "leaf.fill")
                .font(.system(size: diametro * 0.31))
                .foregroundStyle(paleta.primario.color)
                .scaleEffect(aparecer ? 1 : 0.2, anchor: .bottom)
                .opacity(aparecer ? 1 : 0)
        }
        .frame(height: diametro * 1.6)
        .onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.3).delay(0.4)) { aparecer = true } }
    }
}
