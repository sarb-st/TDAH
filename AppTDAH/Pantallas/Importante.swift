import SwiftUI
import SwiftData

/// La etiqueta dorada "★ La importante".
struct EtiquetaImportante: View {
    var texto = "La importante"
    var body: some View {
        Text("★ \(texto.uppercased())")
            .font(.caption2.weight(.bold)).tracking(0.6)
            .foregroundStyle(Dorado.texto.color)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Dorado.fondo.color, in: Capsule())
    }
}

/// Lo que se muestra la primera vez que se abre la app en el día.
enum MananaImportante {
    static let clave = "importanteVista"

    static func yaVista(ahora: Date = .now) -> Bool {
        UserDefaults.standard.string(forKey: clave) == Ritual.clave(de: ahora)
    }

    static func marcar(ahora: Date = .now) { UserDefaults.standard.set(Ritual.clave(de: ahora), forKey: clave) }

    /// Un hueco libre de verdad antes de la importante (respeta lo agendado y lo fijo).
    @MainActor
    static func hueco(para t: Tarea, tareas: [Tarea], ahora: Date = .now) -> Sugerencia? {
        let perfil = Perfil.actual
        let ocupados = Guardado.ocupados(tareas.filter { $0.uid != t.uid })
        guard let s = MotorSlots.sugerencias(duracion: t.duracionMinutos, ocupados: ocupados, desde: ahora,
                                             apertura: perfil.apertura, cierre: perfil.cierre, cantidad: 1).first,
              Calendar.current.isDate(s.inicio, inSameDayAs: t.inicio),
              s.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60) <= t.inicio.addingTimeInterval(1) else { return nil }
        return Sugerencia(inicio: s.inicio, libreHasta: min(s.libreHasta, t.inicio))
    }
}

/// Firme, la primera vez del día: "Buen día. Hoy lo importante es:". Si hay un hueco libre antes, ofrece adelantarla.
struct BuenDiaView: View {
    let tarea: Tarea
    let paleta: Paleta
    var alCerrar: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query private var tareas: [Tarea]

    var body: some View {
        let hueco = MananaImportante.hueco(para: tarea, tareas: tareas)
        let trabajo = Perfil.actual.horarioTrabajo(.now)
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(maxHeight: 120)
            Text("BUEN DÍA").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color)
            Text("Hoy lo importante es:").font(.serif(30, relativoA: .largeTitle)).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("★ LA IMPORTANTE").font(.caption2.weight(.bold)).foregroundStyle(Dorado.texto.color)
                    Spacer()
                    Text("\(Formato.hora(tarea.inicio)) · \(Formato.minutos(tarea.duracionMinutos))").font(.caption).foregroundStyle(paleta.secundario.color)
                }
                Text(tarea.titulo).font(.serif(20, relativoA: .title3))
            }
            .padding(.vertical, 16).padding(.leading, 21).padding(.trailing, 16)
            .background(paleta.superficie.color)
            .overlay(alignment: .leading) { Rectangle().fill(tarea.categoria.rgb.color).frame(width: 6) }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Dorado.borde.color, lineWidth: 1.5))
            .padding(.top, 22)
            Group {
                if let h = hueco {
                    chip("Libre de \(Formato.hora(h.inicio)) a \(Formato.hora(h.libreHasta))")
                    Text("Tenés un hueco antes. ¿Arrancamos por ahí?").font(.body).foregroundStyle(paleta.secundario.color).padding(.top, 10)
                } else if let tr = trabajo {
                    chip("Trabajás de \(Perfil.horas(tr.inicio, tr.fin))")
                    Text("Queda para las \(Formato.hora(tarea.inicio)), con la cabeza ya libre.").foregroundStyle(paleta.secundario.color).padding(.top, 10)
                } else {
                    Text("A las \(Formato.hora(tarea.inicio)) te espera.").foregroundStyle(paleta.secundario.color)
                }
            }
            .padding(.top, 28)
            Spacer()
            if let h = hueco {
                Button("Sí, adelantala a las \(Formato.hora(h.inicio))") { Acciones.correr(tarea, a: h.inicio, ctx: ctx); alCerrar() }
                    .buttonStyle(BotonPrimario(paleta: paleta))
                Button("A las \(Formato.hora(tarea.inicio)) está bien", action: alCerrar)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color))
                    .padding(.top, 10)
            } else {
                Button("Dale", action: alCerrar).buttonStyle(BotonPrimario(paleta: paleta))
            }
            Text(hueco == nil ? "No hay hueco antes: no te ofrezco adelantarla." : "Una sola vez por día, la primera vez que abrís la app.")
                .font(.caption).foregroundStyle(paleta.secundario.color).frame(maxWidth: .infinity).padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.bottom, 16)
        .background(paleta.fondo.color.ignoresSafeArea())
        .foregroundStyle(paleta.texto.color)
        .tint(paleta.primario.color)
    }

    private func chip(_ t: String) -> some View {
        Label(t, systemImage: "circle.fill")
            .labelStyle(EtiquetaChica())
            .font(.footnote)
            .foregroundStyle(paleta.primario.color)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(paleta.primario.color.opacity(0.1), in: Capsule())
    }
}

