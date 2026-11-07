import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Cargar o editar una tarea a mano (en la Fase 2 se suma el dictado con IA).
struct NuevaTareaView: View {
    let tarea: Tarea?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @State private var titulo = ""
    @State private var inicio = MotorSlots.redondearArriba(.now.addingTimeInterval(30 * 60), minutos: 15)
    @State private var duracion = 30
    @State private var pasos: [String] = []

    private let duraciones = [10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Qué vas a hacer", text: $titulo, axis: .vertical)
                        .font(.serif(20, relativoA: .title3))
                }
                Section {
                    DatePicker("Comienza", selection: $inicio, in: Date()...)
                    Picker("Duración", selection: $duracion) {
                        ForEach(duraciones, id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
                Section("Pasos (opcional)") {
                    ForEach(pasos.indices, id: \.self) { i in
                        TextField("Paso \(i + 1)", text: $pasos[i])
                    }
                    .onDelete { pasos.remove(atOffsets: $0) }
                    Button("Agregar paso") { pasos.append("") }
                }
            }
            .navigationTitle(tarea == nil ? "Nueva tarea" : "Editar tarea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: guardar).disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: cargar)
        }
    }

    private func cargar() {
        guard let t = tarea else { return }
        titulo = t.titulo
        inicio = max(t.inicio, .now)
        duracion = duraciones.contains(t.duracionMinutos) ? t.duracionMinutos : 30
        pasos = t.pasosOrdenados.map(\.texto)
    }

    private func guardar() {
        let t = tarea ?? Tarea(titulo: "", inicio: inicio, duracionMinutos: duracion)
        if tarea == nil { ctx.insert(t) }
        t.titulo = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        t.inicio = inicio
        t.duracionMinutos = duracion
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
        if t.estado == .programada { Avisos.programarInicio(t) }
        cerrar()
    }
}

struct AjustesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var cerrar
    @AppStorage("apariencia") private var apariencia = Apariencia.automatico.rawValue
    @State private var importando = false
    @State private var mensaje: String?

    var body: some View {
        NavigationStack {
            Form {
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
        return version + "\n\n" + texto
    }
}
