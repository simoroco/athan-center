import SwiftUI

// MARK: - ActionEditSheet — create/edit a custom tracked action (iOS only).

struct ActionEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    /// nil = create, otherwise edit this action.
    var editing: TrackedAction? = nil

    @State private var name: String = ""
    @State private var icon: String = "📿"
    @State private var counter: Bool = false

    private let icons = ["📿", "🤲", "📖", "🕌", "🌙", "⭐", "💧", "🧎", "🙏", "❤️", "✨", "🌟", "☀️", "🕯️", "📿", "🚶"]

    var body: some View {
        let theme = store.theme
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.muted)
                        TextField("e.g. Sadaqa, Dua, Walk…", text: $name)
                            .padding(12)
                            .background(theme.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(theme.textPrimary)
                            .accessibilityIdentifier("actionNameField")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                            ForEach(icons, id: \.self) { e in
                                Text(e)
                                    .font(.system(size: 26))
                                    .frame(width: 40, height: 40)
                                    .background(icon == e ? Color(hex: 0xD4AF37).opacity(0.35) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                        icon == e ? Color(hex: 0xD4AF37) : Color.clear, lineWidth: 2))
                                    .onTapGesture { icon = e }
                            }
                        }
                    }

                    Toggle(isOn: $counter) {
                        VStack(alignment: .leading) {
                            Text("Numeric counter")
                                .foregroundStyle(theme.textPrimary)
                            Text(counter ? "Tap adds +1 (e.g. rak'as, pages)" : "Unchecked → orange → blue")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.muted)
                        }
                    }
                    .tint(Color(hex: 0xD4AF37))
                    .accessibilityIdentifier("actionCounterToggle")

                    if editing != nil {
                        Button(role: .destructive) {
                            if let e = editing { store.removeAction(id: e.id) }
                            dismiss()
                        } label: {
                            Label("Delete this action", systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("actionDelete")
                    }

                    Spacer(minLength: 8)
                }
                .padding(20)
            }
            .background(theme.bgBase)
            .navigationTitle(editing == nil ? "New action" : "Edit action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("actionSave")
                }
            }
            .onAppear {
                if let e = editing {
                    name = e.name; icon = e.icon; counter = e.counter
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if var e = editing {
            e.name = trimmed; e.icon = icon; e.counter = counter
            store.updateAction(e)
        } else {
            store.addAction(TrackedAction(name: trimmed, icon: icon, counter: counter))
        }
        dismiss()
    }
}
