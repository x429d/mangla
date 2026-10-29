import SwiftUI

/// Small command palette for jumping to a page by number (`G`).
struct ReaderPageEntryOverlay: View {
    @Bindable var session: ReadingSession
    @FocusState private var isFocused: Bool

    private var pageBinding: Binding<String> {
        Binding(
            get: { session.pageEntryText },
            set: { value in
                let digits = value.filter { "0123456789".contains($0) }
                session.pageEntryText = String(digits.prefix(4))
            }
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { session.cancelPageEntry() }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(t(.page))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("1", text: pageBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 62)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.09))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
                        )
                        .focused($isFocused)
                        .onSubmit { session.commitPageEntry() }

                    Text("/ \(session.totalPages)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }

                Text(t(.pageEntryHint))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
        .onAppear { isFocused = true }
        .task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            isFocused = true
        }
    }
}
