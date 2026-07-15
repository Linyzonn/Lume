import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var engine: PlayerEngine
    var onTap: () -> Void
    // Appui long : acces direct a la file d'attente sans ouvrir le lecteur.
    @State private var showQueue = false

    var body: some View {
        if let track = engine.currentTrack {
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 44, corner: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // VoiceOver : le titre/artiste est l'element qui ouvre le
                // lecteur plein ecran (les boutons restent independants).
                .accessibilityElement(children: .combine)
                .accessibilityLabel("En lecture : \(track.title), \(track.artist)")
                .accessibilityHint("Ouvre le lecteur en plein écran")
                .accessibilityAddTraits(.isButton)
                Spacer(minLength: 4)

                Button {
                    Haptics.light()
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Lecture")

                Button {
                    Haptics.light()
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Morceau suivant")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottom) {
                // Fine barre de progression : sous-vue isolee qui observe
                // engine.progress -> seule cette barre se re-rend 4x/s,
                // pas tout le mini-lecteur ni le reste de l'interface.
                MiniProgressLine(progress: engine.progress)
                    .padding(.horizontal, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture {
                Haptics.light()
                showQueue = true
            }
            .sheet(isPresented: $showQueue) { QueueView() }
        }
    }

}

// Barre de progression du mini-lecteur (voir PlaybackProgress dans PlayerEngine).
private struct MiniProgressLine: View {
    @ObservedObject var progress: PlaybackProgress

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LumeTheme.accent)
                .frame(width: geo.size.width * fraction, height: 2)
        }
        .frame(height: 2)
    }

    private var fraction: Double {
        guard progress.duration > 0 else { return 0 }
        return min(1, max(0, progress.time / progress.duration))
    }
}
