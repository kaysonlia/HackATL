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
