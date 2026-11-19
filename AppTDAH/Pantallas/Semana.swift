import SwiftUI

/// "¿Qué te toca esta semana?": el turno de la semana (si alternás, ya viene elegido) y, tocando la letra de un día,
/// otro turno, libre u otro horario solo ese día. También se cuenta por voz.
struct EstaSemanaView: View {
    let paleta: Paleta
    /// Dentro de Preparar mañana, "Listo" sigue al paso siguiente.
    var alTerminar: (() -> Void)? = nil

    @PerfilVivo private var perfil
    @State private var elegido: Int?
    @State private var dictado = Dictado()
    @State private var entendido: String?
    @State private var pensando = false

    static let colorManana = RGB(0x5E8378)
    static let colorTarde = RGB(0x6E86A0)
    private static let letras = ["L", "M", "M", "J", "V", "S", "D"]
    private static let nombres = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    /// El domingo a la noche se prepara la semana que viene; si no, la que corre.
    private var lunes: Date {
        let hoy = Date.now
        let cal = Calendar.current
        let esDomingoTarde = Perfil.indiceDia(hoy) == 6 && cal.component(.hour, from: hoy) >= 17
        let base = Perfil.lunes(de: hoy)
        return esDomingoTarde ? (cal.date(byAdding: .day, value: 7, to: base) ?? base) : base
    }

    private var clave: String { Perfil.claveSemana(lunes) }

    private var semana: SemanaElegida {
        perfil.trabajo.semanas[clave] ?? SemanaElegida(turno: perfil.turno(semanaDe: lunes))
    }

    private func dia(_ i: Int) -> Date { Calendar.current.date(byAdding: .day, value: i, to: lunes) ?? lunes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(encabezado).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(paleta.secundario.color).padding(.top, 14)
                Text("¿Qué te toca esta semana?").font(.serif(27, relativoA: .title)).padding(.top, 10)
                Text("Del lunes \(Calendar.current.component(.day, from: lunes)) al domingo \(Calendar.current.component(.day, from: dia(6))).")
                    .font(.subheadline).foregroundStyle(paleta.secundario.color).padding(.top, 8)
                filaTurno.padding(.top, 22)
                if perfil.trabajo.alterna {
                    Text("Alternás cada semana: esta te toca de \(semana.turno == "m" ? "mañana" : "tarde").")
                        .font(.caption).foregroundStyle(paleta.secundario.color).padding(.top, 6).padding(.leading, 4)
                }
                Text("TOCÁ UN DÍA PARA CAMBIARLO").font(.caption2.weight(.bold)).tracking(1)
                    .foregroundStyle(paleta.secundario.color).padding(.top, 22).padding(.bottom, 8)
                dias
                if let i = elegido { panel(i).padding(.top, 10) } else {
                    Text("Los días con color trabajás; los punteados, libre. El puntito marca un día cambiado.")
                        .font(.caption).foregroundStyle(paleta.secundario.color).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .padding(.top, 10)
                }
                contame.padding(.top, 14)
                if let alTerminar {
                    Button("Listo", action: alTerminar).buttonStyle(BotonPrimario(paleta: paleta)).padding(.top, 14)
                }
                Text("Los turnos y lo demás fijo se editan en Vos › Horarios fijos.")
                    .font(.caption).foregroundStyle(paleta.secundario.color).frame(maxWidth: .infinity).padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(paleta.fondo.color.ignoresSafeArea())
        .navigationTitle("Esta semana")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { dictado.detener() }
    }

    private var encabezado: String {
        let hoy = Date.now
        return Perfil.indiceDia(hoy) == 6 ? "DOMINGO \(Calendar.current.component(.day, from: hoy)) · PARA LA SEMANA QUE VIENE" : "ESTA SEMANA"
    }

    private func guardar(_ s: SemanaElegida) { perfil.trabajo.semanas[clave] = s }

    // MARK: Turno