/// Suave, la primera vez del día: una tarjetita dorada que baja y se va sola.
struct RecordatorioImportante: View {
    let tarea: Tarea
    @Environment(\.paleta) private var paleta

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("★ HOY, LO IMPORTANTE").font(.caption2.weight(.bold)).foregroundStyle(Dorado.texto.color)
            Text(tarea.titulo).font(.serif(18, relativoA: .headline))
            Text("\(Formato.hora(tarea.inicio)) · \(Formato.minutos(tarea.duracionMinutos))").font(.caption).foregroundStyle(paleta.secundario.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Dorado.borde.color, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .accessibilityLabel("Hoy, lo importante: \(tarea.titulo), a las \(Formato.hora(tarea.inicio))")
    }
}

/// El arco que avanza: el círculo de la app sin cerrar, como algo en camino.
struct ArcoQueAvanza: View {
    @Environment(\.paleta) private var paleta
    @State private var largo = 0.5

    var body: some View {
        ZStack {
            Circle().fill(paleta.superficie.color)
            Circle().stroke(paleta.linea.color)
            Circle().stroke(paleta.primario.color.opacity(0.18), lineWidth: 2.5).padding(12)
            Circle().trim(from: 0, to: largo)
                .stroke(paleta.primario.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(12)
        }
        .frame(width: 58, height: 58)
        .onAppear { withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { largo = 0.7 } }
        .accessibilityHidden(true)
    }
}

/// Si pasan un par de días sin nada de un objetivo: un empujoncito cálido con dos cosas chicas para seguir.
struct EmpujonView: View {
    let objetivo: String
    let paleta: Paleta
    var alCerrar: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query private var tareas: [Tarea]
    @Query private var registros: [SlotRegistro]
    @PerfilVivo private var perfil
    @State private var comentario: String?
    @State private var sugerencias: [PropuestaIA.TareaIA] = []
    @State private var agendadas: [String: Date] = [:]
    @State private var cargando = true

    private var recientes: [Tarea] {
        tareas.filter { $0.area == objetivo && $0.estado == .terminada }.sorted { ($0.inicioReal ?? $0.inicio) > ($1.inicioReal ?? $1.inicio) }
    }

