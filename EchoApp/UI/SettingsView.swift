import EchoCore
import SwiftUI

/// User settings: optional sound groups that are hidden by default.
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let descriptions: [String: String] = [
        "Footsteps": "Someone walking or running nearby.",
        "Water Running": "A tap, sink, bath or toilet running.",
        "Power Tool": "Drills, saws, chainsaws and lawn mowers.",
        "Cough/Sneeze": "Someone coughing or sneezing nearby.",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(model.optionalGroups, id: \.self) { group in
                        Toggle(isOn: binding(for: group)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group)
                                if let text = Self.descriptions[group] {
                                    Text(text).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Extra sounds")
                } footer: {
                    Text("Off by default: they happen often and rarely need action. When on, they show as low urgency.")
                }
                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Louder than the room by", value: "\(Int(model.loudnessMargin.rounded())) dB")
                        Slider(value: $model.loudnessMargin, in: LoudnessGate.marginRange, step: 1) {
                            Text("Strictness")
                        } minimumValueLabel: {
                            Text("More\nsensitive").font(.caption).multilineTextAlignment(.leading)
                        } maximumValueLabel: {
                            Text("Less\nsensitive").font(.caption).multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Strictness")
                } footer: {
                    Text("A sound is only named when its loudest moment is this much louder than the room's background (and at least 45 dB). Raise it in loud rooms to ignore quieter sounds; default 6 dB.")
                }
                Section {
                    Toggle(isOn: $model.demoMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Demo mode")
                            Text("Treat sounds as coming from a speaker.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Clips played on a laptop or phone are far quieter than the real thing, so they look distant and less urgent. Demo mode assumes speaker playback: a siren played loudly nearby shows red. Turn it off for real-world use.")
                }
                Section {
                    Text("Typing, keys, camera shutters, body sounds, music, TV and radio, crowds and laughter, appliance hum, insects, birds and other animals (except dogs) and aircraft overhead.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Never shown")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func binding(for group: String) -> Binding<Bool> {
        Binding(
            get: { model.enabledOptionalGroups.contains(group) },
            set: { on in
                if on { model.enabledOptionalGroups.insert(group) } else { model.enabledOptionalGroups.remove(group) }
            })
    }
}
