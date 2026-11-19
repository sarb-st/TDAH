import SwiftUI
import SwiftData
import PhotosUI
import ContactsUI
import UIKit

/// Un binding al perfil guardado: cada cambio se guarda solo.
@MainActor
@propertyWrapper
struct PerfilVivo: DynamicProperty {
    @AppStorage(Perfil.clave) private var datos = Data()
    var wrappedValue: Perfil {
        get { Perfil.desde(datos) }
        nonmutating set { datos = newValue.datos }
    }
    var projectedValue: Binding<Perfil> { Binding(get: { wrappedValue }, set: { wrappedValue = $0 }) }
}

// MARK: - Vos

/// Lo tuyo: tu foto, tu día, lo que te importa, tu semana y tu gente.
struct VosView: View {
    let paleta: Paleta
    @Environment(\.dismiss) private var cerrar
    @Query private var registros: [SlotRegistro]
    @PerfilVivo private var perfil
    @AppStorage("fotoPerfil") private var versionFoto = 0
    @State private var fotoElegida: PhotosPickerItem?

    private var focoSemana: Int {
        let lunes = Perfil.lunes(de: .now)
        return registros.filter { MotorSlots.resultadosConFoco.contains($0.resultado) && ($0.fin ?? .distantPast) >= lunes }
            .map(\.minutosReales).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    cabecera
                    titulo("Tu día")
                    fila("Te levantás") { hora($perfil.levanta) }
                    fila("Te acostás") { hora($perfil.acuesta) }
                    bloque {
                        Text("¿Cuándo rendís más?")
                        Picker("Rendís más", selection: $perfil.rinde) {
                            Text("Mañana").tag("manana")
                            Text("Tarde").tag("tarde")
                            Text("Noche").tag("noche")
                        }
                        .pickerStyle(.segmented)
                        Text("Para proponerte las cosas pesadas a esa hora.").font(.caption).foregroundStyle(paleta.secundario.color)
                    }
                    titulo("Lo que te importa")
                    NavigationLink { ObjetivosView(paleta: paleta) } label: {
                        filaLink("Objetivos", perfil.objetivos.filter { !$0.isEmpty }.joined(separator: " · ").nilSiVacio ?? "Hasta tres")
                    }
                    bloque {
                        Text("Con la importante")
                        Picker("Con la importante", selection: $perfil.modo) {
                            Text("Suave").tag("suave")
                            Text("Firme").tag("firme")
                        }
                        .pickerStyle(.segmented)
                        Text(perfil.firme
                             ? "Te la recuerda a la mañana, cuida su horario, y decirle “Ahora no” cuesta más."
                             : "Tiene su ★ y nada más. Decidís como siempre.")
                            .font(.caption).foregroundStyle(paleta.secundario.color)
                    }
                    titulo("Tu semana")
                    NavigationLink { HorariosFijosView(paleta: paleta) } label: {
                        filaLink("Horarios fijos", resumenFijos)
                    }
                    NavigationLink { EstaSemanaView(paleta: paleta) } label: {
                        filaLink("¿Qué te toca esta semana?", perfil.trabajo.activo ? (perfil.turno(semanaDe: .now) == "m" ? "Turno mañana" : "Turno tarde") : "Sin trabajo cargado")
                    }
                    fila("Minutos de foco") { Text("Esta semana \(Formato.minutos(focoSemana))").foregroundStyle(paleta.secundario.color) }
                    titulo("Tu gente")
                    NavigationLink { LosTuyosView(paleta: paleta) } label: { filaLink("Los tuyos", "Llamadas, audios y en persona") }
                    fila("Tu persona de accountability") { Text("Próximamente").foregroundStyle(paleta.secundario.color) }
                }
                .padding(20)
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Vos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
        .environment(\.paleta, paleta)
        .tint(paleta.primario.color)
        .onChange(of: fotoElegida) { _, item in Task { await guardarFoto(item) } }
    }

    private var resumenFijos: String {
        var partes: [String] = []
        if perfil.trabajo.activo { partes.append("Trabajo") }
        partes += perfil.fijos.map(\.titulo)
        return partes.isEmpty ? "Nada cargado" : partes.joined(separator: " · ")
    }

    private var cabecera: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $fotoElegida, matching: .images) {
                FotoPerfil(lado: 78, conBorde: true)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill").font(.caption)
                            .foregroundStyle(paleta.fondo.color)
                            .frame(width: 28, height: 28)
                            .background(paleta.primario.color, in: Circle())
                            .overlay(Circle().stroke(paleta.fondo.color, lineWidth: 3))
                            .offset(x: 3, y: 3)
                    }
            }
            .accessibilityLabel("Cambiar la foto")
            VStack(alignment: .leading, spacing: 2) {
                TextField("Tu nombre", text: $perfil.nombre).font(.serif(26, relativoA: .title))
                Text("Tu nombre va en los avisos a tu persona.").font(.caption).foregroundStyle(paleta.secundario.color)
                if versionFoto > 0 {
                    Button("Sacar la foto") {
                        try? FileManager.default.removeItem(at: FotoPerfil.url)
                        versionFoto = 0
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func guardarFoto(_ item: PhotosPickerItem?) async {
        guard let item, let datos = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: datos) else { return }
        let lado: CGFloat = 400
        let escala = lado / min(img.size.width, img.size.height)
        let tam = CGSize(width: img.size.width * escala, height: img.size.height * escala)
        let chica = UIGraphicsImageRenderer(size: tam).image { _ in img.draw(in: CGRect(origin: .zero, size: tam)) }
        if let jpg = chica.jpegData(compressionQuality: 0.85) {
            try? jpg.write(to: FotoPerfil.url, options: .atomic)
            versionFoto += 1
        }
    }

    private func titulo(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 14)
    }

    private func bloque<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func fila<C: View>(_ t: String, @ViewBuilder _ derecha: () -> C) -> some View {
        HStack { Text(t); Spacer(); derecha() }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func filaLink(_ t: String, _ sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(t).foregroundStyle(paleta.texto.color)
                Text(sub).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func hora(_ minutos: Binding<Int>) -> some View {
        DatePicker("", selection: Binding<Date>(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minutos.wrappedValue) * 60) },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); minutos.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
                   displayedComponents: .hourAndMinute)
            .labelsHidden()
    }
}

