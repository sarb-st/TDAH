import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Cargar o editar una tarea a mano (en la Fase 2 se suma el dictado con IA).
struct NuevaTareaView: View {
    let tarea: Tarea?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Query private var todas: [Tarea]

    @State private var titulo = ""
    @State private var inicio = MotorSlots.redondearArriba(.now.addingTimeInterval(30 * 60), minutos: 15)
    @State private var duracion = 30
    @State private var pasos: [String] = []
    @State private var lugar = ""
    @State private var direccion = ""
    @State private var notas = ""
    @State private var choque: (con: Tarea, sugerida: Date?)?
    @FocusState private var foco: Bool

    private let duraciones = [10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Qué vas a hacer", text: $titulo, axis: .vertical)
                        .font(.serif(20, relativoA: .title3))
                        .focused($foco)
                }
                Section {
                    DatePicker("Comienza", selection: $inicio, in: Date()...)
                    Picker("Duración", selection: $duracion) {
                        ForEach(duraciones, id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
                Section {
                    TextField("Lugar", text: $lugar).focused($foco)
                    TextField("Dirección", text: $direccion).focused($foco).textContentType(.fullStreetAddress)
                    TextField("Notas: qué llevar, qué no olvidar…", text: $notas, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($foco)
                } header: {
                    Text("Lugar y notas (opcional)")
                } footer: {
                    Text("Las notas aparecen antes de empezar, junto a la cuenta regresiva.")
                }
                Section("Pasos (opcional)") {
                    ForEach(pasos.indices, id: \.self) { i in
                        TextField("Paso \(i + 1)", text: $pasos[i]).focused($foco)
                    }
                    .onDelete { pasos.remove(atOffsets: $0) }
                    Button("Agregar paso") { pasos.append("") }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tarea == nil ? "Nueva tarea" : "Editar tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: revisarYGuardar).disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { foco = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                        .accessibilityLabel("Ocultar teclado")
                }
            }
            .alert(textoChoque, isPresented: Binding(get: { choque != nil }, set: { if !$0 { choque = nil } })) {
                if let sugerida = choque?.sugerida {
                    Button("Ponerla a las \(Formato.hora(sugerida))") { inicio = sugerida; guardar() }
                }
                Button("Guardar igual") { guardar() }
                Button("Cambiar la hora", role: .cancel) {}
            }
            .onAppear(perform: cargar)
        }
    }

    private var textoChoque: String {
        guard let c = choque?.con else { return "" }
        return "Se pisa con “\(c.titulo)” de las \(Formato.hora(c.inicio))."
    }

    private func cargar() {
        guard let t = tarea else { return }
        titulo = t.titulo
        inicio = max(t.inicio, .now)
        duracion = duraciones.contains(t.duracionMinutos) ? t.duracionMinutos : 30
        pasos = t.pasosOrdenados.map(\.texto)
        lugar = t.lugar
        direccion = t.direccion
        notas = t.notas
    }

    /// Antes de guardar, revisa que no se pise con otra tarea; si se pisa, ofrece el próximo hueco libre.
    private func revisarYGuardar() {
        let otras = todas.filter { $0.uid != tarea?.uid && $0.ocupaAgenda }
        let propuesta = DateInterval(start: inicio, duration: Double(duracion) * 60)
        if let con = otras.first(where: { MotorSlots.solapa(propuesta, con: [$0.intervalo]) }) {
            let sugerida = MotorSlots.sugerencias(duracion: duracion, ocupados: otras.map(\.intervalo),
                                                  desde: inicio.addingTimeInterval(-10 * 60), apertura: 0, cierre: 23,
                                                  cantidad: 1).first?.inicio
            choque = (con, sugerida)
        } else {
            guardar()
        }
    }

    private func guardar() {
        let t = tarea ?? Tarea(titulo: "", inicio: inicio, duracionMinutos: duracion)
        if tarea == nil { ctx.insert(t) }
        t.titulo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        t.inicio = inicio
        t.duracionMinutos = duracion
        t.lugar = lugar.trimmingCharacters(in: .whitespacesAndNewlines)
        t.direccion = direccion.trimmingCharacters(in: .whitespacesAndNewlines)
        t.notas = notas.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.estado != .enCurso { t.estado = .programada }
        let hechos = Set(t.pasos.filter(\.hecho).map(\.texto))
        for p in t.pasos { ctx.delete(p) }
        for (i, texto) in pasos.map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }).enumerated() {
            let paso = Paso(texto: texto, orden: i, hecho: hechos.contains(texto))
            ctx.insert(paso)
            paso.tarea = t
        }
        Acciones.guardar(ctx)
        Avisos.pedirPermiso()
        let programar = t.estado == .programada
        Task {
            await Alarmas.pedirPermiso()
            if programar { Avisos.programarInicio(t) }
        }
        cerrar()
    }
}