    private var filaTurno: some View {
        HStack {
            Text("Turno")
            Spacer()
            HStack(spacing: 2) {
                botonTurno("m", "Mañana", "sun.max", Self.colorManana)
                botonTurno("t", "Tarde", "moon", Self.colorTarde)
            }
            .padding(2)
            .background(Color.gray.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(paleta.linea.color))
    }

    private func botonTurno(_ t: String, _ nombre: String, _ icono: String, _ color: RGB) -> some View {
        let sel = semana.turno == t
        return Button {
            var s = semana
            s.turno = t
            withAnimation(.easeInOut(duration: 0.3)) { guardar(s) }
        } label: {
            Label(nombre, systemImage: icono)
                .font(.footnote.weight(sel ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(sel ? color.color : paleta.texto.color)
                .background(sel ? paleta.superficie.color : .clear, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(sel ? 0.12 : 0), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Días

    private func horario(_ i: Int) -> (inicio: Int, fin: Int)? { perfil.horarioTrabajo(dia(i)) }

    private func colorDia(_ i: Int) -> RGB? {
        guard let h = horario(i) else { return nil }
        let d = semana.dias[safe: i] ?? nil
        if let d, d.inicio == nil { return d.tipo == "m" ? Self.colorManana : Self.colorTarde }
        if d == nil {
            return semana.turno == "m" ? Self.colorManana : Self.colorTarde
        }
        return h.inicio < 12 * 60 ? Self.colorManana : Self.colorTarde
    }

    private var dias: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                let color = colorDia(i)
                let cambiado = (semana.dias[safe: i] ?? nil) != nil
                Button { withAnimation(.spring(duration: 0.3)) { elegido = elegido == i ? nil : i } } label: {
                    VStack(spacing: 1) {
                        Text(Self.letras[i]).font(.caption.weight(.bold))
                        Text("\(Calendar.current.component(.day, from: dia(i)))").font(.serif(17, relativoA: .body))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .foregroundStyle(color?.color ?? paleta.secundario.color)
                    .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        if let color {
                            RoundedRectangle(cornerRadius: 13).stroke(color.color, lineWidth: 1.5)
                        } else {
                            RoundedRectangle(cornerRadius: 13).stroke(paleta.linea.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if cambiado { Circle().fill(Dorado.borde.color).frame(width: 7, height: 7).padding(4) }
                    }
                    .offset(y: elegido == i ? -3 : 0)
                    .overlay {
                        if elegido == i { RoundedRectangle(cornerRadius: 15).stroke(paleta.primario.color, lineWidth: 2).padding(-3).offset(y: -3) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.nombres[i]) \(Calendar.current.component(.day, from: dia(i))), \(horario(i).map { Perfil.horas($0.inicio, $0.fin) } ?? "libre")")
            }
        }
    }

    private func panel(_ i: Int) -> some View {
        let h = horario(i)
        let actual: String = {
            if let d = semana.dias[safe: i] ?? nil { return d.inicio == nil ? d.tipo : "otro" }
            return h == nil ? "l" : semana.turno
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Self.nombres[i]) \(Calendar.current.component(.day, from: dia(i)))").font(.serif(20, relativoA: .title3))
                Spacer()
                Text(h.map { Perfil.horas($0.inicio, $0.fin) } ?? "libre").font(.caption).foregroundStyle(paleta.secundario.color).monospacedDigit()
            }
            HStack(spacing: 8) {
                tile("Mañana", "06 – 14", sel: actual == "m") { cambiar(i, DiaSemana(tipo: "m")) }
                tile("Tarde", "14 – 22", sel: actual == "t") { cambiar(i, DiaSemana(tipo: "t")) }
                tile("Libre", "no trabajo", sel: actual == "l") { cambiar(i, DiaSemana(tipo: "l")) }
            }
            filaHora("Entro", h?.inicio ?? 9 * 60) { nuevo in cambiar(i, DiaSemana(tipo: nuevo < 12 * 60 ? "m" : "t", inicio: nuevo, fin: max(nuevo + 60, h?.fin ?? 17 * 60))) }
            filaHora("Salgo", h?.fin ?? 17 * 60) { nuevo in cambiar(i, DiaSemana(tipo: (h?.inicio ?? 9 * 60) < 12 * 60 ? "m" : "t", inicio: h?.inicio ?? 9 * 60, fin: nuevo)) }
            if (semana.dias[safe: i] ?? nil) != nil {
                Button("Volver a como siempre") { cambiar(i, nil) }.font(.caption).foregroundStyle(paleta.secundario.color)
            }
        }
        .padding(13)
        .background(paleta.superficie.color, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(paleta.linea.color))
    }

    private func cambiar(_ i: Int, _ d: DiaSemana?) {
        var s = semana
        var lista = s.dias
        while lista.count < 7 { lista.append(nil) }
        // Elegir el turno de la semana en un día laboral es lo mismo que "como siempre".
        if let d, d.inicio == nil, d.tipo == s.turno, perfil.trabajo.dias[safe: i] == true { lista[i] = nil } else { lista[i] = d }
        s.dias = lista
        withAnimation(.easeInOut(duration: 0.25)) { guardar(s) }
    }

    private func tile(_ t: String, _ sub: String, sel: Bool, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 2) {
                Text(t).font(.subheadline)
                Text(sub).font(.caption2).foregroundStyle(paleta.secundario.color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(sel ? paleta.primario.color : paleta.linea.color, lineWidth: sel ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(paleta.texto.color)
    }

    private func filaHora(_ t: String, _ valor: Int, _ cambio: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(t).font(.subheadline)
            Spacer()
            Text(Perfil.hhmm(valor)).font(.serif(16, relativoA: .body)).monospacedDigit()
            Stepper(t, onIncrement: { cambio(min(24 * 60, valor + 30)) }, onDecrement: { cambio(max(5 * 60, valor - 30)) })
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(paleta.fondo.color, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(paleta.linea.color))
    }

    // MARK: Contame la semana

    private var contame: some View {
        Button {
            if dictado.escuchando { Task { await interpretar() } } else { entendido = nil; dictado.texto = ""; Task { await dictado.empezar() } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: dictado.escuchando ? "stop.fill" : "mic.fill")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(paleta.fondo.color)
                    .background(paleta.primario.color, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(pensando ? "Ordenando…" : (dictado.escuchando ? "Te escucho… tocá para terminar" : (entendido == nil ? "Contame la semana" : "Entendí:")))
                        .font(.subheadline.weight(.semibold))
                    Text(dictado.escuchando ? (dictado.texto.isEmpty ? "…" : dictado.texto) : (entendido ?? "“de lunes a miércoles de tarde, jueves y viernes de mañana”"))
                        .font(.caption).foregroundStyle(paleta.secundario.color).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(paleta.primario.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .foregroundStyle(paleta.texto.color)
        .disabled(pensando || !ClaveIA.hay)
        .opacity(ClaveIA.hay ? 1 : 0.5)
    }

    private func interpretar() async {
        let texto = dictado.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        dictado.detener()
        guard !texto.isEmpty else { return }
        pensando = true
        defer { pensando = false }
        do {
            let r = try await ClienteClaude.interpretarSemana(texto, manana: Perfil.horas(perfil.trabajo.manana.inicio, perfil.trabajo.manana.fin),
                                                              tarde: Perfil.horas(perfil.trabajo.tarde.inicio, perfil.trabajo.tarde.fin))
            var s = SemanaElegida(turno: r.turno)
            s.dias = (0..<7).map { i in
                guard let d = r.dias[safe: i] else { return nil }
                let a = Self.minutos(d.entra), b = Self.minutos(d.sale)
                if let a, let b { return DiaSemana(tipo: d.tipo, inicio: a, fin: b) }
                if d.tipo == r.turno && perfil.trabajo.dias[safe: i] == true { return nil }
                return DiaSemana(tipo: d.tipo)
            }
            withAnimation(.easeInOut(duration: 0.4)) { guardar(s) }
            entendido = texto
        } catch {
            entendido = error.localizedDescription
        }
    }

    static func minutos(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return p[0] * 60 + p[1]
    }
}
