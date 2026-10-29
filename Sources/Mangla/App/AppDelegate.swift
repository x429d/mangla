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

    static var isFullScreen: Bool {
        targetWindow?.styleMask.contains(.fullScreen) ?? false
    }

    static func setTrafficLightsHidden(_ hidden: Bool, in target: NSWindow? = nil) {
        guard let window = target ?? targetWindow else { return }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(button), button.isHidden != hidden else {
                continue
            }
            button.isHidden = hidden
        }
    }

    static func closeWindow() {
        targetWindow?.performClose(nil)
    }

    static func miniaturizeWindow() {
        targetWindow?.performMiniaturize(nil)
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
    private var lastNavigationKeyTime: TimeInterval = 0

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        createWindow()
        model.bootstrap()

        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
        WindowChrome.setTrafficLightsHidden(true)
        NSApp.activate(ignoringOtherApps: true)
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
        if let toolbar = window?.toolbar {
            for item in toolbar.items.reversed()
            where item.itemIdentifier.rawValue.contains("toggleSidebar") {
                if let index = toolbar.items.firstIndex(of: item) {
                    toolbar.removeItem(at: index)
                }
            }

            // The app ships a themed sidebar toggle and custom window
            // controls; the empty native toolbar otherwise becomes a black
            // strip in fullscreen.
            if toolbar.isVisible {
                toolbar.isVisible = false
            }
        }

        // The app draws its own window buttons in the sidebar and above the
        // library, so the native titlebar never appears over the content
        // (including fullscreen, where macOS otherwise reveals it together
        // with the menu bar).
        if let window {
            WindowChrome.setTrafficLightsHidden(true, in: window)
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let session = model.reading else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // The page field owns the keyboard while it is open; Enter is handled by
        // its TextField, Esc cancels here.
        if session.isPageEntryVisible {
            if event.keyCode == 53 {
                session.cancelPageEntry()
                return true
            }
            return false
        }

        // The cheat sheet is modal for reading keys, but system menu shortcuts
        // (⌘Q, ⌘W, ⌘H…) still work.
        if session.isHelpVisible {
            if event.keyCode == 53
                || ReaderShortcuts.isHelpKey(keyCode: event.keyCode, modifiers: flags) {
                session.hideHelp()
                return true
            }
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return false
            }
            return true
        }

        guard let command = ReaderShortcuts.command(
            keyCode: event.keyCode,
            modifiers: flags,
            layoutMode: session.layoutMode
        ) else {
            return false
        }

        if event.isARepeat, !command.allowsKeyRepeat {
            guard event.timestamp - lastNavigationKeyTime >= 0.10 else { return true }
        }
        lastNavigationKeyTime = event.timestamp

        return perform(command, in: session)
    }

    private func perform(_ command: ReaderKeyCommand, in session: ReadingSession) -> Bool {
        switch command {
        case .close:
            model.closeReader()
        case .pageLeft:
            if session.direction == .rtl { session.next() } else { session.previous() }
        case .pageRight:
            if session.direction == .rtl { session.previous() } else { session.next() }
        case .pageForward:
            session.next()
        case .pageBackward:
            session.previous()
        case .chapterForward:
            session.nextChapter()
        case .chapterBackward:
            session.previousChapter()
        case .firstPage:
            session.goToPage(0)
        case .lastPage:
            session.goToPage(max(0, session.totalPages - 1))
        case .screenForward:
            if session.bridge.scrollScreen(forward: true) { return true }
            if session.zoom > 1.01, session.layoutMode != .webtoon { return true }
            session.next()
        case .screenBackward:
            if session.bridge.scrollScreen(forward: false) { return true }
            if session.zoom > 1.01, session.layoutMode != .webtoon { return true }
            session.previous()
        case .layout(let mode):
            session.layoutMode = mode
        case .toggleDirection:
            session.toggleDirection()
        case .fit(let mode):
            session.fitMode = mode
        case .zoomIn:
            session.bridge.zoomIn()
        case .zoomOut:
            session.bridge.zoomOut()
        case .resetZoom:
            session.resetZoom()
        case .toggleFullScreen:
            WindowChrome.toggleFullScreen()
        case .toggleHelp:
            session.toggleHelp()
        case .pageEntry:
            session.beginPageEntry()
        }
        return true
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

        let readingMenuItem = NSMenuItem()
        mainMenu.addItem(readingMenuItem)
        let readingMenu = NSMenu(title: "Чтение")
        readingMenuItem.submenu = readingMenu
        readingMenu.addItem(menuItem("Предыдущая страница", #selector(readingPreviousPage(_:)), ""))
        readingMenu.addItem(menuItem("Следующая страница", #selector(readingNextPage(_:)), ""))
        readingMenu.addItem(.separator())
        readingMenu.addItem(menuItem("Предыдущая глава", #selector(readingPreviousChapter(_:)), ""))
        readingMenu.addItem(menuItem("Следующая глава", #selector(readingNextChapter(_:)), ""))
        readingMenu.addItem(.separator())
        readingMenu.addItem(menuItem("Перейти к странице…", #selector(readingGoToPage(_:)), "g"))

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

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Справка")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(menuItem("Управление читалкой", #selector(readingShowHelp(_:)), "/"))

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
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
    @objc private func readingPreviousPage(_ sender: Any?) { model.reading?.previous() }
    @objc private func readingNextPage(_ sender: Any?) { model.reading?.next() }
    @objc private func readingPreviousChapter(_ sender: Any?) { model.reading?.previousChapter() }
    @objc private func readingNextChapter(_ sender: Any?) { model.reading?.nextChapter() }
    @objc private func readingGoToPage(_ sender: Any?) { model.reading?.beginPageEntry() }
    @objc private func readingShowHelp(_ sender: Any?) { model.reading?.toggleHelp() }
    @objc private func zoomIn(_ sender: Any?) { model.reading?.bridge.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { model.reading?.bridge.zoomOut() }
    @objc private func resetZoom(_ sender: Any?) { model.reading?.bridge.resetZoom() }
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
        case #selector(readingPreviousPage(_:)), #selector(readingNextPage(_:)),
             #selector(readingPreviousChapter(_:)), #selector(readingNextChapter(_:)),
             #selector(readingGoToPage(_:)), #selector(readingShowHelp(_:)):
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
