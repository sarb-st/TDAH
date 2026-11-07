import Foundation
import SwiftData
import UserNotifications

/// Registro de errores propio. Se ve y se copia desde Ajustes → Diagnóstico.
/// No guarda títulos de tareas ni datos personales.
enum Registro {
    private static let cola = DispatchQueue(label: "app.tdah.registro")

    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("diagnostico.log")
    }

    static func anotar(_ texto: String) {
        let linea = "\(Date().formatted(.iso8601)) \(texto)\n"
        cola.async {
            let datos = Data(linea.utf8)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(datos)
                try? h.close()
            } else {
                try? datos.write(to: url)
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let tamano = attrs[.size] as? Int, tamano > 200_000,
               let todo = try? Data(contentsOf: url) {
                try? todo.suffix(100_000).write(to: url)
            }
        }
    }

    static func leer() -> String {
        cola.sync { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }

    static func borrar() {
        cola.sync { try? FileManager.default.removeItem(at: url) }
    }
}

/// Notificaciones locales: avisos de la hora (repetidos), aviso 5 min antes del final, fin del slot y firma.
enum Avisos {
    private static var centro: UNUserNotificationCenter { .current() }
    private static var activos: Bool { DatosDemo.pantalla == nil }

    static func pedirPermiso() {
        guard activos else { return }
        centro.requestAuthorization(options: [.alert, .sound, .badge]) { ok, error in
            if let error { Registro.anotar("Permiso de avisos: error \(error.localizedDescription)") }
            else { Registro.anotar("Permiso de avisos: \(ok ? "aceptado" : "rechazado")") }
        }
    }

    private static func ids(_ t: Tarea, _ tipo: String, _ cantidad: Int) -> [String] {
        (0..<cantidad).map { "\(t.uid.uuidString)-\(tipo)-\($0)" }
    }

    static func programarInicio(_ t: Tarea) {
        cancelarInicio(t)
        let textos = [
            (t.titulo, "Comienza ahora. Abrí para decidir."),
            (t.titulo, "Te está esperando. Abrí para decidir."),
            ("Último aviso: \(t.titulo)", "Si la descartás, cierro este slot y te pregunto cuándo.")
        ]
        for (i, fecha) in MotorSlots.horariosAviso(t.inicio).enumerated() where fecha > .now {
            agregar(id: ids(t, "inicio", textos.count)[i], fecha: fecha, titulo: textos[i].0, cuerpo: textos[i].1)
        }
    }

    static func programarFin(_ t: Tarea) {
        cancelarFin(t)
        guard let fin = t.finPrevisto else { return }
        let ids = ids(t, "fin", 2)
        let antes = fin.addingTimeInterval(-5 * 60)
        if antes > .now { agregar(id: ids[0], fecha: antes, titulo: "Quedan 5 minutos", cuerpo: t.titulo) }
        if fin > .now { agregar(id: ids[1], fecha: fin, titulo: "Terminó el tiempo", cuerpo: "\(t.titulo). ¿Cómo seguimos?") }
    }

    static func cancelarInicio(_ t: Tarea) { centro.removePendingNotificationRequests(withIdentifiers: ids(t, "inicio", 3)) }
    static func cancelarFin(_ t: Tarea) { centro.removePendingNotificationRequests(withIdentifiers: ids(t, "fin", 2)) }
    static func cancelarTodo(_ t: Tarea) { cancelarInicio(t); cancelarFin(t) }

    static func agregar(id: String, fecha: Date, titulo: String, cuerpo: String) {
        guard activos else { return }
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = cuerpo
        contenido.sound = .default
        let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fecha)
        let pedido = UNNotificationRequest(identifier: id, content: contenido,
                                           trigger: UNCalendarNotificationTrigger(dateMatching: partes, repeats: false))
        centro.add(pedido) { error in
            if let error { Registro.anotar("No se pudo programar un aviso: \(error.localizedDescription)") }
        }
    }
}

/// Lee cuándo vence la firma que puso SideStore y avisa dos días antes.
enum Firma {
    static func vencimiento() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let datos = try? Data(contentsOf: url),
              let texto = String(data: datos, encoding: .isoLatin1),
              let desde = texto.range(of: "<?xml"),
              let hasta = texto.range(of: "</plist>") else { return nil }
        let plist = String(texto[desde.lowerBound..<hasta.upperBound])
        let dic = try? PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any]
        return dic?["ExpirationDate"] as? Date
    }

    static func programarAviso() {
        guard let vence = vencimiento() else {
            Registro.anotar("Firma: sin perfil embebido (compilación sin firmar).")
            return
        }
        Registro.anotar("Firma: vence \(vence.formatted(.iso8601)).")
        let aviso = vence.addingTimeInterval(-2 * 86_400)
        guard aviso > .now else { return }
        Avisos.agregar(id: "firma", fecha: aviso, titulo: "Renová la firma",
                       cuerpo: "Abrí SideStore y tocá Refresh All. La app vence en dos días.")
    }
}

