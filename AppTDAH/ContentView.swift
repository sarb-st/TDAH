import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(Textos.saludo)
                .font(.largeTitle)
                .bold()

            Text("Compilada el")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(Textos.fechaDeCompilacion(timestamp: BuildInfo.timestamp))

            if let commit = BuildInfo.commit {
                Text("Versión \(commit)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

#Preview {
    ContentView()
}
