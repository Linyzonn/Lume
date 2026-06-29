import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var engine: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let lyrics = engine.currentTrack?.lyrics, !lyrics.isEmpty {
                    Text(lyrics)
                        .font(.title3)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Pas de paroles intégrées")
                            .font(.headline)
                        Text("Les paroles s'affichent ici quand elles sont incluses dans les métadonnées du fichier (tag « lyrics »).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 80)
                }
            }
            .navigationTitle(engine.currentTrack?.title ?? "Paroles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
