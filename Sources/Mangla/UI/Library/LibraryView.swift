import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.projectURL == nil {
                WelcomeView(model: model)
                    .transition(.opacity)
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    SidebarView(model: model)
                        .navigationSplitViewColumnWidth(min: 252, ideal: 300, max: 372)
                } detail: {
                    LibraryGridView(model: model)
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar(removing: .sidebarToggle)
                .background(Theme.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.25), value: model.projectURL)
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var showStructure = false

    var body: some View {
        ZStack {
            Theme.backgroundDeep.ignoresSafeArea()

            RadialGradient(
                colors: [Theme.accent.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 760
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color(red: 0.25, green: 0.55, blue: 0.85).opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 700
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                LogoMark(size: 78)
                    .padding(.bottom, 26)

                Text("Mangla")
                    .font(.system(size: 72, weight: .regular, design: .serif))
                    .tracking(-1.5)
                    .foregroundStyle(Theme.textPrimary)

                Text("Тихая, быстрая читалка манги для macOS")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)

                HStack(spacing: 14) {
                    Button {
                        model.chooseProject()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                            Text("Выбрать папку проекта")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Theme.accentSoft, Theme.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        withAnimation(Theme.spring) { showStructure.toggle() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "questionmark.circle")
                            Text("Как это работает")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 34)

                if showStructure {
                    StructureExplainer()
                        .padding(.top, 30)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                } else {
                    HStack(spacing: 8) {
                        ForEach(["WEBP", "JPG", "PNG", "AVIF", "HEIC"], id: \.self) { format in
                            Text(format)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.045)))
                                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                        }
                    }
                    .padding(.top, 34)
                }

                Spacer(minLength: 40)

                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.accentSoft)
                    Text("Нативный AppKit · ProMotion")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 40)
        }
    }
}

struct StructureExplainer: View {
    var body: some View {
        HStack(spacing: 0) {
            column(
                title: "Проект",
                subtitle: "любая папка",
                lines: ["/Manga Library"]
            )
            arrow
            column(
                title: "Манга",
                subtitle: "папка с названием",
                lines: ["/Berserk", "/One Piece"]
            )
            arrow
            column(
                title: "Глава",
                subtitle: "картинки или подпапки",
                lines: ["/001.webp", "/Chapter 02/"]
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 14)
    }

    private func column(title: String, subtitle: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.accentSoft)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 3)
        }
        .frame(width: 170, alignment: .leading)
    }
}

// MARK: - Empty project

struct EmptyProjectView: View {
    let onRefresh: () -> Void
    let onChoose: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.panel)
                    .frame(width: 92, height: 118)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -14, y: 4)
                    .opacity(0.55)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.panelStrong)
                    .frame(width: 92, height: 118)
                    .rotationEffect(.degrees(5))
                    .offset(x: 14, y: 2)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 92, height: 118)
                    .overlay(
                        Image(systemName: "folder.fill")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    )
            }
            .frame(height: 138)

            Text("В проекте нет манги")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)

            Text("Добавьте папки с мангой в выбранный проект — они появятся здесь автоматически.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button("Обновить") { onRefresh() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Выбрать другую папку") { onChoose() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Показать в Finder") { onReveal() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.11 : 0.06)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
