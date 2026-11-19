import SwiftUI
import MapKit
import SwiftData

/// Sugerencias de Mapas mientras se escribe un lugar: así no hay que tipear todo y se corrigen errores de tipeo.
@Observable
final class BuscadorLugar: NSObject, MKLocalSearchCompleterDelegate {
    var resultados: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completador = MKLocalSearchCompleter()
    @ObservationIgnored private var conRegion = false

    override init() {
        super.init()
        completador.delegate = self
        completador.resultTypes = [.address, .pointOfInterest]
    }

    @MainActor
    func buscar(_ texto: String) {
        let limpio = texto.trimmingCharacters(in: .whitespaces)
        guard limpio.count >= 3 else {
            resultados = []
            completador.cancel()
            return
        }
        if !conRegion {
            conRegion = true
            Task { @MainActor in
                if let r = await Viaje.shared.regionSugerida() { completador.region = r }
                completador.queryFragment = limpio
            }
        }
        completador.queryFragment = limpio
    }

    func limpiar() {
        resultados = []
        completador.cancel()
    }

    func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        resultados = Array(c.results.prefix(4))
    }

    func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {
        resultados = []
    }
}

/// Campo "Lugar" con sugerencias; al elegir una, completa también la dirección.
struct CampoLugar: View {
    @Binding var lugar: String
    @Binding var direccion: String
    var placeholder = "Lugar"

    @State private var buscador = BuscadorLugar()
    @State private var recienElegido = false
    @FocusState private var enfocado: Bool
    @Environment(\.paleta) private var paleta

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $lugar)
                .focused($enfocado)
                .onChange(of: lugar) { _, nuevo in
                    if recienElegido { recienElegido = false; return }
                    if enfocado { buscador.buscar(nuevo) }
                }
                .onChange(of: enfocado) { _, foco in if !foco { buscador.limpiar() } }
            ForEach(buscador.resultados, id: \.self) { r in
                Button { elegir(r) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mappin.circle").foregroundStyle(paleta.primario.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(.subheadline).foregroundStyle(paleta.texto.color)
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle).font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func elegir(_ r: MKLocalSearchCompletion) {
        recienElegido = true
        lugar = r.title
        direccion = r.subtitle.isEmpty ? r.title : "\(r.title), \(r.subtitle)"
        buscador.limpiar()
        enfocado = false
    }
}

/// La salida hacia una cita se calcula desde donde estás. Cada vez que se abre la app se revisan las citas
/// de las próximas 24 horas y, si el viaje cambió, se reprograman los avisos.
@MainActor
enum Salidas {
    private static var ultima: Date?

    static func recalcular(_ ctx: ModelContext) {
        guard DatosDemo.pantalla == nil else { return }
        if let u = ultima, Date.now.timeIntervalSince(u) < 10 * 60 { return }
        ultima = .now
        guard let tareas = try? ctx.fetch(FetchDescriptor<Tarea>()) else { return }
        let ahora = Date.now
        let citas = tareas.filter { t in
            t.esCita && t.estado == .programada && t.inicio > ahora && t.inicio < ahora.addingTimeInterval(86_400)
                && !(t.direccion.isEmpty && t.lugar.isEmpty)
        }
        guard !citas.isEmpty else { return }
        Task { @MainActor in
            for t in citas {
                guard let m = await Viaje.shared.minutos(hasta: t.direccion.isEmpty ? t.lugar : t.direccion, medio: t.medioViaje) else { continue }
                if abs(m - t.minutosViaje) >= 3 {
                    t.minutosViaje = m
                    Avisos.programarCita(t)
                    Calendario.sincronizar(t)
                    Registro.anotar("Salida recalculada para una cita (\(m) min de viaje).")
                }
            }
            Acciones.guardar(ctx)
        }
    }
}
