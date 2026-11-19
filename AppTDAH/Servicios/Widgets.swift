import Foundation
import WidgetKit

/// Le deja anotado al widget "Lo que viene" lo próximo y le avisa que se actualice.
enum Widgets {
    @MainActor private static var ultimo: LoQueViene?
    @MainActor private static var avisoSinGrupo = false

    /// Lo próximo, como lo ve el widget: lo que está en curso y las próximas tareas y citas.
    static func datos(_ tareas: [Tarea], ahora: Date) -> LoQueViene {
        let enCurso = tareas.filter { $0.estado == .enCurso }
        let siguientes = MotorSlots.proximas(tareas, ahora: ahora, cantidad: 8)
        // Una tarea que llegó a su hora sin decisión todavía se ve un rato ("es la hora").
        let aLaHora = tareas.filter {
            $0.estado == .programada && !$0.esCita && $0.inicio <= ahora
                && ahora.timeIntervalSince($0.inicio) < LoQueViene.ventanaDeLaHora
        }
        return LoQueViene(items: (enCurso + aLaHora + siguientes).map(item))
    }

    static func item(_ t: Tarea) -> LoQueViene.Item {
        let inicio = t.inicioReal ?? t.inicio
        let fin = t.finPrevisto ?? inicio.addingTimeInterval(Double(t.duracionMinutos) * 60)
        let notas = t.notas.trimmingCharacters(in: .whitespacesAndNewlines)
        var i = LoQueViene.Item(titulo: t.titulo, categoria: t.categoria.rawValue, inicio: inicio, fin: fin,
                                enCurso: t.estado == .enCurso, salida: t.salida,
                                lugar: t.lugar, notas: notas.count > 140 ? String(notas.prefix(140)) + "…" : notas)
        i.tituloCorto = t.tituloCorto.isEmpty ? nil : t.tituloCorto
        let pendientes = t.pasosOrdenados.filter { !$0.hecho }.map(\.texto)
        i.pasos = pendientes.isEmpty ? nil : Array(pendientes.prefix(5))
        i.importante = t.importante ? true : nil
        if let p = t.proyecto {
            i.proyecto = p.titulo
            i.proyectoInicio = p.inicioEfectivo
            i.proyectoFin = p.deadline
        }
        return i
    }

    @MainActor
    static func actualizar(_ tareas: [Tarea]) {
        guard DatosDemo.pantalla == nil else { return }
        let nuevos = datos(tareas, ahora: .now)
        guard nuevos != ultimo else { return }
        if GrupoApp.guardar(nuevos) {
            ultimo = nuevos
            CarruselWidget.indice = 0
            WidgetCenter.shared.reloadAllTimelines()
        } else if !avisoSinGrupo {
            avisoSinGrupo = true
            Registro.anotar("Widgets: no se pudo escribir en la carpeta compartida (\(GrupoApp.identificador)).")
        }
    }

    static var estado: String {
        "Widgets: \(GrupoApp.carpeta == nil ? "sin carpeta compartida" : "OK") (\(GrupoApp.identificador))"
    }
}
