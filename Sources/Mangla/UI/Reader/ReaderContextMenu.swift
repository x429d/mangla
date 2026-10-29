import AppKit

/// Right-click menu shared by the page and webtoon canvases.
///
/// Mouse users get the same navigation, layout, fit and zoom controls as the
/// keyboard and HUD, without having to find the hover panels first.
@MainActor
final class ReaderContextMenuController: NSObject {
    private let session: ReadingSession

    init(session: ReadingSession) {
        self.session = session
        super.init()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Предыдущая страница", #selector(previousPage(_:))))
        menu.addItem(item("Следующая страница", #selector(nextPage(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Предыдущая глава", #selector(previousChapter(_:))))
        menu.addItem(item("Следующая глава", #selector(nextChapter(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Перейти к странице…", #selector(goToPage(_:))))

        menu.addItem(.separator())

        let layoutItem = item("Режим", nil)
        layoutItem.submenu = layoutMenu()
        menu.addItem(layoutItem)

        let directionItem = item("Направление", nil)
        directionItem.isEnabled = session.layoutMode != .webtoon
        directionItem.submenu = directionMenu()
        menu.addItem(directionItem)

        let fitItem = item("Вписывание", nil)
        fitItem.isEnabled = session.layoutMode != .webtoon
        fitItem.submenu = fitMenu()
        menu.addItem(fitItem)

        menu.addItem(.separator())

        let zoomIn = item("Увеличить", #selector(zoomIn(_:)))
        zoomIn.isEnabled = session.zoom < 4.99
        menu.addItem(zoomIn)

        let zoomOut = item("Уменьшить", #selector(zoomOut(_:)))
        zoomOut.isEnabled = session.zoom > 1.01
        menu.addItem(zoomOut)

        let resetZoom = item("Сбросить масштаб", #selector(resetZoom(_:)))
        resetZoom.isEnabled = session.zoom > 1.01
        menu.addItem(resetZoom)

        menu.addItem(.separator())
        menu.addItem(item("Управление…", #selector(showHelp(_:))))
        menu.addItem(item("Полный экран", #selector(toggleFullScreen(_:))))
        menu.addItem(.separator())
        menu.addItem(item("В библиотеку", #selector(closeReader(_:))))

        return menu
    }

    private func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if action != nil {
            item.target = self
        }
        return item
    }

    private func layoutMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for mode in LayoutMode.allCases {
            let item = item(mode.title, #selector(setLayout(_:)))
            item.representedObject = mode.rawValue
            item.state = session.layoutMode == mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func directionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for direction in ReadingDirection.allCases {
            let item = item(direction.title, #selector(setDirection(_:)))
            item.representedObject = direction.rawValue
            item.state = session.direction == direction ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func fitMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for mode in FitMode.allCases {
            let item = item(mode.title, #selector(setFit(_:)))
            item.representedObject = mode.rawValue
            item.state = session.fitMode == mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Actions

    @objc private func previousPage(_ sender: Any?) { session.previous() }
    @objc private func nextPage(_ sender: Any?) { session.next() }
    @objc private func previousChapter(_ sender: Any?) { session.previousChapter() }
    @objc private func nextChapter(_ sender: Any?) { session.nextChapter() }
    @objc private func goToPage(_ sender: Any?) { session.beginPageEntry() }
    @objc private func zoomIn(_ sender: Any?) { session.bridge.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { session.bridge.zoomOut() }
    @objc private func resetZoom(_ sender: Any?) { session.resetZoom() }
    @objc private func showHelp(_ sender: Any?) { session.showHelp() }
    @objc private func toggleFullScreen(_ sender: Any?) { WindowChrome.toggleFullScreen() }
    @objc private func closeReader(_ sender: Any?) { session.dismiss() }

    @objc private func setLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = LayoutMode(rawValue: raw) else { return }
        session.layoutMode = mode
    }

    @objc private func setDirection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let direction = ReadingDirection(rawValue: raw) else { return }
        session.direction = direction
    }

    @objc private func setFit(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = FitMode(rawValue: raw) else { return }
        session.fitMode = mode
    }
}