struct AjustesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @Query private var registros: [SlotRegistro]
    @AppStorage("apariencia") private var apariencia = Apariencia.automatico.rawValue
    @AppStorage("alarmas") private var alarmas = true
    @State private var importando = false
    @State private var mensaje: String?

    private var minutosDeFoco: Int {
        registros.filter { MotorSlots.resultadosConFoco.contains($0.resultado) }.map(\.minutosReales).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Minutos de foco", value: Formato.minutos(minutosDeFoco))
                } footer: {
                    Text("Todo el tiempo que trabajaste en tus slots desde que usás la app.")
                }

                Section {
                    Picker("Apariencia", selection: $apariencia) {
                        ForEach(Apariencia.allCases) { Text($0.nombre).tag($0.rawValue) }
                    }
                } header: {
                    Text("Apariencia")
                } footer: {
                    Text("Automático cambia de a poco con la luz del día. Siempre día queda en el color de la mañana.")
                }

                Section {
                    Toggle("Sonar como alarma", isOn: $alarmas)
                        .disabled(!Alarmas.soportadas)
                        .onChange(of: alarmas) { _, activa in
                            if activa { Task { await Alarmas.pedirPermiso() } }
                        }
                    if Alarmas.soportadas && alarmas && !Alarmas.autorizadas {
                        Text("Falta el permiso: cuando cargues una tarea te lo va a pedir, o activalo en Ajustes del iPhone → AppTDAH.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Avisos")
                } footer: {
                    Text(Alarmas.soportadas
                         ? "El comienzo y el fin de cada slot suenan como un despertador, aunque el iPhone esté en silencio."
                         : "Para que suene como alarma hace falta iOS 26 o más nuevo. Por ahora llegan como notificación.")
                }

                Section {
                    LabeledContent("Última copia", value: CopiaSeguridad.ultima.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Todavía no")
                    Button("Hacer una copia ahora") {
                        CopiaSeguridad.guardar(ctx)
                        mensaje = "Copia guardada."
                    }
                    if FileManager.default.fileExists(atPath: CopiaSeguridad.url.path) {
                        ShareLink("Guardar la copia en iCloud Drive…", item: CopiaSeguridad.url)
                    }
                    Button("Restaurar desde una copia…") { importando = true }
                } header: {
                    Text("Copia de seguridad")
                } footer: {
                    Text("Se hace sola cada vez que salís de la app. El archivo está en Archivos → En mi iPhone → AppTDAH. Si vas a borrar la app, guardala antes en iCloud Drive.")
                }

                Section("Firma") {
                    if let vence = Firma.vencimiento() {
                        LabeledContent("Vence", value: vence.formatted(date: .abbreviated, time: .shortened))
                        Text("Te aviso dos días antes para renovarla en SideStore.").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Esta compilación no tiene firma (normal en pruebas).").foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink("Diagnóstico") { DiagnosticoView() }
                }

                Section("Versión") {
                    LabeledContent("Compilada", value: Textos.fechaDeCompilacion(timestamp: BuildInfo.timestamp))
                    if let commit = BuildInfo.commit { LabeledContent("Código", value: commit) }
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .fileImporter(isPresented: $importando, allowedContentTypes: [.json]) { resultado in
                switch resultado {
                case .success(let url):
                    do { mensaje = "Listo: \(try CopiaSeguridad.restaurar(desde: url, en: ctx)) tareas recuperadas." }
                    catch { mensaje = "No pude leer esa copia."; Registro.anotar("Restaurar copia: \(error.localizedDescription)") }
                case .failure(let error):
                    Registro.anotar("Elegir copia: \(error.localizedDescription)")
                }
            }
            .alert(mensaje ?? "", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
                Button("Listo", role: .cancel) {}
            }
        }
    }
}

/// Muestra el registro de errores para copiarlo y pegarlo en Claude Code.
struct DiagnosticoView: View {
    @State private var texto = ""
    @State private var copiado = false

    var body: some View {
        ScrollView {
            Text(texto.isEmpty ? "Sin errores registrados." : texto)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnóstico")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Borrar", role: .destructive) { Registro.borrar(); texto = "" }
                Spacer()
                Button(copiado ? "Copiado" : "Copiar todo") {
                    UIPasteboard.general.string = diagnosticoCompleto
                    copiado = true
                }
            }
        }
        .onAppear { texto = Registro.leer() }
    }

    private var diagnosticoCompleto: String {
        let version = "AppTDAH \(BuildInfo.commit ?? "local") · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)"
        let alarmas = "Alarmas: \(Alarmas.soportadas ? (Alarmas.autorizadas ? "autorizadas" : "sin permiso") : "no soportadas")"
        return version + "\n" + alarmas + "\n\n" + texto
    }
}
