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

    // Glisser vers le bas pour fermer.
    @State private var dragOffset: CGFloat = 0
    // Couleurs d'ambiance derivees de la pochette (fond plein ecran).
    @State private var bgTop: Color = Color(red: 0.13, green: 0.13, blue: 0.17)
    @State private var bgBottom: Color = .black

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                grabber
                    .highPriorityGesture(dismissDrag)
                Spacer(minLength: 8)
                artwork
                    .highPriorityGesture(dismissDrag)
                Spacer(minLength: 16)
                trackInfo
                scrubber
                transport
                volumeSection
                bottomBar
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .environment(\.colorScheme, .dark)   // texte clair, lisible sur fond colore
            .offset(y: dragOffset)               // suit le doigt 1:1 (pas d'animation ici)
        }
        .task(id: engine.currentTrack?.id) { updateAmbiance() }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showLyrics) { LyricsView() }
        .sheet(isPresented: $showEQ) { EqualizerView() }
    }

    // MARK: - Geste de fermeture

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // On ne reagit qu'au glissement vers le bas.
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    isPresented = false
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Composants

    private var backgroundGradient: some View {
        ZStack {
            // Degrade plein ecran derive de la pochette.
            LinearGradient(colors: [bgTop, bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // Pochette floutee, subtile, pour la matiere (sans voile gris).
            if let track = engine.currentTrack, let img = library.artworkImage(for: track) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 90)
                    .opacity(0.35)
                    .ignoresSafeArea()
            }
            // Leger voile sombre en bas pour la lisibilite des controles.
            LinearGradient(colors: [.clear, .black.opacity(0.45)],
                           startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.6), value: bgTop)
    }

    private var grabber: some View {
        HStack {
            Capsule().fill(.white.opacity(0.5)).frame(width: 40, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            Button { isPresented = false } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Text(displayArtist)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // largeur bornee -> plus de debordement
            if let track = engine.currentTrack {
                FavoriteButton(track: track).font(.title2)
            }
        }
        .padding(.bottom, 12)
    }

    // Titre lisible (repli si le tag est vide).
    private var displayTitle: String {
        let t = (engine.currentTrack?.title ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Titre inconnu" : t
    }

    // Artiste principal + nombre d'artistes supplementaires (ex. "TIF +3").
    private var displayArtist: String {
        let a = (engine.currentTrack?.artist ?? "").trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return "Artiste inconnu" }
        let parts = a.split(whereSeparator: { $0 == "," || $0 == "&" || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count > 1 { return "\(parts[0]) +\(parts.count - 1)" }
        return a
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
            .tint(.white)

            HStack {
                Text((isScrubbing ? scrubValue : engine.currentTime).asTimeString)
                Spacer()
                Text(engine.duration.asTimeString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.bottom, 12)
    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button { engine.shuffleEnabled.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(engine.shuffleEnabled ? LumeTheme.accent : .white.opacity(0.7))
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
                    .foregroundStyle(engine.repeatMode == .off ? .white.opacity(0.7) : LumeTheme.accent)
            }
            .font(.title3)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
    }

    // Volume systeme (0-100 %, synchro iPhone) + boost au-dela de 100 %.
    private var volumeSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                SystemVolumeSlider()
                    .frame(height: 28)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.footnote)
                    .foregroundStyle(engine.volumeBoost > 0 ? LumeTheme.accent : .white.opacity(0.5))
                Slider(value: Binding(
                    get: { Double(engine.volumeBoost) },
                    set: { engine.volumeBoost = Float($0) }
                ), in: 0...0.5)
                .tint(LumeTheme.accent)
                Text("+\(Int((engine.volumeBoost * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(.top, 6)
    }

    private var bottomBar: some View {
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
        .foregroundStyle(.white.opacity(0.8))
    }

    private func cycleRepeat() {
        switch engine.repeatMode {
        case .off: engine.repeatMode = .all
        case .all: engine.repeatMode = .one
        case .one: engine.repeatMode = .off
        }
    }

    // MARK: - Ambiance (couleurs derivees de la pochette)

    private func updateAmbiance() {
        guard let track = engine.currentTrack,
              let img = library.artworkImage(for: track) else {
            withAnimation(.easeInOut(duration: 0.6)) {
                bgTop = Color(red: 0.13, green: 0.13, blue: 0.17)
                bgBottom = .black
            }
            return
        }
        let colors = img.ambianceColors()
        withAnimation(.easeInOut(duration: 0.6)) {
            bgTop = Color(colors.top)
            bgBottom = Color(colors.bottom)
        }
    }
}

// Curseur de volume systeme (enveloppe MPVolumeView).
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = true
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Extraction des couleurs d'ambiance depuis la pochette

extension UIImage {
    // Deux couleurs (haut / bas) tirees de la pochette, assombries pour rester
    // lisibles sous du texte blanc.
    func ambianceColors() -> (top: UIColor, bottom: UIColor) {
        let top = averageColor(upperHalf: true)?.ambianceAdjusted(maxBrightness: 0.55) ?? UIColor(white: 0.18, alpha: 1)
        let bottom = averageColor(upperHalf: false)?.ambianceAdjusted(maxBrightness: 0.28) ?? .black
        return (top, bottom)
    }

    private func averageColor(upperHalf: Bool) -> UIColor? {
        guard let ci = CIImage(image: self) else { return nil }
        let e = ci.extent
        // Repere CoreImage : origine en bas a gauche -> la moitie "haute" de l'image
        // correspond a la partie superieure en Y.
        let rect = upperHalf
            ? CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2)
            : CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 2)
        guard let f = CIFilter(name: "CIAreaAverage",
                               parameters: [kCIInputImageKey: ci,
                                            kCIInputExtentKey: CIVector(cgRect: rect)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(out, toBitmap: &px, rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255,
                       blue: CGFloat(px[2]) / 255, alpha: 1)
    }
}

extension UIColor {
    // Plafonne la luminosite (assombrit les pochettes claires) et rehausse un peu la
    // saturation pour une ambiance plus marquee.
    func ambianceAdjusted(maxBrightness: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            // Couleur non convertible (gris) : on renvoie un gris sombre.
            var w: CGFloat = 0
            getWhite(&w, alpha: &a)
            return UIColor(white: min(w, maxBrightness), alpha: 1)
        }
        return UIColor(hue: h,
                       saturation: min(1, s * 1.2 + 0.05),
                       brightness: min(b, maxBrightness),
                       alpha: 1)
    }
}
