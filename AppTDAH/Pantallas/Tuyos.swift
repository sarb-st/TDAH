import SwiftUI
import SwiftData
import ContactsUI
import UIKit

/// Los colores de las personas (de la paleta de la app).
enum ColoresPersona {
    static let todos = [RGB(0x4E6B55), RGB(0xB08A3E), RGB(0x6E86A0), RGB(0x9C92B4), RGB(0x5E8378)]
    static func color(_ i: Int) -> RGB { todos[((i % todos.count) + todos.count) % todos.count] }
}

/// Cómo saludar: llamada, audio, mensaje o en persona.
enum Medio: String, CaseIterable, Identifiable {
    case llamada, audio, mensaje, persona
    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .llamada: "Llamada"
        case .audio: "Audio"
        case .mensaje: "Mensaje"
        case .persona: "En persona"
        }
    }

    var icono: String {
        switch self {
        case .llamada: "phone"
        case .audio: "mic"
        case .mensaje: "message"
        case .persona: "person.2"
        }
    }

    var minutos: Int {
        switch self {
        case .llamada: 20
        case .audio, .mensaje: 5
        case .persona: 60
        }
    }

    func titulo(_ nombre: String) -> String {
        switch self {
        case .llamada: "Llamar a \(nombre)"
        case .audio: "Mandarle un audio a \(nombre)"
        case .mensaje: "Escribirle a \(nombre)"
        case .persona: "Ver a \(nombre)"
        }
    }
}

/// Un círculo de persona: la foto o, sin foto, la letra y la circunferencia en su color; el aro del estado gira despacio.
struct CirculoPersona: View {
    let persona: Persona
    var lado: CGFloat = 58
    var elegida = false
    @Environment(\.paleta) private var paleta
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var giro = 0.0

    var body: some View {
        let color = ColoresPersona.color(persona.color)
        ZStack {
            Circle().fill(paleta.superficie.color)
            if let datos = persona.foto, let img = UIImage(data: datos) {
                Image(uiImage: img).resizable().scaledToFill().clipShape(Circle()).padding(4)
            } else {
                Text(persona.inicial).font(.serif(lado * 0.4, relativoA: .title2)).foregroundStyle(color.color)
            }
            Circle().stroke(color.color.opacity(0.22), lineWidth: 2.5).padding(-5)
            Circle().trim(from: 0, to: max(0.03, persona.aro()))
                .stroke(color.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90 + giro))
                .padding(-5)
        }
        .frame(width: lado, height: lado)
        .padding(5)
        .overlay {
            if elegida { Circle().stroke(color.color, lineWidth: 2).padding(-3) }
        }
        .onAppear {
            guard !reducir else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { giro = 360 }
        }
    }
}

