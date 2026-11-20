import SwiftUI
import WidgetKit

/// Solo para las capturas del simulador (`-demo widgets`): los widgets como se ven en la pantalla de inicio
/// y en la de bloqueo, con datos de muestra.
struct DemoWidgetsView: View {
    let ahora: Date
    @Environment(\.colorScheme) private var esquema

    private var tarea: LoQueViene {
        LoQueViene(items: [
            .init(titulo: "Llamar al banco por la tarjeta nueva y el cambio de dirección", categoria: "tarea", inicio: ahora.addingTimeInterval(272),
                  fin: ahora.addingTimeInterval(272 + 45 * 60), lugar: "Banco",
                  notas: "Tener a mano el número de cliente. Preguntar por la tarjeta nueva.",
                  tituloCorto: "Banco: tarjeta y dirección", pasos: ["Buscar el número de cliente", "Llamar y pedir la tarjeta", "Avisar el cambio de dirección"]),
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

    /// El grande con pasos, lugar y nota, y varias cosas después.
    private var grande: LoQueViene {
        LoQueViene(items: [
            .init(titulo: "Cocinar para congelar", categoria: "tarea", inicio: ahora.addingTimeInterval(506),
                  fin: ahora.addingTimeInterval(506 + 60 * 60), lugar: "Casa", notas: "Sacar el freezer a las 10",
                  pasos: ["Milanesas", "Nuggets", "Croquetas de arroz"]),
            .init(titulo: "Facturas veterinaria al seguro", categoria: "tarea", inicio: ahora.addingTimeInterval(74 * 60),
                  fin: ahora.addingTimeInterval(104 * 60)),
            .init(titulo: "Chequear respuesta de la asociación", categoria: "tarea", inicio: ahora.addingTimeInterval(150 * 60),
                  fin: ahora.addingTimeInterval(180 * 60), importante: true),
            .init(titulo: "Dentista", categoria: "cita", inicio: ahora.addingTimeInterval(300 * 60),
                  fin: ahora.addingTimeInterval(345 * 60)),
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
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    marco(VistaCapturaWidget(familia: .systemSmall), ancho: 158, alto: 158, c: c)
                    marco(VistaLoQueVieneWidget(datos: cita, fecha: ahora, familia: .systemSmall, indice: 0), ancho: 158, alto: 158, c: c, margen: false)
                }
                marco(VistaEscribirWidget(familia: .systemMedium), ancho: 330, alto: 158, c: c)
                marco(VistaLoQueVieneWidget(datos: tarea, fecha: ahora, familia: .systemMedium, indice: 0), ancho: 330, alto: 158, c: c, margen: false)
                marco(VistaLoQueVieneWidget(datos: grande, fecha: ahora, familia: .systemLarge, indice: 0), ancho: 345, alto: 362, c: c, margen: false)
                marco(VistaLoQueVieneWidget(datos: proyecto, fecha: ahora, familia: .systemLarge, indice: 0), ancho: 345, alto: 362, c: c, margen: false)
                HStack(spacing: 12) {
                    bloqueo(VistaLoQueVieneWidget(datos: cita, fecha: ahora, familia: .accessoryRectangular), ancho: 170, alto: 72)
                    bloqueo(VistaCapturaWidget(familia: .accessoryCircular), ancho: 72, alto: 72)
                }
                .padding(14)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(.top, 50)
            .frame(maxWidth: .infinity)
        }
    }

    private func marco(_ v: some View, ancho: CGFloat, alto: CGFloat, c: ColoresWidget, margen: Bool = true) -> some View {
        v.padding(margen ? 16 : 0)
            .frame(width: ancho, height: alto)
            .background(c.fondo, in: RoundedRectangle(cornerRadius: 22))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.linea))
    }

    private func bloqueo(_ v: some View, ancho: CGFloat, alto: CGFloat) -> some View {
        v.frame(width: ancho, height: alto).foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
}