/// Copia de seguridad en un archivo que se ve en la app Archivos ("En mi iPhone" → AppTDAH).
enum CopiaSeguridad {
    struct CopiaPaso: Codable { var texto: String; var hecho: Bool; var orden: Int }
    struct CopiaTarea: Codable {
        var uid: UUID
        var titulo: String
        var inicio: Date
        var duracionMinutos: Int
        var estado: String
        var inicioReal: Date?
        var minutosExtra: Int
        var pasos: [CopiaPaso]
    }
    struct Copia: Codable { var version = 1; var creada: Date; var tareas: [CopiaTarea] }

    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AppTDAH-copia.json")
    }

    static var ultima: Date? { UserDefaults.standard.object(forKey: "ultimaCopia") as? Date }

    @MainActor static func guardar(_ ctx: ModelContext) {
        guard DatosDemo.pantalla == nil else { return }
        do {
            let tareas = try ctx.fetch(FetchDescriptor<Tarea>())
            let copia = Copia(creada: .now, tareas: tareas.map { t in
                CopiaTarea(uid: t.uid, titulo: t.titulo, inicio: t.inicio, duracionMinutos: t.duracionMinutos,
                           estado: t.estadoRaw, inicioReal: t.inicioReal, minutosExtra: t.minutosExtra,
                           pasos: t.pasosOrdenados.map { CopiaPaso(texto: $0.texto, hecho: $0.hecho, orden: $0.orden) })
            })
            let codificador = JSONEncoder()
            codificador.dateEncodingStrategy = .iso8601
            codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
            try codificador.encode(copia).write(to: url, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: "ultimaCopia")
        } catch {
            Registro.anotar("Copia de seguridad: error \(error.localizedDescription)")
        }
    }

    /// Agrega las tareas de la copia que no existan. Devuelve cuántas agregó.
    @MainActor static func restaurar(desde origen: URL, en ctx: ModelContext) throws -> Int {
        let acceso = origen.startAccessingSecurityScopedResource()
        defer { if acceso { origen.stopAccessingSecurityScopedResource() } }
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        let copia = try decodificador.decode(Copia.self, from: Data(contentsOf: origen))
        let existentes = Set(try ctx.fetch(FetchDescriptor<Tarea>()).map(\.uid))
        var agregadas = 0
        for c in copia.tareas where !existentes.contains(c.uid) {
            let t = Tarea(titulo: c.titulo, inicio: c.inicio, duracionMinutos: c.duracionMinutos)
            t.uid = c.uid
            t.estadoRaw = c.estado
            t.inicioReal = c.inicioReal
            t.minutosExtra = c.minutosExtra
            ctx.insert(t)
            for p in c.pasos {
                let paso = Paso(texto: p.texto, orden: p.orden, hecho: p.hecho)
                ctx.insert(paso)
                paso.tarea = t
            }
            agregadas += 1
        }
        try ctx.save()
        Registro.anotar("Copia restaurada: \(agregadas) tareas agregadas.")
        return agregadas
    }
}

/// Lo que pasa con cada decisión del usuario.
@MainActor
enum Acciones {
    static func guardar(_ ctx: ModelContext) {
        do { try ctx.save() } catch { Registro.anotar("Error al guardar: \(error.localizedDescription)") }
    }

    private static func registrar(_ t: Tarea, _ resultado: String, ctx: ModelContext, ahora: Date = .now) {
        let minutos = t.inicioReal.map { Int((ahora.timeIntervalSince($0) / 60).rounded()) } ?? 0
        ctx.insert(SlotRegistro(uidTarea: t.uid, titulo: t.titulo, inicioPlaneado: t.inicio, inicioReal: t.inicioReal,
                                fin: ahora, resultado: resultado, minutosReales: minutos))
    }

    static func empezar(_ t: Tarea, ctx: ModelContext) {
        t.estado = .enCurso
        t.inicioReal = .now
        t.minutosExtra = 0
        Avisos.cancelarInicio(t)
        Avisos.programarFin(t)
        guardar(ctx)
    }

    static func ahoraNo(_ t: Tarea, ctx: ModelContext) {
        registrar(t, "ahora no", ctx: ctx)
        t.estado = .faltaHora
        Avisos.cancelarTodo(t)
        guardar(ctx)
    }