/// Estar presente con los tuyos: a quién saludar, cómo y de qué hablar, con el hilo de lo que te contaron.
struct LosTuyosView: View {
    let paleta: Paleta
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Persona.creada) private var personas: [Persona]
    @Query private var tareas: [Tarea]
    @State private var elegidaUid: UUID?
    @State private var medio: Medio = .llamada
    @State private var tema = ""
    @State private var temas: [String] = []
    @State private var buscandoTemas = false
    @State private var opcion = 0
    @State private var aviso: String?
    @State private var preguntando: Persona?

    private var elegida: Persona? { personas.first { $0.uid == elegidaUid } ?? personas.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("ESTAR PRESENTE CON LOS MÍOS").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 8)
                Text("¿A quién saludamos?").font(.serif(23, relativoA: .title2))
                Text("Una llamada, un audio, un mensaje o en persona. Lo tuyo, sin tareas.")
                    .font(.subheadline).foregroundStyle(paleta.secundario.color)
                caras.padding(.top, 10)
                if !personas.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dashed").foregroundStyle(paleta.primario.color)
                        Text("Lleno: hablaron hace poco. Se vacía con los días; vacío, ya toca.")
                    }
                    .font(.caption).foregroundStyle(paleta.secundario.color)
                }
                if let p = elegida { panel(p).padding(.top, 10) }
                if let a = aviso { Text(a).font(.footnote).foregroundStyle(paleta.primario.color).padding(.top, 8) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationTitle("Los tuyos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preguntando) { p in PreguntaPersonaView(persona: p).environment(\.paleta, paleta).presentationDetents([.medium, .large]) }
        .onChange(of: elegidaUid) { _, _ in tema = ""; temas = []; opcion = 0; cargarTemas() }
        .onAppear { cargarTemas() }
    }

    private var caras: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(personas, id: \.uid) { p in
                    Button { elegidaUid = p.uid } label: {
                        VStack(spacing: 2) {
                            CirculoPersona(persona: p, elegida: p.uid == elegida?.uid)
                            Text(p.nombre).font(.caption).lineLimit(1).foregroundStyle(paleta.texto.color)
                            Text(estado(p)).font(.caption2).foregroundStyle(paleta.secundario.color)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Quitar", role: .destructive) { ctx.delete(p); Acciones.guardar(ctx) }
                    }
                }
                Button { SelectorContactos.abrir { agregar($0) } } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus").font(.title3)
                            .frame(width: 58, height: 58)
                            .overlay(Circle().stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .padding(5)
                        Text(personas.isEmpty ? "Elegir de Contactos" : "Sumar").font(.caption).multilineTextAlignment(.center)
                    }
                    .frame(width: 80)
                    .foregroundStyle(paleta.primario.color)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    private func estado(_ p: Persona) -> String {
        guard let d = p.dias() else { return "sin anotar" }
        if d == 0 { return "hoy" }
        return p.yaToca() ? "ya toca" : "hace \(d) d"
    }

    private func panel(_ p: Persona) -> some View {
        let color = ColoresPersona.color(p.color)
        let opciones = cuandos(p)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nombre).font(.serif(21, relativoA: .title3))
                HStack(spacing: 4) {
                    Text(p.dias().map { $0 == 0 ? "Hablaron hoy" : "Hace \($0) días" } ?? "Todavía sin anotar")
                    Text("·")
                    Menu {
                        ForEach([(7, "cada semana"), (15, "cada 15 días"), (30, "cada mes")], id: \.0) { d, t in
                            Button(t) { p.cadaDias = d; Acciones.guardar(ctx) }
                        }
                    } label: { Text("te gusta \(p.cadaDias <= 7 ? "cada semana" : (p.cadaDias <= 15 ? "cada 15 días" : "cada mes")) ▾") }
                }
                .font(.caption).foregroundStyle(paleta.secundario.color)
            }
            if !p.hilo.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(p.hilo.prefix(2)), id: \.persistentModelID) { n in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fecha(n.fecha).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(paleta.secundario.color)
                            Text(n.texto).font(.footnote)
                        }
                    }
                }
                .padding(.leading, 11)
                .overlay(alignment: .leading) { Rectangle().fill(color.color.opacity(0.55)).frame(width: 2) }
            }
            rotulo("¿Cómo?")
            HStack(spacing: 6) {
                ForEach(Medio.allCases) { m in
                    Button { medio = m } label: {
                        VStack(spacing: 4) {
                            Image(systemName: m.icono).foregroundStyle(color.color)
                            Text(m.nombre).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(medio == m ? color.color : paleta.linea.color, lineWidth: medio == m ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(paleta.texto.color)
                }
            }
            rotulo("¿De qué querés hablar?")
            TextField("Algo que no te quieras olvidar", text: $tema, axis: .vertical)
                .padding(10)
                .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color))
            if buscandoTemas { ProgressView().controlSize(.small) }
            if !temas.isEmpty {
                FlujoChips(textos: temas, color: color) { t in
                    tema = tema.isEmpty ? t : tema + " · " + t
                    temas.removeAll { $0 == t }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(Array(opciones.enumerated()), id: \.offset) { i, f in
                        Button(Formato.diaYHora(f, ahora: .now)) { opcion = i }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(opciones[safe: opcion].map { Formato.diaYHora($0, ahora: .now) } ?? "Elegir cuándo").font(.subheadline)
                        Text("un hueco libre ▾").font(.caption2).foregroundStyle(paleta.secundario.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color))
                }
                .foregroundStyle(paleta.texto.color)
                Button("Agendar") { agendar(p, en: opciones[safe: opcion]) }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .foregroundStyle(paleta.fondo.color)
                    .background(paleta.primario.color, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(opciones.isEmpty)
            }
            .padding(.top, 4)
            Button(p.nombre.lowercased().hasPrefix("tus ") || p.nombre.lowercased().hasPrefix("mis ") ? "Ya hablamos" : "Ya hablé") { preguntando = p }
                .font(.subheadline)
                .underline()
                .foregroundStyle(paleta.primario.color)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(paleta.linea.color))
    }

    private func rotulo(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 6)
    }

    private func fecha(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "Hoy" : d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es")))
    }

    /// Tres huecos libres para saludar, que respetan lo agendado y lo fijo.
    private func cuandos(_ p: Persona) -> [Date] {
        let perfil = Perfil.actual
        let ocupados = Guardado.ocupados(tareas)
        return MotorSlots.sugerencias(duracion: medio.minutos, ocupados: ocupados, desde: .now,
                                      apertura: perfil.apertura, cierre: perfil.cierre).map(\.inicio)
    }

    private func cargarTemas() {
        guard let p = elegida, ClaveIA.hay, !p.hilo.isEmpty else { return }
        buscandoTemas = true
        Task {
            temas = (try? await ClienteClaude.temasPersona(nombre: p.nombre, hilo: p.hilo.map(\.texto))) ?? []
            buscandoTemas = false
        }
    }

    private func agregar(_ c: CNContact) {
        // Solo se leen los datos que vinieron con el contacto (pedir otros hace fallar la app).
        let nombrePila = c.isKeyAvailable(CNContactGivenNameKey) ? c.givenName : ""
        let apellido = c.isKeyAvailable(CNContactFamilyNameKey) ? c.familyName : ""
        let nombre = [nombrePila, apellido].filter { !$0.isEmpty }.joined(separator: " ")
        guard !nombre.isEmpty else { return }
        let p = Persona(nombre: nombrePila.isEmpty ? nombre : nombrePila, color: personas.count)
        if c.isKeyAvailable(CNContactThumbnailImageDataKey) { p.foto = c.thumbnailImageData }
        ctx.insert(p)
        Acciones.guardar(ctx)
        elegidaUid = p.uid
    }

    private func agendar(_ p: Persona, en fecha: Date?) {
        guard let fecha else { return }
        let t = Tarea(titulo: medio.titulo(p.nombre), inicio: fecha, duracionMinutos: medio.minutos)
        t.personaUid = p.uid.uuidString
        t.medio = medio.rawValue
        t.notas = tema.trimmingCharacters(in: .whitespacesAndNewlines)
        let objetivos = Perfil.actual.objetivos
        if let o = objetivos.first(where: { $0.lowercased().contains("presente") || $0.lowercased().contains("míos") || $0.lowercased().contains("afecto") }) {
            t.area = o
        }
        ctx.insert(t)
        Acciones.guardar(ctx)
        Avisos.programarInicio(t)
        Calendario.sincronizar(t)
        aviso = "Agendado: \(medio.nombre.lowercased()) a \(p.nombre), \(Formato.diaYHora(fecha, ahora: .now).lowercased()). Cuando termines te pregunto qué te contó."
        tema = ""
    }
}

