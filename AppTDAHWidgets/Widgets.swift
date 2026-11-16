import SwiftUI
import WidgetKit

@main
struct WidgetsAppTDAH: WidgetBundle {
    var body: some Widget {
        CapturaWidget()
        LoQueVieneWidget()
    }
}

// MARK: Captura: un toque abre la app directo en el dictado (un widget no puede grabar audio).

struct EntradaSimple: TimelineEntry { let date: Date }

struct ProveedorCaptura: TimelineProvider {
    func placeholder(in context: Context) -> EntradaSimple { EntradaSimple(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (EntradaSimple) -> Void) { completion(EntradaSimple(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaSimple>) -> Void) {
        completion(Timeline(entries: [EntradaSimple(date: .now)], policy: .never))
    }
}

struct CapturaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Captura", provider: ProveedorCaptura()) { _ in VistaCapturaFamilia() }
            .configurationDisplayName("Captura")
            .description("Un toque para dictar o escribir lo que tenés en la cabeza.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

private struct VistaCapturaFamilia: View {
    @Environment(\.widgetFamily) private var familia
    var body: some View { VistaCapturaWidget(familia: familia) }
}

// MARK: Lo que viene: la próxima cosa con su cuenta regresiva.

struct EntradaLoQueViene: TimelineEntry {
    let date: Date
    let datos: LoQueViene?
}

struct ProveedorLoQueViene: TimelineProvider {
    func placeholder(in context: Context) -> EntradaLoQueViene { EntradaLoQueViene(date: .now, datos: Muestra.datos) }

    func getSnapshot(in context: Context, completion: @escaping (EntradaLoQueViene) -> Void) {
        let datos = GrupoApp.leer()
        let sirve = datos?.actual(en: .now) != nil
        completion(EntradaLoQueViene(date: .now, datos: context.isPreview && !sirve ? Muestra.datos : datos))
    }

    /// Una entrada por cada momento en que cambia lo que se muestra; la cuenta regresiva corre sola entre medio.
    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaLoQueViene>) -> Void) {
        let datos = GrupoApp.leer()
        let ahora = Date.now
        let fechas = datos?.cambios(desde: ahora) ?? [ahora]
        let entradas = fechas.map { EntradaLoQueViene(date: $0, datos: datos) }
        // Al final, o como mucho en 6 horas, vuelve a leer lo que dejó la app.
        let proxima = min((fechas.last ?? ahora).addingTimeInterval(60), ahora.addingTimeInterval(6 * 3600))
        completion(Timeline(entries: entradas, policy: .after(proxima)))
    }
}

struct LoQueVieneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LoQueViene", provider: ProveedorLoQueViene()) { e in VistaLoQueVieneFamilia(entrada: e) }
            .configurationDisplayName("Lo que viene")
            .description("La próxima cosa con su cuenta regresiva.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

private struct VistaLoQueVieneFamilia: View {
    let entrada: EntradaLoQueViene
    @Environment(\.widgetFamily) private var familia
    var body: some View { VistaLoQueVieneWidget(datos: entrada.datos, fecha: entrada.date, familia: familia) }
}

/// Lo que se ve en la galería de widgets antes de agregarlo.
enum Muestra {
    static var datos: LoQueViene {
        let ahora = Date.now
        return LoQueViene(items: [
            .init(titulo: "Llamar al banco", categoria: "tarea", inicio: ahora.addingTimeInterval(272),
                  fin: ahora.addingTimeInterval(272 + 45 * 60), lugar: "Banco", notas: "Tener a mano el número de cliente."),
            .init(titulo: "Preparar el menú semanal", categoria: "tarea", inicio: ahora.addingTimeInterval(3872),
                  fin: ahora.addingTimeInterval(3872 + 30 * 60)),
        ])
    }
}
