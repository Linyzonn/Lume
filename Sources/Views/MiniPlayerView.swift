import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var engine: PlayerEngine
    var onTap: () -> Void

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
                Spacer(minLength: 4)

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Lecture")

                Button {
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
                // Fine barre de progression.
                GeometryReader { geo in
                    Rectangle()
                        .fill(LumeTheme.accent)
                        .frame(width: geo.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
    }

    private var progress: Double {
        guard engine.duration > 0 else { return 0 }
        return min(1, max(0, engine.currentTime / engine.duration))
    }
}