// MARK: - Horarios fijos

/// Lo ocupado siempre: el trabajo (dos turnos, qué días, días distintos y si alterna) y lo demás fijo.
struct HorariosFijosView: View {
    let paleta: Paleta
    @PerfilVivo private var perfil
    @State private var diaEditado: Int?
    @State private var fijoEditado: HorarioFijo?

    private static let letras = ["L", "M", "M", "J", "V", "S", "D"]
    static let nombres = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábados", "domingos"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lo que ya está ocupado. Ahí la app no te propone nada; si cargás algo vos, te deja.")
                    .font(.subheadline).foregroundStyle(paleta.secundario.color)
                trabajo
                ForEach(perfil.fijos) { f in
                    Button { fijoEditado = f } label: { tarjetaFijo(f) }.buttonStyle(.plain)
                }
                Button {
                    fijoEditado = HorarioFijo(titulo: "", dias: [false, false, false, false, false, true, false], inicio: 10 * 60, fin: 12 * 60)
                } label: {
                    Text("+ Agregar un horario fijo").frame(maxWidth: .infinity).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .foregroundStyle(paleta.primario.color)
            }
            .padding(20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationTitle("Horarios fijos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { diaEditado.map { DiaEditado(id: $0) } }, set: { diaEditado = $0?.id })) { d in
            DiaDistintoView(dia: d.id).environment(\.paleta, paleta).presentationDetents([.medium])
        }
        .sheet(item: $fijoEditado) { f in
            EditarFijoView(fijo: f).environment(\.paleta, paleta).presentationDetents([.medium, .large])
        }
    }

    struct DiaEditado: Identifiable { let id: Int }

    private var trabajo: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "briefcase").frame(width: 32, height: 32).background(paleta.primario.color.opacity(0.12), in: Circle())
                Text("Trabajo").font(.serif(19, relativoA: .title3))
                Spacer()
                Toggle("Trabajo", isOn: $perfil.trabajo.activo).labelsHidden()
            }
            .foregroundStyle(paleta.texto.color)
            if perfil.trabajo.activo {
                renglon("Turno mañana") { rango($perfil.trabajo.manana) }
                renglon("Turno tarde") { rango($perfil.trabajo.tarde) }
                Divider().padding(.vertical, 8)
                Text("Días").font(.subheadline)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let trabaja = perfil.trabajo.dias[i]
                        Button {
                            if trabaja { diaEditado = i } else { perfil.trabajo.dias[i] = true }
                        } label: {
                            Text(Self.letras[i]).font(.footnote.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(trabaja ? paleta.fondo.color : paleta.texto.color)
                                .background(trabaja ? paleta.primario.color : paleta.fondo.color, in: Circle())
                                .overlay(Circle().stroke(paleta.linea.color, lineWidth: trabaja ? 0 : 1))
                                .overlay(alignment: .topTrailing) {
                                    if perfil.trabajo.distintos[String(i)] != nil {
                                        Circle().fill(Categoria.cita.rgb.color).frame(width: 9, height: 9)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Self.nombres[i])\(trabaja ? ", trabajás" : "")")
                    }
                }
                .padding(.top, 6)
                ForEach(perfil.trabajo.distintos.keys.sorted(), id: \.self) { k in
                    if let i = Int(k), perfil.trabajo.dias[safe: i] == true, let c = perfil.trabajo.distintos[k] {
                        HStack {
                            Text("Los \(Self.nombres[i])")
                            Spacer()
                            Text(DiaDistintoView.texto(c)).foregroundStyle(paleta.secundario.color)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Categoria.cita.rgb.mezcla(paleta.superficie, 0.84).color, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 6)
                    }
                }
                Text("Tocá un día marcado para darle otro horario. Tocá uno sin marcar para sumarlo.")
                    .font(.caption).foregroundStyle(paleta.secundario.color).padding(.top, 6)
                Divider().padding(.vertical, 8)
                Toggle("Alterno cada semana", isOn: $perfil.trabajo.alterna)
                Text("El domingo a las 20 te pregunto qué te toca esa semana, y ahí cambiás algo puntual.")
                    .font(.caption).foregroundStyle(paleta.secundario.color).padding(.top, 4)
            }
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
    }

    private func renglon<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack { Text(t); Spacer(); c() }.padding(.top, 10)
    }

    private func rango(_ turno: Binding<Turno>) -> some View {
        HStack(spacing: 4) {
            selectorHora(Binding(get: { turno.wrappedValue.inicio }, set: { turno.wrappedValue.inicio = $0 }))
            Text("–").foregroundStyle(paleta.secundario.color)
            selectorHora(Binding(get: { turno.wrappedValue.fin }, set: { turno.wrappedValue.fin = $0 }))
        }
    }

    private func selectorHora(_ m: Binding<Int>) -> some View {
        DatePicker("", selection: Binding<Date>(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(m.wrappedValue) * 60) },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
                   displayedComponents: .hourAndMinute)
            .labelsHidden()
    }

    private func tarjetaFijo(_ f: HorarioFijo) -> some View {
        let dias = f.dias.enumerated().filter(\.element).map { Self.nombres[$0.offset] }
        return HStack {
            Image(systemName: "clock").frame(width: 32, height: 32).background(paleta.primario.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(f.titulo.isEmpty ? "Sin nombre" : f.titulo).font(.serif(18, relativoA: .headline))
                Text("\(dias.isEmpty ? "ningún día" : dias.joined(separator: ", ")) · \(Perfil.horas(f.inicio, f.fin))")
                    .font(.caption).foregroundStyle(paleta.secundario.color)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(paleta.secundario.color)
        }
        .foregroundStyle(paleta.texto.color)
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
    }
}

