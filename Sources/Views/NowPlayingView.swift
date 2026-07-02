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

    @State private var dragOffset: CGFloat = 0
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
                progressBar
                transport
                volumeSection
                bottomBar
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .environment(\.colorScheme, .dark)
            .offset(y: dragOffset)
        }
        .task(id: engine.currentTrack?.id) { updateAmbiance() }
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(isPresented: $showLyrics) { LyricsView() }
        .sheet(isPresented: $showEQ) { EqualizerView() }
    }

    // MARK: - Fermeture par glissement (coordonnees globales => pas de tremblement)

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                if value.translation.height > 0 { dragOffset = value.translation.height }
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    isPresented = false
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Fond

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if let track = engine.currentTrack, let img = library.artworkImage(for: track) {
                // CRITIQUE : une Image .scaledToFill() SANS frame ni clip prend la
                // taille necessaire pour couvrir (ex. 852x852 pour une pochette
                // carree sur un ecran 393x852) et GONFLE toute la mise en page :
                // titre pousse hors ecran a gauche, barres qui debordent, etc.
                // On la contraint donc exactement a la taille de l'ecran.
                GeometryReader { geo in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 90)
                        .opacity(0.35)
                }
                .ignoresSafeArea()
            }
            // Voile sombre progressif : garantit que titre / temps / boutons (texte blanc)
            // restent lisibles meme quand la pochette est tres claire (ex. fond blanc).
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.35), .black.opacity(0.82)],
                           startPoint: .top, endPoint: .bottom)
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
        .overlay(alignment: .center) {
            Text("v12")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(LumeTheme.accent))
                .offset(y: 26)
        }
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

    private var artworkSize: CGFloat { min(UIScreen.main.bounds.width - 96, 300) }

    // MARK: - Titre / artiste

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                // NOTE : ne PAS remettre .fixedSize ici. Combine avec lineLimit,
                // il faisait deborder le texte hors de l'ecran (on voyait la fin
                // du titre depasser sur le bord gauche).
                Text(displayTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .layoutPriority(1)
            if let track = engine.currentTrack {
                FavoriteButton(track: track).font(.title2).foregroundStyle(.white)
            }
        }
        .clipped()
        .padding(.bottom, 12)
    }

    private var displayTitle: String {
        let t = (engine.currentTrack?.title ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Titre inconnu" : t
    }

    private var displayArtist: String {
        // On affiche l'artiste TEL QUEL. L'ancien decoupage sur "," "&" "/"
        // massacrait les noms legitimes : "AC/DC" -> "AC +1",
        // "Tyler, The Creator" -> "Tyler +1", "Earth, Wind & Fire" -> "Earth +2".
        let a = (engine.currentTrack?.artist ?? "").trimmingCharacters(in: .whitespaces)
        return a.isEmpty ? "Artiste inconnu" : a
    }

    // MARK: - Barre de progression (maison, fiable)

    private var progressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let value = isScrubbing ? scrubValue : engine.currentTime
                let frac = engine.duration > 0 ? CGFloat(value / engine.duration) : 0
                let clamped = max(0, min(1, frac))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                    Capsule().fill(.white).frame(width: w * clamped, height: 5)
                    Circle().fill(.white)
                        .frame(width: 15, height: 15)
                        .shadow(radius: 2)
                        .offset(x: (w - 15) * clamped)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard engine.duration > 0 else { return }
                            isScrubbing = true
                            let p = min(max(0, g.location.x / w), 1)
                            scrubValue = Double(p) * engine.duration
                        }
                        .onEnded { _ in
                            guard engine.duration > 0 else { return }
                            engine.seek(to: scrubValue)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text((isScrubbing ? scrubValue : engine.currentTime).asTimeString)
                Spacer()
                Text(engine.duration.asTimeString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.bottom, 10)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 36) {
            Button { engine.shuffleEnabled.toggle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(engine.shuffleEnabled ? LumeTheme.accent : .white.opacity(0.7))
            }
            .font(.title3)

            Button { engine.previous() } label: { Image(systemName: "backward.fill") }
                .font(.title)

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }

            Button { engine.next() } label: { Image(systemName: "forward.fill") }
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

    // MARK: - Volume systeme (le boost est desormais dans le panneau « Son »)

    private var volumeSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
            SystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            Image(systemName: "speaker.wave.3.fill")
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 44) {
            Button { showLyrics = true } label: { Image(systemName: "quote.bubble") }
            Button { showEQ = true } label: { Image(systemName: "slider.vertical.3") }
            Button { showQueue = true } label: { Image(systemName: "list.bullet") }
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

    // MARK: - Ambiance (couleurs depuis la pochette)

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
// Deux pieges corriges ici :
//  1. showsRouteButton est deprecie et inserait un bouton AirPlay DANS la vue,
//     qui ecrasait / decalait le slider dans ses 34 pt de hauteur.
//  2. Un frame initial .zero fait parfois apparaitre le slider invisible ou
//     mal positionne au premier affichage -> on donne un frame non nul.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 280, height: 34))
        v.tintColor = .white
        if let slider = v.subviews.compactMap({ $0 as? UISlider }).first {
            slider.minimumTrackTintColor = .white
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        }
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Couleurs d'ambiance depuis la pochette

extension UIImage {
    func ambianceColors() -> (top: UIColor, bottom: UIColor) {
        let top = averageColor(upperHalf: true)?.ambianceAdjusted(maxBrightness: 0.55) ?? UIColor(white: 0.18, alpha: 1)
        let bottom = averageColor(upperHalf: false)?.ambianceAdjusted(maxBrightness: 0.28) ?? .black
        return (top, bottom)
    }

    private func averageColor(upperHalf: Bool) -> UIColor? {
        guard let ci = CIImage(image: self) else { return nil }
        let e = ci.extent
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
    func ambianceAdjusted(maxBrightness: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
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
