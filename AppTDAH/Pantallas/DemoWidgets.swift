import SwiftUI
import WidgetKit

/// Solo para las capturas del simulador (`-demo widgets`): los widgets como se ven en la pantalla de inicio
/// y en la de bloqueo, con datos de muestra.
struct DemoWidgetsView: View {
    let ahora: Date
    @Environment(\.colorScheme) private var esquema

    private var tarea: LoQueViene {
        LoQueViene(items: [
            .init(titulo: "Llamar al banco", categoria: "tarea", inicio: ahora.addingTimeInterval(272),
                  fin: ahora.addingTimeInterval(272 + 45 * 60), lugar: "Banco",
                  notas: "Tener a mano el número de cliente. Preguntar por la tarjeta nueva."),
            .init(titulo: "Preparar el menú semanal", categoria: "tarea", inicio: ahora.addingTimeInterval(3872),
                  fin: ahora.addingTimeInterval(3872 + 30 * 60)),
        ])
    }

    private var proyecto: LoQueViene {
        LoQueViene(items: [
            .init(titulo: "Embalar los libros", categoria: "proyecto", inicio: ahora.addingTimeInterval(50 * 60),
                  fin: ahora.addingTimeInterval(140 * 60), notas: "Empezar por el estante del living.",
                  proyecto: "Mudanza", proyectoInicio: ahora.addingTimeInterval(-6 * 86_400),
                  proyectoFin: ahora.addingTimeInterval(9 * 86_400)),
            .init(titulo: "Dentista", categoria: "cita", inicio: ahora.addingTimeInterval(26 * 3600),
                  fin: ahora.addingTimeInterval(26 * 3600 + 45 * 60)),
        ])
    }

    private var cita: LoQueViene {
        LoQueViene(items: [
            .init(titulo: "Dentista", categoria: "cita", inicio: ahora.addingTimeInterval(80 * 60),
                  fin: ahora.addingTimeInterval(125 * 60), salida: ahora.addingTimeInterval(38 * 60), lugar: "Consultorio"),
        ])
    }

    var body: some View {
        let c = ColoresWidget.para(esquema)
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                marco(VistaCapturaWidget(familia: .systemSmall), ancho: 158, c: c)
                marco(VistaLoQueVieneWidget(datos: tarea, fecha: ahora, familia: .systemSmall), ancho: 158, c: c)
            }
            marco(VistaLoQueVieneWidget(datos: proyecto, fecha: ahora, familia: .systemMedium), ancho: 330, c: c)
            marco(VistaCapturaWidget(familia: .systemMedium), ancho: 330, c: c)
            HStack(spacing: 12) {
                bloqueo(VistaLoQueVieneWidget(datos: cita, fecha: ahora, familia: .accessoryRectangular), ancho: 170, alto: 72)
                bloqueo(VistaCapturaWidget(familia: .accessoryCircular), ancho: 72, alto: 72)
            }
            .padding(14)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func marco(_ v: some View, ancho: CGFloat, c: ColoresWidget) -> some View {
        v.padding(16)
            .frame(width: ancho, height: 158)
            .background(c.fondo, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.linea))
    }

    private func bloqueo(_ v: some View, ancho: CGFloat, alto: CGFloat) -> some View {
        v.frame(width: ancho, height: alto).foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
}
