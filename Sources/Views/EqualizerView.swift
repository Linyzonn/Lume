import SwiftUI

// Panneau « Son » : profils d'ecoute, optimiseur de basses, ambiance et egaliseur.
struct EqualizerView: View {
    @EnvironmentObject var engine: PlayerEngine
    @Environment(\.dismiss) var dismiss

    // Presets manuels de l'egaliseur : 10 gains (dB) chacun.
    static let presets: [(name: String, gains: [Float])] = [
        ("Plat",        [0,0,0,0,0,0,0,0,0,0]),
        ("Basses +",    [6,5,4,2,0,0,0,0,1,2]),
        ("Aigus +",     [0,0,0,0,0,1,2,4,5,6]),
        ("Vocal",       [-2,-1,0,2,4,4,3,1,0,-1]),
        ("Pop",         [-1,0,2,3,3,2,0,-1,-1,-1]),
        ("Rock",        [4,3,1,-1,-1,0,2,3,4,4]),
        ("Électro",     [5,4,1,0,-1,1,2,3,4,5]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    modeSection
                    speedSection
                    boostSection
                    normalizeSection
                    bassSection
                    ambianceSection
                    eqSection
                }
                .padding(.vertical)
            }
            .navigationTitle("Son")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Profils d'ecoute

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Profil d'écoute", systemImage: "dial.medium")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PlayerEngine.ListeningMode.allCases) { mode in
                        let selected = engine.listeningMode == mode
                        Button {
                            // selectListeningMode sauvegarde d'abord les
                            // reglages manuels (recuperables via
                            // « Personnalisé » ci-dessous).
                            engine.selectListeningMode(mode)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.title3)
                                Text(mode.rawValue)
                                    .font(.caption2.weight(.medium))
                            }
                            .frame(width: 84, height: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? AnyShapeStyle(LumeTheme.accent.gradient)
                                                   : AnyShapeStyle(Color.secondary.opacity(0.12)))
                            )
                            .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    // Retour aux derniers reglages manuels : un profil ne
                    // detruit plus le son personnalise de l'utilisateur.
                    if engine.hasCustomSound {
                        Button {
                            engine.restoreCustomSound()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.title3)
                                Text("Personnalisé")
                                    .font(.caption2.weight(.medium))
                            }
                            .frame(width: 84, height: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            Text("Choisis un profil adapté à ton écoute. Il règle d'un coup l'égaliseur, les basses et l'ambiance. « Personnalisé » restaure tes derniers réglages manuels.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    // MARK: - Vitesse de lecture

    private static let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Vitesse de lecture", systemImage: "gauge.with.needle")
            HStack(spacing: 10) {
                ForEach(Self.speeds, id: \.self) { speed in
                    let selected = engine.playbackRate == speed
                    Button(speedLabel(speed)) {
                        engine.playbackRate = speed
                    }
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Capsule().fill(selected ? AnyShapeStyle(LumeTheme.accent)
                                                : AnyShapeStyle(Color.secondary.opacity(0.12)))
                    )
                    .foregroundStyle(selected ? .white : .primary)
                    .accessibilityLabel("Vitesse \(speedLabel(speed))")
                }
            }
            .padding(.horizontal)
            Text("Pratique pour les podcasts et livres audio (la hauteur du son ne change pas). À une vitesse différente de 1x, le lecteur affiche des boutons ±15 s.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    private func speedLabel(_ s: Float) -> String {
        s == 1 ? "1x" : String(format: "%g", Double(s)) + "x"
    }

    // MARK: - Boost de volume

    private var boostSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Boost de volume", systemImage: "bolt.fill")
            HStack {
                Text("100%").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(engine.volumeBoost) },
                    set: { engine.volumeBoost = Float($0) }
                ), in: 0...0.5, step: 0.05)
                .tint(LumeTheme.accent)
                Text("\(100 + Int((engine.volumeBoost * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 52)
            }
            .padding(.horizontal)
            Text("Amplifie le son au-delà du volume maximal de l'iPhone. À forte valeur, un peu de saturation est possible.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    // MARK: - Volume homogene

    private var normalizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $engine.normalizeVolume) {
                sectionTitle("Volume homogène", systemImage: "waveform.path.ecg")
            }
            .padding(.horizontal)
            Text("Atténue les morceaux plus forts que les autres pour un niveau d'écoute constant. Qualité intacte : aucune compression, le niveau est ajusté une seule fois avant chaque morceau, jamais en cours de lecture. Prend effet à partir du morceau suivant (la bibliothèque s'analyse en arrière-plan à l'activation).")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    // MARK: - Optimiseur de basses

    private var bassSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $engine.bassBoostEnabled) {
                sectionTitle("Optimiseur de basses", systemImage: "speaker.wave.3.fill")
            }
            .padding(.horizontal)

            if engine.bassBoostEnabled {
                HStack {
                    Image(systemName: "minus")
                    Slider(value: $engine.bassBoostAmount, in: 0...12, step: 1)
                        .tint(LumeTheme.accent)
                    Image(systemName: "plus")
                    Text("\(Int(engine.bassBoostAmount))")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 24)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Ambiance (reverb)

    private var ambianceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Ambiance", systemImage: "music.mic")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PlayerEngine.ReverbOption.allCases) { opt in
                        let selected = engine.reverbOption == opt
                        Button(opt.rawValue) {
                            engine.reverbOption = opt
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(LumeTheme.accent)
                                                    : AnyShapeStyle(Color.secondary.opacity(0.12)))
                        )
                        .foregroundStyle(selected ? .white : .primary)
                    }
                }
                .padding(.horizontal)
            }
            if engine.reverbOption != .off {
                HStack {
                    Text("Intensité").font(.subheadline)
                    Slider(value: $engine.reverbAmount, in: 0...100, step: 5)
                        .tint(LumeTheme.accent)
                    Text("\(Int(engine.reverbAmount))%")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 44)
                }
                .padding(.horizontal)
            }
            Text("« Concert » et « Cathédrale » donnent la sensation d'espace d'une salle live.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }
    }

    // MARK: - Egaliseur manuel

    private var eqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $engine.eqEnabled) {
                sectionTitle("Égaliseur", systemImage: "slider.vertical.3")
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.presets, id: \.name) { preset in
                        Button(preset.name) {
                            engine.eqGains = preset.gains
                            engine.eqEnabled = true
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<10, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", engine.eqGains[i]))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                        VerticalSlider(value: Binding(
                            get: { engine.eqGains[i] },
                            set: { newVal in
                                var g = engine.eqGains
                                g[i] = newVal
                                engine.eqGains = g
                            }
                        ), range: -12...12)
                        .frame(maxHeight: .infinity)
                        // VoiceOver : chaque bande devient reglable
                        // (balayage vertical = ±1 dB).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Bande \(freqLabel(PlayerEngine.eqFrequencies[i])) hertz")
                        .accessibilityValue("\(Int(engine.eqGains[i])) décibels")
                        .accessibilityAdjustableAction { direction in
                            var g = engine.eqGains
                            g[i] += direction == .increment ? 1 : -1
                            g[i] = max(-12, min(12, g[i]))
                            engine.eqGains = g
                        }
                        Text(freqLabel(PlayerEngine.eqFrequencies[i]))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 200)
            .padding(.horizontal)
            .opacity(engine.eqEnabled ? 1 : 0.4)
            .disabled(!engine.eqEnabled)

            Button("Réinitialiser l'égaliseur") {
                engine.eqGains = Array(repeating: 0, count: 10)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Aides

    private func sectionTitle(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private func freqLabel(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f/1000))k" : "\(Int(f))"
    }
}

// Slider vertical pour l'egaliseur.
struct VerticalSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let pct = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.25))
                    .frame(width: 4)
                Capsule().fill(LumeTheme.accent)
                    .frame(width: 4, height: height * pct)
                Circle().fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(radius: 2)
                    .offset(y: -(height - 18) * pct)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let p = 1 - min(max(0, g.location.y / height), 1)
                        value = range.lowerBound + Float(p) * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}
