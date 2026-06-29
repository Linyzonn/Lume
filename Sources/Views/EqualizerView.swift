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
                            engine.listeningMode = mode
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
                }
                .padding(.horizontal)
            }
            Text("Choisis un profil adapté à ton écoute. Il règle d'un coup l'égaliseur, les basses et l'ambiance.")
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
