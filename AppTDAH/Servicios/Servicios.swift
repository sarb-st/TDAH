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
        if t.esCita { return programarCita(t) }
        cancelarInicio(t)
        let textos = [
            (t.titulo, "Comienza ahora. Abrí para decidir."),
            (t.titulo, "Te está esperando. Abrí para decidir."),
            ("Último aviso: \(t.titulo)", "Si la descartás, cierro este slot y te pregunto cuándo.")
        ]
        let alarmas = Alarmas.disponibles
        for (i, fecha) in MotorSlots.horariosAviso(t.inicio).enumerated() where fecha > .now {
            // Con alarmas disponibles, el comienzo suena como un despertador aunque el iPhone esté en silencio.
            if alarmas {
                Alarmas.programar(id: Alarmas.id(t.uid, UInt8(i)), fecha: fecha, titulo: textos[i].0)
            } else {
                agregar(id: ids(t, "inicio", textos.count)[i], fecha: fecha, titulo: textos[i].0, cuerpo: textos[i].1)
            }
        }
    }

    /// Una cita no pide decisión: avisa cuándo salir (viaje + 10 min) o, sin viaje, 10 minutos antes.
    static func programarCita(_ t: Tarea) {
        cancelarInicio(t)
        let ids = ids(t, "inicio", 3)
        if let salida = t.salida {
            let antes = salida.addingTimeInterval(-15 * 60)
            if antes > .now { agregar(id: ids[0], fecha: antes, titulo: "En 15 min salís: \(t.titulo)", cuerpo: "Cita a las \(Formato.hora(t.inicio)). Viaje de \(t.minutosViaje) min.") }
            guard salida > .now else { return }
            if Alarmas.disponibles {
                Alarmas.programar(id: Alarmas.id(t.uid, 1), fecha: salida, titulo: "Salí ahora: \(t.titulo)")
            } else {
                agregar(id: ids[1], fecha: salida, titulo: "Salí ahora: \(t.titulo)", cuerpo: "Cita a las \(Formato.hora(t.inicio)).")
            }
        } else {
            let aviso = t.inicio.addingTimeInterval(-10 * 60)
            guard aviso > .now else { return }
            if Alarmas.disponibles {
                Alarmas.programar(id: Alarmas.id(t.uid, 1), fecha: aviso, titulo: "En 10 min: \(t.titulo)")
            } else {
                agregar(id: ids[1], fecha: aviso, titulo: "En 10 min: \(t.titulo)", cuerpo: t.lugar.isEmpty ? "Cita a las \(Formato.hora(t.inicio))." : t.lugar)
            }
        }
    }

    /// Cada noche a las 21: las citas de mañana, con la hora de salida.
    @MainActor
    static func programarResumen(_ tareas: [Tarea]) {
        guard activos else { return }
        centro.removePendingNotificationRequests(withIdentifiers: ["resumen"])
        let cal = Calendar.current
        var hoy21 = cal.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
        if hoy21 < .now { hoy21 = cal.date(byAdding: .day, value: 1, to: hoy21) ?? hoy21 }
        guard let manana = cal.date(byAdding: .day, value: 1, to: hoy21) else { return }
        let citas = tareas.filter { $0.esCita && $0.estado == .programada && cal.isDate($0.inicio, inSameDayAs: manana) }
            .sorted { $0.inicio < $1.inicio }
        guard !citas.isEmpty else { return }
        let texto = citas.map { c in
            "\(Formato.hora(c.inicio)) \(c.titulo)" + (c.salida.map { " (salí \(Formato.hora($0)))" } ?? "")
        }.joined(separator: " · ")
        agregar(id: "resumen", fecha: hoy21, titulo: "Mañana", cuerpo: texto)
    }

    static func programarFin(_ t: Tarea) {
        cancelarFin(t)
        guard let fin = t.finPrevisto else { return }
        let ids = ids(t, "fin", 2)
        let antes = fin.addingTimeInterval(-5 * 60)
        if antes > .now { agregar(id: ids[0], fecha: antes, titulo: "Quedan 5 minutos", cuerpo: t.titulo) }
        guard fin > .now else { return }
        if Alarmas.disponibles {
            Alarmas.programar(id: Alarmas.id(t.uid, 3), fecha: fin, titulo: "Terminó el tiempo: \(t.titulo)")
        } else {
            agregar(id: ids[1], fecha: fin, titulo: "Terminó el tiempo", cuerpo: "\(t.titulo). ¿Cómo seguimos?")
        }
    }

    static func cancelarInicio(_ t: Tarea) {
        centro.removePendingNotificationRequests(withIdentifiers: ids(t, "inicio", 3))
        Alarmas.cancelar((0..<3).map { Alarmas.id(t.uid, UInt8($0)) })
    }

    static func cancelarFin(_ t: Tarea) {
        centro.removePendingNotificationRequests(withIdentifiers: ids(t, "fin", 2))
        Alarmas.cancelar([Alarmas.id(t.uid, 3)])
    }
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
        var lugar: String?
        var direccion: String?
        var notas: String?
        var esCita: Bool?
        var minutosViaje: Int?
        var pasos: [CopiaPaso]
    }
    struct CopiaCaptura: Codable { var uid: UUID; var tipo: String; var texto: String; var titulo: String; var tema: String; var creada: Date; var archivada: Bool }
    struct Copia: Codable { var version = 1; var creada: Date; var tareas: [CopiaTarea]; var capturas: [CopiaCaptura]? }

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
                           lugar: t.lugar, direccion: t.direccion, notas: t.notas,
                           esCita: t.esCita, minutosViaje: t.minutosViaje,
                           pasos: t.pasosOrdenados.map { CopiaPaso(texto: $0.texto, hecho: $0.hecho, orden: $0.orden) })
            }, capturas: (try ctx.fetch(FetchDescriptor<Captura>())).map {
                CopiaCaptura(uid: $0.uid, tipo: $0.tipo, texto: $0.texto, titulo: $0.titulo, tema: $0.tema, creada: $0.creada, archivada: $0.archivada)
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
            t.lugar = c.lugar ?? ""
            t.direccion = c.direccion ?? ""
            t.notas = c.notas ?? ""
            t.esCita = c.esCita ?? false
            t.minutosViaje = c.minutosViaje ?? 0
            ctx.insert(t)
            for p in c.pasos {
                let paso = Paso(texto: p.texto, orden: p.orden, hecho: p.hecho)
                ctx.insert(paso)
                paso.tarea = t
            }
            agregadas += 1
        }
        let capturasExistentes = Set(try ctx.fetch(FetchDescriptor<Captura>()).map(\.uid))
        for c in copia.capturas ?? [] where !capturasExistentes.contains(c.uid) {
            let nueva = Captura(tipo: c.tipo, texto: c.texto, titulo: c.titulo, tema: c.tema)
            nueva.uid = c.uid
            nueva.creada = c.creada
            nueva.archivada = c.archivada
            ctx.insert(nueva)
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

    /// Guarda y actualiza el espejo en el calendario del iPhone.
    static func guardar(_ t: Tarea, ctx: ModelContext) {
        Calendario.sincronizar(t)
        guardar(ctx)
    }

    /// Las citas que ya pasaron quedan hechas solas; el inbox sin procesar se archiva a las 2 semanas.
    static func mantenimiento(ctx: ModelContext) {
        let ahora = Date.now
        if let tareas = try? ctx.fetch(FetchDescriptor<Tarea>()) {
            for t in tareas where t.esCita && t.estado == .programada
                && t.inicio.addingTimeInterval(Double(t.duracionMinutos) * 60) < ahora {
                t.estado = .terminada
            }
            Avisos.programarResumen(tareas)
        }
        if let capturas = try? ctx.fetch(FetchDescriptor<Captura>()) {
            for c in capturas where c.tipo == "inbox" && !c.archivada && c.creada < ahora.addingTimeInterval(-14 * 86_400) {
                c.archivada = true
            }
        }
        guardar(ctx)
    }

    @discardableResult
    private static func registrar(_ t: Tarea, _ resultado: String, ctx: ModelContext, ahora: Date = .now) -> Int {
        // Si el tiempo terminó y no hubo respuesta enseguida, cuenta hasta el fin previsto, no hasta ahora.
        let fin = min(ahora, t.finPrevisto.map { $0.addingTimeInterval(15 * 60) } ?? ahora)
        let minutos = t.inicioReal.map { max(0, Int((fin.timeIntervalSince($0) / 60).rounded())) } ?? 0
        ctx.insert(SlotRegistro(uidTarea: t.uid, titulo: t.titulo, inicioPlaneado: t.inicio, inicioReal: t.inicioReal,
                                fin: ahora, resultado: resultado, minutosReales: minutos))
        return minutos
    }

    static func empezar(_ t: Tarea, ctx: ModelContext) {
        t.estado = .enCurso
        t.inicioReal = .now
        t.minutosExtra = 0
        Avisos.cancelarInicio(t)
        Avisos.programarFin(t)
        guardar(t, ctx: ctx)
    }

    static func ahoraNo(_ t: Tarea, ctx: ModelContext) {
        registrar(t, "ahora no", ctx: ctx)
        t.estado = .faltaHora
        Avisos.cancelarTodo(t)
        guardar(t, ctx: ctx)
    }

    static func reprogramar(_ t: Tarea, a fecha: Date, ctx: ModelContext) {
        if t.estado == .programada { registrar(t, "sin respuesta", ctx: ctx) }
        t.inicio = fecha
        t.estado = .programada
        t.inicioReal = nil
        t.minutosExtra = 0
        Avisos.programarInicio(t)
        guardar(t, ctx: ctx)
    }

    static func archivar(_ t: Tarea, ctx: ModelContext) {
        t.estado = .archivada
        Avisos.cancelarTodo(t)
        guardar(t, ctx: ctx)
    }

    /// Devuelve los minutos de foco de este slot.
    @discardableResult
    static func terminar(_ t: Tarea, ctx: ModelContext) -> Int {
        let minutos = registrar(t, "terminada", ctx: ctx)
        t.estado = .terminada
        Avisos.cancelarTodo(t)
        guardar(t, ctx: ctx)
        return minutos
    }

    /// Una tarea archivada vuelve sin hora: la app pregunta "¿Cuándo, entonces?".
    static func restaurar(_ t: Tarea, ctx: ModelContext) {
        t.estado = .faltaHora
        t.inicioReal = nil
        t.minutosExtra = 0
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
        guardar(t, ctx: ctx)
    }

    static func borrar(_ t: Tarea, ctx: ModelContext) {
        Avisos.cancelarTodo(t)
        Calendario.borrar(t)
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
        func tarea(_ titulo: String, en segundos: Double, _ duracion: Int, conPasos: Bool = false, hechos: Int = 0,
                   lugar: String = "", notas: String = "") -> Tarea {
            let t = Tarea(titulo: titulo, inicio: ahora.addingTimeInterval(segundos), duracionMinutos: duracion)
            t.lugar = lugar
            t.notas = notas
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

        let notasBanco = "Tener a mano el número de cliente. Preguntar también por la tarjeta nueva."
        func proyectoDemo() -> Proyecto {
            let p = Proyecto(titulo: "Mudanza", deadline: ahora.addingTimeInterval(24 * 86_400))
            p.creado = ahora.addingTimeInterval(-10 * 86_400)
            ctx.insert(p)
            for (i, (titulo, dias, hecha)) in [("Elegir empresa de mudanza", -3.0, true), ("Embalar la cocina y el living", 6.0, false),
                                              ("Cambiar dirección en bancos y servicios", 14.0, false), ("Día de la mudanza", 24.0, false)].enumerated() {
                let e = Etapa(titulo: titulo, fechaObjetivo: ahora.addingTimeInterval(dias * 86_400), orden: i)
                e.cumplida = hecha
                ctx.insert(e)
                e.proyecto = p
            }
            return p
        }
        switch p {
        case "vacio":
            break
        case "cita":
            let c = tarea("Dentista", en: 50 * 60, 45, lugar: "Consultorio", notas: "Llevar la orden y la credencial.")
            c.esCita = true
            c.minutosViaje = 25
            c.direccion = "Calle Ejemplo 123"
        case "proyecto":
            let p = proyectoDemo()
            let t = tarea("Comprar cajas y cinta", en: 3 * 3600, 45)
            t.proyecto = p
            let segunda = p.etapas.first { $0.orden == 1 }
            t.etapa = segunda
            let t2 = tarea("Embalar los libros", en: 26 * 3600, 90)
            t2.proyecto = p
            t2.etapa = segunda
        case "captura":
            break
        case "lista", "calendario":
            let hecha = tarea("Responder el mail del estudio", en: -3 * 3600, 30)
            hecha.estado = .terminada
            hecha.inicioReal = hecha.inicio
            ctx.insert(SlotRegistro(uidTarea: hecha.uid, titulo: hecha.titulo, inicioPlaneado: hecha.inicio, inicioReal: hecha.inicio,
                                    fin: hecha.inicio.addingTimeInterval(32 * 60), resultado: "terminada", minutosReales: 32))
            ctx.insert(SlotRegistro(uidTarea: UUID(), titulo: "Ordenar el escritorio", inicioPlaneado: ahora.addingTimeInterval(-5400),
                                    inicioReal: nil, fin: ahora.addingTimeInterval(-5400), resultado: "ahora no", minutosReales: 0))
            tarea("Llamar al banco", en: 272, 45, conPasos: true, lugar: "Banco", notas: notasBanco)
            tarea("Preparar el menú semanal", en: 3872, 30, notas: "Mirar qué hay en la heladera antes.")
            tarea("Regar las plantas", en: 9272, 15)
            tarea("Comprar regalo de cumpleaños", en: 26 * 3600, 60, lugar: "Centro")
            let cita = tarea("Dentista", en: 27 * 3600, 45, lugar: "Consultorio")
            cita.esCita = true
            cita.minutosViaje = 25
            let p = proyectoDemo()
            tarea("Comprar cajas y cinta", en: 30 * 3600, 45).proyecto = p
            ctx.insert(Captura(tipo: "inbox", texto: "lo de Martín"))
            ctx.insert(Captura(tipo: "idea", texto: "una lámpara que respire como el círculo", titulo: "Lámpara que respira", tema: "diseño"))
            tarea("Pagar las cuentas", en: 50 * 3600, 20)
        case "decidir":
            tarea("Llamar al banco", en: -20, 45, conPasos: true, notas: notasBanco)
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
            tarea("Llamar al banco", en: 272, 45, conPasos: true, lugar: "Banco", notas: notasBanco)
            tarea("Preparar el menú semanal", en: 3872, 30)
            tarea("Regar las plantas", en: 9272, 15)
        }
        try? ctx.save()
    }
}