/// Un día del trabajo que es distinto siempre: entrás o salís antes o después.
struct DiaDistintoView: View {
    let dia: Int
    @PerfilVivo private var perfil
    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta
    @State private var c = [0, 0]

    static func corrimiento(_ m: Int) -> String {
        if m == 0 { return "a horario" }
        let a = abs(m)
        let t = a < 60 ? "\(a) min" : (a % 60 == 0 ? "\(a / 60) h" : "\(a / 60) h \(a % 60)")
        return "\(t) \(m < 0 ? "antes" : "después")"
    }

    static func texto(_ c: [Int]) -> String {
        var partes: [String] = []
        if let a = c[safe: 0], a != 0 { partes.append("entrás \(corrimiento(a))") }
        if let b = c[safe: 1], b != 0 { partes.append("salís \(corrimiento(b))") }
        return partes.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Todos los \(HorariosFijosView.nombres[dia])").font(.serif(22, relativoA: .title2)).padding(.top, 18)
            filaPaso("Entrás", 0)
            filaPaso("Salís", 1)
            Text("Turno mañana: \(Perfil.horas(perfil.trabajo.manana.inicio + c[0], perfil.trabajo.manana.fin + c[1]))\nTurno tarde: \(Perfil.horas(perfil.trabajo.tarde.inicio + c[0], perfil.trabajo.tarde.fin + c[1]))")
                .font(.footnote).foregroundStyle(paleta.secundario.color)
            Button("Listo") {
                if c == [0, 0] { perfil.trabajo.distintos[String(dia)] = nil } else { perfil.trabajo.distintos[String(dia)] = c }
                cerrar()
            }
            .buttonStyle(BotonPrimario(paleta: paleta))
            Button("Ese día no trabajo") {
                perfil.trabajo.dias[dia] = false
                perfil.trabajo.distintos[String(dia)] = nil
                cerrar()
            }
            .frame(maxWidth: .infinity)
            .font(.subheadline)
            .foregroundStyle(paleta.secundario.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(paleta.fondo.color.ignoresSafeArea())
        .onAppear { c = perfil.trabajo.distintos[String(dia)] ?? [0, 0] }
    }

    private func filaPaso(_ t: String, _ i: Int) -> some View {
        HStack {
            Text(t)
            Spacer()
            Text(Self.corrimiento(c[i])).font(.serif(17, relativoA: .body)).monospacedDigit()
            Stepper(t, value: $c[i], in: -240...240, step: 30).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Un horario fijo que no es el trabajo.
struct EditarFijoView: View {
    @State var fijo: HorarioFijo
    @PerfilVivo private var perfil
    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta

    var body: some View {
        NavigationStack {
            Form {
                TextField("Qué es (rugby, curso, gimnasio…)", text: $fijo.titulo)
                Section("Días") {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            Button { fijo.dias[i].toggle() } label: {
                                Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.footnote.weight(.semibold))
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(fijo.dias[i] ? paleta.fondo.color : paleta.texto.color)
                                    .background(fijo.dias[i] ? paleta.primario.color : .clear, in: Circle())
                                    .overlay(Circle().stroke(paleta.linea.color, lineWidth: fijo.dias[i] ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Horario") {
                    DatePicker("Desde", selection: hora(\.inicio), displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: hora(\.fin), displayedComponents: .hourAndMinute)
                }
                if perfil.fijos.contains(where: { $0.id == fijo.id }) {
                    Button("Borrar este horario", role: .destructive) {
                        perfil.fijos.removeAll { $0.id == fijo.id }
                        cerrar()
                    }
                }
            }
            .navigationTitle("Horario fijo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let i = perfil.fijos.firstIndex(where: { $0.id == fijo.id }) { perfil.fijos[i] = fijo } else { perfil.fijos.append(fijo) }
                        cerrar()
                    }
                    .disabled(fijo.titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(paleta.primario.color)
    }

    private func hora(_ k: WritableKeyPath<HorarioFijo, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(fijo[keyPath: k]) * 60) },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); fijo[keyPath: k] = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
}

// MARK: - Objetivos

/// Hasta tres objetivos, con los minutos de foco de la semana. Lo demás se ordena solo en áreas;
/// "Lo último que ordenó" se corrige tocando la etiqueta, y la app aprende para lo parecido.
struct ObjetivosView: View {
    let paleta: Paleta
    @PerfilVivo private var perfil
    @Query(sort: \Tarea.creada, order: .reverse) private var tareas: [Tarea]
    @Query private var registros: [SlotRegistro]
    @Environment(\.modelContext) private var ctx
    @State private var aprendido: String?

    static let coloresAreas: [String: RGB] = ["Casa": RGB(0xB7A98F), "Cuidado personal": RGB(0x9DB5AC), "Pareja": RGB(0xC9A0A0),
                                              "Trámites y papeles": RGB(0xA7B48C), "Trabajo": RGB(0x8EA3B8), "Tiempo libre": RGB(0xC9A35E)]

    static func color(_ area: String, objetivos: [String]) -> RGB {
        if let i = objetivos.firstIndex(of: area) { return [RGB(0x7FA383), RGB(0x9C92B4), RGB(0x6E86A0)][i % 3] }
        return coloresAreas[area] ?? RGB(0xC2B49C)
    }

    /// Minutos de foco de esta semana por objetivo o área.
    private var minutos: [String: Int] {
        let lunes = Perfil.lunes(de: .now)
        let area = Dictionary(tareas.map { ($0.uid, $0.area) }, uniquingKeysWith: { a, _ in a })
        var r: [String: Int] = [:]
        for reg in registros where MotorSlots.resultadosConFoco.contains(reg.resultado) && (reg.fin ?? .distantPast) >= lunes {
            if let a = area[reg.uidTarea], !a.isEmpty { r[a, default: 0] += reg.minutosReales }
        }
        return r
    }

    var body: some View {
        let mins = minutos
        let maximo = max(60, mins.values.max() ?? 60)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Lo que de verdad importa").font(.serif(23, relativoA: .title2))
                Text("Hasta tres objetivos. Tocá un nombre para cambiarlo.").font(.subheadline).foregroundStyle(paleta.secundario.color)
                ForEach(0..<3, id: \.self) { i in
                    if i < perfil.objetivos.count {
                        objetivo(i, minutos: mins[perfil.objetivos[i]] ?? 0, maximo: maximo)
                    } else if i == perfil.objetivos.count {
                        Button { perfil.objetivos.append("") } label: {
                            Text(i == 0 ? "+ Agregar un objetivo" : "+ Agregar otro").frame(maxWidth: .infinity).padding(12)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .foregroundStyle(paleta.primario.color)
                    }
                }
                seccion("Lo demás, ordenado solo")
                ForEach(Perfil.areas, id: \.self) { a in
                    let m = mins[a] ?? 0
                    VStack(spacing: 4) {
                        HStack {
                            Circle().fill((Self.coloresAreas[a] ?? paleta.halo).color).frame(width: 10, height: 10)
                            Text(a).font(.subheadline)
                            Spacer()
                            Text(Formato.minutos(m)).font(.caption).foregroundStyle(paleta.secundario.color).monospacedDigit()
                        }
                        barra(Double(m) / Double(maximo), color: Self.coloresAreas[a] ?? paleta.halo)
                    }
                    .padding(.vertical, 4)
                }
                seccion("Lo último que ordenó · tocá para corregir")
                ForEach(Array(tareas.filter { !$0.area.isEmpty || $0.estado != .archivada }.prefix(8)), id: \.uid) { t in
                    HStack {
                        Text(t.titulo).font(.subheadline).lineLimit(1)
                        Spacer()
                        Menu {
                            ForEach(perfil.objetivos.filter { !$0.isEmpty } + Perfil.areas, id: \.self) { a in
                                Button(a) { corregir(t, a) }
                            }
                        } label: {
                            let a = t.area.isEmpty ? "Sin ordenar" : t.area
                            Text("\(a) ▾").font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .foregroundStyle(paleta.texto.color)
                                .background(Self.color(t.area, objetivos: perfil.objetivos).mezcla(paleta.superficie, 0.75).color, in: Capsule())
                                .overlay(Capsule().stroke(Self.color(t.area, objetivos: perfil.objetivos).color.opacity(0.7)))
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let a = aprendido { Text(a).font(.caption).foregroundStyle(paleta.primario.color) }
            }
            .padding(20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationTitle("Objetivos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func objetivo(_ i: Int, minutos: Int, maximo: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Un objetivo de esta etapa", text: Binding(get: { perfil.objetivos[safe: i] ?? "" },
                                                                      set: { if perfil.objetivos.indices.contains(i) { perfil.objetivos[i] = $0 } }))
                    .font(.serif(18, relativoA: .headline))
                Button { perfil.objetivos.remove(at: i) } label: { Image(systemName: "xmark").font(.caption) }
                    .foregroundStyle(paleta.secundario.color)
                    .accessibilityLabel("Quitar objetivo")
            }
            HStack(spacing: 8) {
                barra(Double(minutos) / Double(maximo), color: Self.color(perfil.objetivos[safe: i] ?? "", objetivos: perfil.objetivos))
                Text("\(Formato.minutos(minutos)) esta semana").font(.caption).foregroundStyle(paleta.secundario.color).fixedSize()
            }
        }
        .padding(14)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func seccion(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 16)
    }

    private func barra(_ f: Double, color: RGB) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(paleta.linea.color)
                Capsule().fill(color.color).frame(width: max(4, g.size.width * min(1, f)))
            }
        }
        .frame(height: 6)
    }

    private func corregir(_ t: Tarea, _ area: String) {
        guard t.area != area else { return }
        t.area = area
        Acciones.guardar(ctx)
        perfil.correcciones.append(Correccion(titulo: t.titulo, area: area))
        if perfil.correcciones.count > 40 { perfil.correcciones.removeFirst(perfil.correcciones.count - 40) }
        aprendido = "Anotado: lo parecido a “\(t.titulo)” va a ir a \(area)."
    }
}