    static func reprogramar(_ t: Tarea, a fecha: Date, ctx: ModelContext) {
        if t.estado == .programada { registrar(t, "sin respuesta", ctx: ctx) }
        t.inicio = fecha
        t.estado = .programada
        t.inicioReal = nil
        t.minutosExtra = 0
        Avisos.programarInicio(t)
        guardar(ctx)
    }

    static func archivar(_ t: Tarea, ctx: ModelContext) {
        t.estado = .archivada
        Avisos.cancelarTodo(t)
        guardar(ctx)
    }

    static func terminarAntes(_ t: Tarea, ctx: ModelContext) {
        guard let real = t.inicioReal else { return }
        t.minutosExtra = Int(Date.now.timeIntervalSince(real) / 60) - t.duracionMinutos
        Avisos.cancelarFin(t)
        guardar(ctx)
    }

    static func terminar(_ t: Tarea, ctx: ModelContext) {
        registrar(t, "terminada", ctx: ctx)
        t.estado = .terminada
        Avisos.cancelarTodo(t)
        guardar(ctx)
    }

    static func extender(_ t: Tarea, minutos: Int, ctx: ModelContext) {
        if let fin = t.finPrevisto, fin < .now {
            // Si el tiempo ya había terminado, la extensión cuenta desde ahora.
            t.minutosExtra += Int((Date.now.timeIntervalSince(fin) / 60).rounded(.up))
        }
        t.minutosExtra += minutos
        t.estado = .enCurso
        Avisos.programarFin(t)
        guardar(ctx)
    }

    static func pararPorHoy(_ t: Tarea, ctx: ModelContext) {
        registrar(t, "paro por hoy", ctx: ctx)
        t.estado = .faltaHora
        t.inicioReal = nil
        t.minutosExtra = 0
        Avisos.cancelarTodo(t)
        guardar(ctx)
    }

    static func correr(_ t: Tarea, a fecha: Date, ctx: ModelContext) {
        t.inicio = fecha
        Avisos.programarInicio(t)
        guardar(ctx)
    }

    static func borrar(_ t: Tarea, ctx: ModelContext) {
        Avisos.cancelarTodo(t)
        ctx.delete(t)
        guardar(ctx)
    }
}

/// Datos de muestra para las capturas del simulador: se activan con `-demo <pantalla> -hora <h>`.
enum DatosDemo {
    static var pantalla: String? { UserDefaults.standard.string(forKey: "demo") }
    static var hora: Double? {
        UserDefaults.standard.object(forKey: "hora") == nil ? nil : UserDefaults.standard.double(forKey: "hora")
    }
    @MainActor private static var cargado = false

    @MainActor static func cargar(en ctx: ModelContext) {
        guard let p = pantalla, !cargado else { return }
        cargado = true
        let ahora = Date()
        let pasos = ["Buscar el número de cliente", "Encontrar el teléfono de atención", "Llamar y pedir el turno",
                     "Anotar fecha y hora", "Pasarlo al calendario", "Juntar los documentos", "Confirmar por mail"]

        @discardableResult
        func tarea(_ titulo: String, en segundos: Double, _ duracion: Int, conPasos: Bool = false, hechos: Int = 0) -> Tarea {
            let t = Tarea(titulo: titulo, inicio: ahora.addingTimeInterval(segundos), duracionMinutos: duracion)
            ctx.insert(t)
            if conPasos {
                for (i, texto) in pasos.enumerated() {
                    let paso = Paso(texto: texto, orden: i, hecho: i < hechos)
                    ctx.insert(paso)
                    paso.tarea = t
                }
            }
            return t
        }

        switch p {
        case "vacio":
            break
        case "decidir":
            tarea("Llamar al banco", en: -20, 45, conPasos: true)
            tarea("Preparar el menú semanal", en: 3600, 30)
        case "cuando":
            let t = tarea("Llamar al banco", en: -1200, 45, conPasos: true)
            t.estado = .faltaHora
            tarea("Preparar el menú semanal", en: 3600, 30)
        case "encurso", "fin":
            let t = tarea("Llamar al banco", en: p == "fin" ? -46 * 60 : -12 * 60, 45, conPasos: true, hechos: 2)
            t.estado = .enCurso
            t.inicioReal = t.inicio
            tarea("Preparar el menú semanal", en: p == "fin" ? 10 * 60 : 45 * 60, 30)
        default:
            tarea("Llamar al banco", en: 272, 45, conPasos: true)
            tarea("Preparar el menú semanal", en: 3872, 30)
            tarea("Regar las plantas", en: 9272, 15)
        }
        try? ctx.save()
    }
}
