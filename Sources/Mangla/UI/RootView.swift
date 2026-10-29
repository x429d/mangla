import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    private var isReading: Bool { model.reading != nil }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            LibraryView(model: model)
                .opacity(isReading ? 0 : 1)
                .allowsHitTesting(!isReading)
                .accessibilityHidden(isReading)

            if let session = model.reading {
                ReaderView(session: session)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.012)),
                            removal: .opacity
                        )
                    )
                    .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 640)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.28), value: isReading)
        .alert(
            "Ошибка",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("Хорошо", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
