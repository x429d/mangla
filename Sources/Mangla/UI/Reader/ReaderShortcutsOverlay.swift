import SwiftUI

/// Cheat sheet shown with `?`. It is the discoverable home for every keyboard,
/// mouse and trackpad gesture the reader supports.
struct ReaderShortcutsOverlay: View {
    let session: ReadingSession

    private struct KeyRow: Identifiable {
        let id = UUID()
        let keys: [String]
        let action: String
    }

    private struct MouseRow: Identifiable {
        let id = UUID()
        let gesture: String
        let action: String
    }

    private let keyboardRows: [KeyRow] = [
        KeyRow(keys: ["←", "→", "A", "D"], action: "Страница назад / вперёд"),
        KeyRow(keys: [",", ".", "J", "K"], action: "То же в порядке чтения"),
        KeyRow(keys: ["Space", "PgDn"], action: "Экран или страница вперёд"),
        KeyRow(keys: ["⇧Space", "PgUp"], action: "Экран или страница назад"),
        KeyRow(keys: ["↑", "↓"], action: "Прокрутка (webtoon) / страница"),
        KeyRow(keys: ["Home", "End"], action: "Первая / последняя страница"),
        KeyRow(keys: ["[", "]"], action: "Глава назад / вперёд"),
        KeyRow(keys: ["⌘←", "⌘→"], action: "Глава назад / вперёд"),
        KeyRow(keys: ["1", "2", "3"], action: "Страница / разворот / webtoon"),
        KeyRow(keys: ["T"], action: "Направление RTL ↔ LTR"),
        KeyRow(keys: ["H", "W", "O"], action: "Вписать по высоте / ширине / 1:1"),
        KeyRow(keys: ["+", "−", "0"], action: "Зум / сброс к 100%"),
        KeyRow(keys: ["G"], action: "Перейти к странице"),
        KeyRow(keys: ["F", "⌃⌘F"], action: "Полный экран"),
        KeyRow(keys: ["?"], action: "Эта шпаргалка"),
        KeyRow(keys: ["Esc", "⌘⇧W"], action: "В библиотеку"),
    ]

    private let mouseRows: [MouseRow] = [
        MouseRow(gesture: "Клик слева / справа", action: "Страница назад / вперёд"),
        MouseRow(gesture: "Двойной клик в центре", action: "2.5× и обратно"),
        MouseRow(gesture: "Колесо", action: "Страница, если всё помещается; иначе прокрутка"),
        MouseRow(gesture: "⌘ + колесо", action: "Зум к курсору"),
        MouseRow(gesture: "Перетаскивание", action: "Панорама при зуме и длинной странице"),
        MouseRow(gesture: "Боковые кнопки", action: "Страница назад / вперёд"),
        MouseRow(gesture: "Правый клик", action: "Меню команд"),
        MouseRow(gesture: "Пинч", action: "Зум; два пальца при зуме — панорама"),
        MouseRow(gesture: "Свайп двумя пальцами", action: "Горизонтально — страница; при зуме — панорама"),
        MouseRow(gesture: "Верхний край", action: "Панель навигации и режимов"),
        MouseRow(gesture: "Нижний край", action: "Слайдер с превью страниц"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture { session.hideHelp() }

            panel
                .frame(maxWidth: 720)
                .padding(24)
        }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 24) {
                column(
                    title: "КЛАВИАТУРА",
                    symbol: "keyboard"
                ) {
                    ForEach(keyboardRows) { row in
                        keyRow(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1)

                column(
                    title: "МЫШЬ И ТРЕКПАД",
                    symbol: "computermouse"
                ) {
                    ForEach(mouseRows) { row in
                        mouseRow(row)
                    }
                }
                .frame(width: 286, alignment: .leading)
            }

            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.44))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 34, y: 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentSoft)
            Text("Управление")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("шпаргалка")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 12)
            Button {
                session.hideHelp()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Закрыть (Esc)")
        }
    }

    private func column<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundStyle(Theme.accentSoft.opacity(0.9))

            content()
        }
    }

    private func keyRow(_ row: KeyRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                    KeyCap(text: key)
                }
            }
            .frame(width: 126, alignment: .leading)

            Text(row.action)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mouseRow(_ row: MouseRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.gesture)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.86))
                .frame(width: 112, alignment: .leading)

            Text(row.action)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("В RTL стрелки и клик-зоны зеркальны. Нажатия читаются по физическим клавишам, поэтому раскладка не важна.")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textPrimary.opacity(0.88))
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
