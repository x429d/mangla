import AppKit
import SwiftUI

@MainActor
final class ManglaWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
enum WindowChrome {
    private static var targetWindow: NSWindow? {
        if let window = NSApp.mainWindow, window.isVisible { return window }
        if let window = NSApp.keyWindow, window.isVisible { return window }
        return NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    static func setTrafficLightsHidden(_ hidden: Bool) {
        guard let window = targetWindow else { return }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = hidden
        }
    }

    static func toggleFullScreen() {
        guard let window = targetWindow else { return }
        window.toggleFullScreen(nil)
    }
}

@main
enum ManglaMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = AppModel()
    private var window: ManglaWindow?
    private var hostingController: NSHostingController<RootView>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        createWindow()
        model.bootstrap()

        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
        NSApp.activate(ignoringOtherApps: true)

        model.bridge.focus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Window

    private func createWindow() {
        let window = ManglaWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mangla"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.043, green: 0.045, blue: 0.052, alpha: 1)
        window.minSize = NSSize(width: 980, height: 640)
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        let root = RootView(model: model)
        let controller = NSHostingController(rootView: root)
        hostingController = controller
        window.contentViewController = controller
        window.toolbar = nil
        window.setContentSize(NSSize(width: 1440, height: 900))

        window.setFrameAutosaveName("Mangla.MainWindow")
        if !window.setFrameUsingName("Mangla.MainWindow") {
            window.center()
        }

        window.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }

        self.window = window

        // SwiftUI installs its own sidebar toggle into the titlebar toolbar
        // after the window is created. The app ships a themed toggle in the
        // sidebar header, so the native duplicate is removed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: window
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.removeNativeSidebarToggle()
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        removeNativeSidebarToggle()
    }

    private func removeNativeSidebarToggle() {
        guard let toolbar = window?.toolbar else { return }

        for item in toolbar.items.reversed()
        where item.itemIdentifier.rawValue.contains("toggleSidebar") {
            if let index = toolbar.items.firstIndex(of: item) {
                toolbar.removeItem(at: index)
            }
        }

        // The app ships a themed sidebar toggle and a custom reader HUD; the
        // empty native toolbar otherwise becomes a black strip in fullscreen.
        if toolbar.isVisible {
            toolbar.isVisible = false
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let session = model.reading else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }

        switch event.keyCode {
        case 53: // Esc
            model.closeReader()
            return true
        case 123: // Left
            if session.direction == .rtl { session.next() } else { session.previous() }
            return true
        case 124: // Right
            if session.direction == .rtl { session.previous() } else { session.next() }
            return true
        case 0: // A (acts like Left)
            if session.direction == .rtl { session.next() } else { session.previous() }
            return true
        case 2: // D (acts like Right)
            if session.direction == .rtl { session.previous() } else { session.next() }
            return true
        case 49, 121: // Space, Page Down
            session.next()
            return true
        case 116: // Page Up
            session.previous()
            return true
        case 115: // Home
            session.goToPage(0)
            return true
        case 119: // End
            session.goToPage(max(0, session.totalPages - 1))
            return true
        case 18: // 1
            session.layoutMode = .single
            return true
        case 19: // 2
            session.layoutMode = .spread
            return true
        case 20: // 3
            session.layoutMode = .webtoon
            return true
        case 17: // T
            guard session.layoutMode != .webtoon else { return true }
            session.direction = session.direction == .rtl ? .ltr : .rtl
            return true
        case 4: // H — fit height
            guard session.layoutMode != .webtoon else { return true }
            session.fitMode = .fitHeight
            return true
        case 13: // W — fit width
            guard session.layoutMode != .webtoon else { return true }
            session.fitMode = .fitWidth
            return true
        case 31: // O — original size
            guard session.layoutMode != .webtoon else { return true }
            session.fitMode = .original
            return true
        case 3: // F
            WindowChrome.toggleFullScreen()
            return true
        default:
            return false
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "О Mangla", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть Mangla", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(
            title: "Скрыть остальные",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Показать все", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Завершить Mangla", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "Файл")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(menuItem("Добавить коллекцию…", #selector(openProject(_:)), "o"))
        fileMenu.addItem(menuItem("Обновить коллекцию", #selector(refreshProject(_:)), "r"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("Закрыть читалку", #selector(closeReader(_:)), "w", [.command, .shift]))
        fileMenu.addItem(withTitle: "Закрыть окно", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Правка")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "Вид")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(menuItem("Показать/скрыть панель", #selector(toggleSidebar(_:)), "\\"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(menuItem("Увеличить", #selector(zoomIn(_:)), "="))
        viewMenu.addItem(menuItem("Уменьшить", #selector(zoomOut(_:)), "-"))
        viewMenu.addItem(menuItem("Фактический размер", #selector(resetZoom(_:)), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(menuItem("Полный экран", #selector(toggleFullScreen(_:)), "f", [.command, .control]))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Окно")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Свернуть", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    // MARK: - Menu actions

    @objc private func openProject(_ sender: Any?) { model.addCollections() }
    @objc private func refreshProject(_ sender: Any?) { model.refresh() }
    @objc private func toggleSidebar(_ sender: Any?) {
        guard model.reading == nil else { return }
        model.toggleSidebar()
    }
    @objc private func closeReader(_ sender: Any?) {
        guard model.reading != nil else { return }
        model.closeReader()
    }
    @objc private func zoomIn(_ sender: Any?) { model.bridge.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { model.bridge.zoomOut() }
    @objc private func resetZoom(_ sender: Any?) { model.bridge.resetZoom() }
    @objc private func toggleFullScreen(_ sender: Any?) { WindowChrome.toggleFullScreen() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openProject(_:)):
            return true
        case #selector(refreshProject(_:)):
            return model.selectedCollectionID != nil
        case #selector(closeReader(_:)):
            return model.reading != nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(resetZoom(_:)):
            return model.reading != nil
        case #selector(toggleSidebar(_:)):
            return model.reading == nil && !model.collections.isEmpty
        case #selector(toggleFullScreen(_:)):
            return true
        default:
            return true
        }
    }
}