/// "¿Qué te contó? ¿En qué quedaron?": se guarda en el hilo de esa persona y el aro se llena.
struct PreguntaPersonaView: View {
    let persona: Persona
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta
    @State private var texto = ""
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿Cómo te fue con \(persona.nombre)?").font(.serif(23, relativoA: .title2)).padding(.top, 20)
            Text("¿Qué te contó? ¿En qué quedaron? Lo guardo en su hilo para la próxima.")
                .font(.subheadline).foregroundStyle(paleta.secundario.color)
            TextField("Por ejemplo: quedamos en hablar el domingo", text: $texto, axis: .vertical)
                .lineLimit(3...6)
                .focused($foco)
                .padding(12)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
            FlujoChips(textos: ["Todo bien, nada para anotar", "Quedamos en algo"], color: ColoresPersona.color(persona.color)) { t in
                texto = t.hasPrefix("Todo") ? "Todo bien." : "Quedamos en "
                foco = true
            }
            Button("Guardar en el hilo") {
                let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                let n = NotaPersona(texto: limpio.isEmpty ? "Hablaron." : limpio)
                ctx.insert(n)
                n.persona = persona
                persona.ultimaVez = .now
                Acciones.guardar(ctx)
                cerrar()
            }
            .buttonStyle(BotonPrimario(paleta: paleta))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(paleta.fondo.color.ignoresSafeArea())
        .tint(paleta.primario.color)
    }
}

/// Chips punteados que se acomodan en renglones.
struct FlujoChips: View {
    let textos: [String]
    let color: RGB
    var alTocar: (String) -> Void
    @Environment(\.paleta) private var paleta

    var body: some View {
        FlowLayout(espacio: 6) {
            ForEach(textos, id: \.self) { t in
                Button(t) { alTocar(t) }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().stroke(color.color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .foregroundStyle(paleta.texto.color)
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Acomoda las vistas de izquierda a derecha y pasa al renglón siguiente cuando no entran.
struct FlowLayout: Layout {
    var espacio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x + t.width > ancho && x > 0 { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            alto = max(alto, t.height)
        }
        return CGSize(width: ancho, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}

/// El selector de Contactos del iPhone. No pide permiso: solo devuelve la persona que elegís.
@MainActor
enum SelectorContactos {
    private final class Delegado: NSObject, CNContactPickerDelegate {
        var alElegir: ((CNContact) -> Void)?
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { alElegir?(contact) }
    }
    private static let delegado = Delegado()

    static func abrir(_ alElegir: @escaping (CNContact) -> Void) {
        delegado.alElegir = alElegir
        let picker = CNContactPickerViewController()
        picker.delegate = delegado
        guard let escena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var arriba = escena.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let siguiente = arriba.presentedViewController { arriba = siguiente }
        arriba.present(picker, animated: true)
    }
}
