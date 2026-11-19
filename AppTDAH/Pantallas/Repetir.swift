import SwiftUI

/// Cómo se repite una tarea: se dicta ("contámelo como te salga") o se elige; abajo, las próximas seis semanas
/// con los días que se encienden y cuántas veces van a ser.
struct RepetirView: View {
    @Binding var regla: Regla?
    let titulo: String
    let duracion: Int

    @Environment(\.dismiss) private var cerrar
    @Environment(\.paleta) private var paleta
    @State private var r = Regla()
    @State private var dictado = Dictado()
    @State private var pensando = false
    @State private var escuchado = ""
    @State private var eligiendoFecha = false

    private let letras = ["L", "M", "M", "J", "V", "S", "D"]
    private let verde = RGB(0x7FA383)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    tarjetaTarea
                    dictar
                    if !escuchado.isEmpty {
                        Text("“\(escuchado)”").font(.serifItalica(15, relativoA: .subheadline)).padding(.horizontal, 2)
                    }
                    modos
                    switch r.modo {
                    case "dias": diasSemana
                    case "cada": cadaTanto
                    case "mes":
                        filaStepper(texto: "El día \(r.diaMes) de cada mes") { r.diaMes = max(1, $0 ? r.diaMes + 1 : r.diaMes - 1); r.diaMes = min(28, r.diaMes) }
                    default: EmptyView()
                    }
                    filaHora
                    Text("HASTA CUÁNDO").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 8)
                    hastaCuando
                    detalleHasta
                    calendario
                    resumen
                }
                .padding(20)
            }
            .background(paleta.fondo.color.ignoresSafeArea())
            .navigationTitle("Se repite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if regla != nil { Button("No se repite") { regla = nil; cerrar() } } else { Button("Cancelar") { cerrar() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { regla = r; cerrar() } }
            }
            .sheet(isPresented: $eligiendoFecha) {
                VStack {
                    DatePicker("Hasta", selection: Binding(get: { r.fechaFin ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)! },
                                                           set: { r.fechaFin = $0 }),
                               in: Date.now..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Button("Listo") { eligiendoFecha = false }.buttonStyle(BotonPrimario(paleta: paleta))
                }
                .padding(20)
                .presentationDetents([.medium, .large])
                .tint(paleta.primario.color)
            }
        }
        .tint(paleta.primario.color)
        .onAppear { if let regla { r = regla } }
        .onDisappear { dictado.detener() }
    }

    private var tarjetaTarea: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("TAREA · \(Formato.minutos(duracion))").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Categoria.tarea.texto(en: paleta))
            Text(titulo.isEmpty ? "Esta tarea" : titulo).font(.serif(19, relativoA: .headline))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.leading, 19).padding(.trailing, 14)
        .background(paleta.superficie.color)
        .overlay(alignment: .leading) { Rectangle().fill(Categoria.tarea.rgb.color).frame(width: 6) }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color))
    }

    private var dictar: some View {
        Button {
            if dictado.escuchando { Task { await interpretar() } } else { dictado.texto = ""; Task { await dictado.empezar() } }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if pensando { ProgressView().tint(paleta.fondo.color) } else { Image(systemName: dictado.escuchando ? "stop.fill" : "mic.fill") }
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(paleta.fondo.color)
                .background(paleta.primario.color, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(dictado.escuchando ? "Te escucho… tocá para terminar" : "Contámelo como te salga").font(.subheadline.weight(.semibold))
                    Text(dictado.escuchando ? (dictado.texto.isEmpty ? "…" : dictado.texto) : "o tocá las opciones de abajo")
                        .font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(paleta.primario.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .foregroundStyle(paleta.texto.color)
        .disabled(!ClaveIA.hay || pensando)
    }

    private var modos: some View {
        HStack(spacing: 6) {
            modo("dia", "Todos los días", "sun.max")
            modo("dias", "Algunos días", "circle.grid.3x3")
            modo("cada", "Cada tanto", "arrow.triangle.2.circlepath")
            modo("mes", "Una vez por mes", "calendar")
        }
    }

    private func modo(_ m: String, _ t: String, _ icono: String) -> some View {
        let sel = r.modo == m
        return Button { withAnimation { r.modo = m } } label: {
            VStack(spacing: 4) {
                Image(systemName: icono).font(.system(size: 17))
                Text(t).font(.caption2).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(sel ? paleta.fondo.color : paleta.texto.color)
            .background(sel ? paleta.primario.color : paleta.superficie.color, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? paleta.primario.color : paleta.linea.color))
        }
        .buttonStyle(.plain)
    }

    private var diasSemana: some View {
        HStack {
            ForEach(0..<7, id: \.self) { i in
                Button { r.dias[i].toggle() } label: {
                    Text(letras[i]).font(.subheadline)
                        .frame(width: 36, height: 36)
                        .foregroundStyle(r.dias[i] ? .white : paleta.texto.color)
                        .background(r.dias[i] ? verde.color : paleta.superficie.color, in: Circle())
                        .overlay(Circle().stroke(r.dias[i] ? verde.color : paleta.linea.color))
                }
                .buttonStyle(.plain)
                if i < 6 { Spacer(minLength: 0) }
            }
        }
    }

    private var cadaTanto: some View {
        let unidad = r.cada == 1 ? (r.unidad == "dias" ? "día" : "semana") : (r.unidad == "dias" ? "días" : "semanas")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 0) {
                    Text("Cada ")
                    Text("\(r.cada)").fontWeight(.semibold).monospacedDigit().frame(minWidth: 24)
                    Text(" \(unidad)")
                }
                .font(.body)
                Spacer()
                Stepper("Cada", value: $r.cada, in: 1...12).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
            Picker("Unidad", selection: $r.unidad) {
                Text("días").tag("dias")
                Text("semanas").tag("semanas")
            }
            .pickerStyle(.segmented)
            Text(r.cada == 1 ? (r.unidad == "dias" ? "Es lo mismo que todos los días." : "Una vez por semana, el mismo día.")
                 : "La hacés una vez y la siguiente es \(r.cada) \(unidad) después.")
                .font(.caption).foregroundStyle(paleta.secundario.color)
        }
    }

    private func filaStepper(texto: String, _ cambio: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(texto)
            Spacer()
            Stepper(texto, onIncrement: { cambio(true) }, onDecrement: { cambio(false) }).labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private var filaHora: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("A qué hora")
                Text("Dura \(Formato.minutos(duracion))").font(.caption).foregroundStyle(paleta.secundario.color)
            }
            Spacer()
            Text(Perfil.hhmm(r.hora)).font(.serif(19, relativoA: .title3)).monospacedDigit()
            Stepper("Hora", onIncrement: { r.hora = min(23 * 60 + 30, r.hora + 30) }, onDecrement: { r.hora = max(5 * 60, r.hora - 30) })
                .labelsHidden()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private var hastaCuando: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            hasta("siempre", "Siempre")
            hasta("meses", "Unos meses")
            hasta("fecha", "Hasta una fecha")
            hasta("veces", "Unas veces")
        }
    }

    private func hasta(_ h: String, _ t: String) -> some View {
        let sel = r.hasta == h
        return Button { withAnimation { r.hasta = h; if h == "fecha" && r.fechaFin == nil { r.fechaFin = Calendar.current.date(byAdding: .month, value: 1, to: .now) } } } label: {
            Text(t).font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(sel ? paleta.primario.color : paleta.linea.color, lineWidth: sel ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(paleta.texto.color)
    }

    @ViewBuilder
    private var detalleHasta: some View {
        switch r.hasta {
        case "meses":
            HStack {
                Text("Durante \(r.meses) \(r.meses == 1 ? "mes" : "meses")")
                Spacer()
                Stepper("Meses", value: $r.meses, in: 1...12).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
        case "fecha":
            HStack {
                Text("Hasta el")
                Spacer()
                Button((r.fechaFin ?? .now).formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es")))) { eligiendoFecha = true }
                    .font(.subheadline)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.gray.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(paleta.texto.color)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
        case "veces":
            HStack {
                Text("\(r.veces) veces")
                Spacer()
                Stepper("Veces", value: $r.veces, in: 1...60).labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
        default:
            Text("Sin fecha de fin. La podés frenar cuando quieras.").font(.caption).foregroundStyle(paleta.secundario.color)
        }
    }

    /// Seis semanas desde este lunes, con los días que se encienden.
    private var calendario: some View {
        let cal = Calendar.current
        let lunes = Perfil.lunes(de: .now)
        let hoy = cal.startOfDay(for: .now)
        let veces = Set(r.ocurrencias(desde: .now, limite: 60).map { cal.startOfDay(for: $0) })
        return VStack(spacing: 4) {
            HStack { ForEach(0..<7, id: \.self) { i in Text(letras[i]).font(.system(size: 10, weight: .bold)).foregroundStyle(paleta.secundario.color).frame(maxWidth: .infinity) } }
            ForEach(0..<6, id: \.self) { semana in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let dia = cal.date(byAdding: .day, value: semana * 7 + d, to: lunes) ?? lunes
                        let si = veces.contains(dia)
                        Text("\(cal.component(.day, from: dia))")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .foregroundStyle(si ? .white : paleta.secundario.color)
                            .background(si ? verde.color : .clear, in: Circle())
                            .overlay { if dia == hoy { Circle().stroke(paleta.primario.color, lineWidth: 1.5) } }
                            .opacity(dia < hoy ? 0.35 : 1)
                    }
                }
            }
        }
        .padding(10)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.linea.color))
        .animation(.spring(duration: 0.35), value: r)
    }

    private var resumen: some View {
        let total = r.hasta == "siempre" ? nil : r.ocurrencias(desde: .now).count
        let fin: String = {
            switch r.hasta {
            case "siempre": return "sin fecha de fin"
            case "veces": return "\(r.veces) veces"
            default: return r.ultimoDia().map { "hasta el " + $0.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es"))) } ?? ""
            }
        }()
        return HStack(spacing: 12) {
            Text(total.map(String.init) ?? "∞")
                .font(.serif(total == nil ? 28 : 24, relativoA: .title))
                .frame(width: 58, height: 58)
                .foregroundStyle(RGB(0x3E6B47).color)
                .background(Paleta.blancoCalido.color, in: Circle())
                .overlay(Circle().stroke(RGB(0xABC3A6).color.opacity(0.5), lineWidth: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.resumen).font(.serif(16.5, relativoA: .body))
                Text(fin + (total.map { r.hasta == "veces" ? "" : " · \($0) veces" } ?? "")).font(.caption).foregroundStyle(paleta.secundario.color)
            }
        }
        .padding(.top, 4)
    }

    private func interpretar() async {
        let texto = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        dictado.detener()
        guard !texto.isEmpty else { return }
        escuchado = texto
        pensando = true
        defer { pensando = false }
        guard let ia = try? await ClienteClaude.interpretarRepeticion(texto) else { return }
        withAnimation {
            r.modo = ia.modo
            if ia.dias.count == 7 { r.dias = ia.dias }
            if ia.cada > 0 { r.cada = ia.cada }
            r.unidad = ia.unidad
            if ia.dia_mes > 0 { r.diaMes = ia.dia_mes }
            if let h = EstaSemanaView.minutos(ia.hora) { r.hora = h }
            r.hasta = ia.hasta
            if ia.meses > 0 { r.meses = ia.meses }
            if let f = FechasIA.dia(ia.fecha) { r.fechaFin = f }
            if ia.veces > 0 { r.veces = ia.veces }
        }
    }
}
