import SwiftUI
import MediaPlayer

struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showEQ = false

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                grabber
                Spacer(minLength: 8)
                artwork
                Spacer(minLength: 16)
                trackInfo
                scrubber
                transport
                bottomBar
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showLyrics) { LyricsView() }
        .sheet(isPresented: $showEQ) { EqualizerView() }
    }

    // MARK: - Composants

    private var backgroundGradient: some View {
        ZStack {
            if let track = engine.currentTrack, let img = library.artworkImage(for: track) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.55)
                    .ignoresSafeArea()
            }
            LinearGradient(colors: [LumeTheme.accent.opacity(0.35), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
        }
    }

    private var grabber: some View {
        HStack {
            Capsule().fill(.secondary).frame(width: 40, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Button { isPresented = false } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture { isPresented = false }
    }

    private var artwork: some View {
        ArtworkView(track: engine.currentTrack, size: artworkSize, corner: 16)
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            .scaleEffect(engine.isPlaying ? 1.0 : 0.86)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: engine.isPlaying)
    }

    private var artworkSize: CGFloat {
        min(UIScreen.main.bounds.width - 56, 360)
    }

    private var trackInfo: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTrack?.title ?? "—")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text(engine.currentTrack?.artist ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let track = engine.currentTrack {
                FavoriteButton(track: track).font(.title2)
            }
        }
        .padding(.bottom, 12)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { isScrubbing ? scrubValue : engine.currentTime },
                set: { scrubValue = $0 }
            ), in: 0...max(1, engine.duration), onEditingChanged: { editing in
                isScrubbing = editing
                if !editing { engine.seek(to: scrubValue) }
            })
            .tint(LumeTheme.accent)

            HStack {
                Text((isScrubbing ? scrubValue : engine.currentTime).asTimeString)
                Spacer()
                Text(engine.duration.asTimeString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button { engine.shuffleEnabled.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(engine.shuffleEnabled ? LumeTheme.accent : .secondary)
            }
            .font(.title3)

            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .font(.title)

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }

            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
            }
            .font(.title)

            Button { cycleRepeat() } label: {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(engine.repeatMode == .off ? .secondary : LumeTheme.accent)
            }
            .font(.title3)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            // Volume systeme.
            SystemVolumeSlider()
                .frame(height: 28)

            HStack(spacing: 44) {
                Button { showLyrics = true } label: {
                    Image(systemName: "quote.bubble")
                }
                Button { showEQ = true } label: {
                    Image(systemName: "slider.vertical.3")
                }
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    private func cycleRepeat() {
        switch engine.repeatMode {
        case .off: engine.repeatMode = .all
        case .all: engine.repeatMode = .one
        case .one: engine.repeatMode = .off
        }
    }
}

// Curseur de volume systeme (enveloppe MPVolumeView).
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = true
        v.tintColor = UIColor(LumeTheme.accent)
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