    /// Minutos de foco de los últimos siete días para este objetivo.
    private var barras: [Int] {
        let cal = Calendar.current
        let uids = Set(tareas.filter { $0.area == objetivo }.map(\.uid))
        return (0..<7).reversed().map { atras in
            let dia = cal.date(byAdding: .day, value: -atras, to: cal.startOfDay(for: .now)) ?? .now
            return registros.filter { uids.contains($0.uidTarea) && cal.isDate($0.fin ?? .distantPast, inSameDayAs: dia) }.map(\.minutosReales).reduce(0, +)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    ArcoQueAvanza()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "es"))).uppercased())
                            .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color)
                        Text("¿Le damos un empujoncito a lo tuyo?").font(.serif(23, relativoA: .title2))
                    }
                }
                .padding(.top, 20)
                VStack(alignment: .leading, spacing: 10) {
                    Label(objetivo.uppercased(), systemImage: "circle.fill")
                        .labelStyle(EtiquetaChica())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Categoria.tarea.texto(en: paleta))
                    let b = barras
                    let maximo = max(30, b.max() ?? 30)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(b.enumerated()), id: \.offset) { _, m in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(m > 0 ? Categoria.tarea.rgb.color : Categoria.tarea.rgb.mezcla(paleta.superficie, 0.8).color)
                                .frame(width: 18, height: m > 0 ? max(10, 30 * CGFloat(m) / CGFloat(maximo)) : 6)
                        }
                        Text("esta semana").font(.caption).foregroundStyle(paleta.secundario.color).padding(.leading, 6)
                    }
                    .frame(height: 32, alignment: .bottom)
                    if cargando && comentario == nil { ProgressView() }
                    Text(comentario ?? (recientes.first.map { "Lo último fue “\($0.titulo)”. ¿Seguimos desde ahí?" } ?? "¿Arrancamos con algo chico?"))
                        .font(.subheadline)
                    ForEach(sugerencias, id: \.titulo) { s in sugerencia(s) }
                    if !ClaveIA.hay && sugerencias.isEmpty, let ultima = recientes.first {
                        sugerencia(PropuestaIA.TareaIA(titulo: ultima.titulo, duracion_min: ultima.duracionMinutos))
                    }
                }
                .padding(14)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(paleta.linea.color))
                .padding(.top, 18)
                HStack(spacing: 18) {
                    Button("Ahora no", action: alCerrar)
                    Button("Avisame menos seguido") { perfil.diasEmpujon = min(14, perfil.diasEmpujon + 2); alCerrar() }
                }
                .font(.subheadline)
                .underline()
                .foregroundStyle(paleta.secundario.color)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .foregroundStyle(paleta.texto.color)
        .tint(paleta.primario.color)
        .task {
            guard ClaveIA.hay else { cargando = false; return }
            if let r = try? await ClienteClaude.empujon(objetivo: objetivo, recientes: recientes.prefix(5).map(\.titulo)) {
                comentario = r.comentario
                sugerencias = Array(r.sugerencias.prefix(2))
            }
            cargando = false
        }
    }

    private func hueco(_ minutos: Int) -> Date? {
        let perfil = Perfil.actual
        return MotorSlots.sugerencias(duracion: minutos, ocupados: Guardado.ocupados(tareas), desde: .now,
                                      apertura: perfil.apertura, cierre: perfil.cierre, cantidad: 1).first?.inicio
    }

    private func sugerencia(_ s: PropuestaIA.TareaIA) -> some View {
        let cuando = agendadas[s.titulo] ?? hueco(max(10, s.duracion_min))
        let hecha = agendadas[s.titulo] != nil
        return HStack(spacing: 10) {
            Image(systemName: "sparkle").foregroundStyle(Categoria.tarea.texto(en: paleta))
                .frame(width: 34, height: 34)
                .background(Categoria.tarea.rgb.mezcla(paleta.superficie, 0.8).color, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.titulo).font(.subheadline.weight(.medium))
                Text("\(Formato.minutos(max(10, s.duracion_min)))\(cuando.map { " · " + Formato.diaYHora($0, ahora: .now).lowercased() } ?? "")")
                    .font(.caption).foregroundStyle(paleta.secundario.color)
            }
            Spacer(minLength: 4)
            Button(hecha ? "✓ \(cuando.map { Formato.hora($0) } ?? "")" : "Agendar") {
                guard !hecha, let f = cuando else { return }
                let t = Tarea(titulo: s.titulo, inicio: f, duracionMinutos: max(10, s.duracion_min))
                t.area = objetivo
                ctx.insert(t)
                Acciones.guardar(ctx)
                Avisos.programarInicio(t)
                Calendario.sincronizar(t)
                agendadas[s.titulo] = f
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .foregroundStyle(hecha ? paleta.primario.color : paleta.fondo.color)
            .background(hecha ? .clear : paleta.primario.color, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(hecha ? Categoria.tarea.rgb.mezcla(paleta.superficie, 0.84).color : paleta.fondo.color, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Si hace falta un empujoncito hoy: el primer objetivo sin nada terminado en los últimos días.
enum Empujon {
    static let clave = "empujonDia"

    @MainActor
    static func objetivo(tareas: [Tarea], ahora: Date = .now) -> String? {
        guard UserDefaults.standard.string(forKey: clave) != Ritual.clave(de: ahora) else { return nil }
        let perfil = Perfil.actual
        let limite = ahora.addingTimeInterval(-Double(perfil.diasEmpujon) * 86_400)
        for o in perfil.objetivos where !o.trimmingCharacters(in: .whitespaces).isEmpty {
            let delObjetivo = tareas.filter { $0.area == o }
            let hecho = delObjetivo.contains { $0.estado == .terminada && ($0.inicioReal ?? $0.inicio) > limite }
            let agendado = delObjetivo.contains { $0.ocupaAgenda && $0.inicio < ahora.addingTimeInterval(2 * 86_400) }
            if !hecho && !agendado { return o }
        }
        return nil
    }

    static func marcar(ahora: Date = .now) { UserDefaults.standard.set(Ritual.clave(de: ahora), forKey: clave) }
}
