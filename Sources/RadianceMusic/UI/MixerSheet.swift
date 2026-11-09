import RadianceKit
import SwiftUI

/**
 * The Mixer (Android's MixerSheet): the whole song, karaoke or the singing only for a split song, how much of the
 * singing karaoke keeps, and Low cut, High cut, Reverb (off at the left).
 */
struct MixerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let track: Track

    var body: some View {
        let m = app.mixer
        @Bindable var fx = Effects.shared
        NavigationStack {
            Form {
                Section {
                    if m.available {
                        Picker("Plays", selection: Binding(get: { m.voice }, set: { m.choose($0) })) {
                            Text("Song").tag(Mixer.Voice.song)
                            Text("Karaoke").tag(Mixer.Voice.karaoke)
                            Text("Vocals only").tag(Mixer.Voice.vocalsOnly)
                        }
                        .pickerStyle(.segmented)
                        if m.voice == .karaoke {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Singing kept: \(Int((m.singing * 100).rounded())) %").font(.system(size: 14)).foregroundStyle(Brand.dim)
                                Slider(value: Binding(get: { Double(m.singing) }, set: { m.sing(Float($0)) }), in: 0...1)
                            }
                        }
                    } else if let w = app.splitter.working, w.key == track.key {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(w.words).font(.system(size: 14)).foregroundStyle(Brand.dim)
                            ProgressView(value: app.splitter.setup ?? w.progress).tint(Brand.orange)
                            Button("Stop", role: .destructive) { app.splitter.cancel(track.key) }
                        }
                    } else if app.splitter.isWaiting(track.key) {
                        HStack {
                            Text("Waiting its turn to be split.").font(.system(size: 14)).foregroundStyle(Brand.dim)
                            Spacer()
                            Button("Take out") { app.splitter.cancel(track.key) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Split “\(track.title)” on this iPhone for karaoke and vocals only. It takes a minute or two (the first time it also gets the splitter, 39 MB).")
                                .font(.system(size: 14)).foregroundStyle(Brand.dim)
                            Button { app.splitter.split(track) } label: { Label("Split it", systemImage: "scissors").labelStyle(.titleAndIcon) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } header: { Text("Karaoke") } footer: {
                    if m.available { Text("Karaoke stays on from song to song.") }
                }
                Section {
                    slider("Low cut", value: $fx.lowSlider, words: fx.lowCut <= Effects.lowOff + 0.5 ? "Off" : "\(Int(fx.lowCut)) Hz")
                    slider("High cut", value: $fx.highSlider, words: fx.highCut >= Effects.highOff - 0.5 ? "Off" : String(format: "%.1f kHz", fx.highCut / 1000))
                    slider("Reverb", value: $fx.reverb, words: fx.reverb < 0.005 ? "Off" : "\(Int(fx.reverb * 100)) %")
                    if !fx.neutral {
                        Button("All off") { fx.lowCut = Effects.lowOff; fx.highCut = Effects.highOff; fx.reverb = 0; app.mixer.effectsChanged() }
                    }
                } header: { Text("Sound") } footer: {
                    Text("Low cut, High cut and Reverb play on songs saved on this iPhone and on split songs.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.sheet)
            .navigationTitle("Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func slider(_ name: String, value: Binding<Double>, words: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name); Spacer(); Text(words).foregroundStyle(Brand.dim) }.font(.system(size: 14))
            Slider(value: value, in: 0...1) { editing in if !editing { app.mixer.effectsChanged() } }
        }
    }
}
