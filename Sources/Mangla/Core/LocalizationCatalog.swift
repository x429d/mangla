/// Every user-visible string in the app. Adding a key forces both language
/// tables to be updated, and `LocalizationTests` verifies that neither is
/// missing an entry.
enum LocKey: String, CaseIterable, Sendable {
    // Common
    case ok
    case errorTitle
    case refresh
    case checkAgain
    case revealInFinder
    case removeFromApp
    case addCollection
    case refreshCollection
    case defaultCollectionName
    case folderUnavailable
    case previousPage
    case nextPage
    case previousChapter
    case nextChapter
    case goToPage
    case closeWindow
    case minimizeWindow
    case fullScreen
    case zoomIn
    case zoomOut
    case resetZoom
    case backToLibrary
    case openControls

    // App menu
    case menuAbout
    case menuHide
    case menuHideOthers
    case menuShowAll
    case menuQuit
    case menuFile
    case menuAddCollection
    case menuCloseReader
    case menuEdit
    case menuUndo
    case menuRedo
    case menuCut
    case menuCopy
    case menuPaste
    case menuSelectAll
    case menuReading
    case menuView
    case menuToggleSidebar
    case menuActualSize
    case menuWindow
    case menuWindowZoom
    case menuHelp
    case menuReaderControls

    // Welcome screen
    case welcomeTagline
    case welcomeDescription
    case welcomeHowItWorks
    case welcomeFooter
    case structureCollection
    case structureAnyFolder
    case structureManga
    case structureNamedFolder
    case structureChapter
    case structureImagesOrSubfolders

    // Library
    case collectionsHeader
    case collectionHeader
    case searchPlaceholder
    case addCollectionHelp
    case refreshCollectionHelp
    case collectionActions
    case scanningCollection
    case selectCollection
    case nothingFound
    case tryAnotherQuery
    case resetFilters
    case showingRange
    case searchQuote
    case emptyNoManga
    case emptyAddFolders
    case unavailableCollectionTitle
    case checking

    // Filters and reading status
    case filterAll
    case filterReading
    case filterCompleted
    case statusUnread
    case statusReading
    case statusCompleted

    // Manga card
    case read
    case continueAction
    case restart
    case chaptersMenu
    case markUnread
    case markRead
    case continueHeader
    case continueMeta

    // Layout, fit and direction
    case layoutSingle
    case layoutSpread
    case layoutWebtoon
    case fitHeight
    case fitWidth
    case fitOriginal
    case fitHeightShort
    case fitWidthShort
    case directionLTR
    case directionRTL

    // Reader sidebar
    case library
    case backToLibraryHelp
    case fit
    case direction
    case zoom
    case mode
    case page
    case fitModeHelp
    case zoomInHelp
    case zoomOutHelp
    case resetZoomHelp
    case goToPageHelp
    case previousChapterHelp
    case nextChapterHelp
    case previousPageLeftHelp
    case nextPageLeftHelp
    case previousPageRightHelp
    case nextPageRightHelp
    case controlsHelp
    case fullScreenHelp

    // Reader overlays and toasts
    case loadingChapter
    case pageEntryHint
    case openPageFailed
    case toastLastChapter
    case toastFirstChapter
    case toastNextUp
    case toastInvalidPage

    // Window controls and sidebar toggle
    case exitFullScreenHelp
    case showSidebarHelp
    case hideSidebarHelp

    // Shortcut cheat sheet
    case helpTitle
    case helpSubtitle
    case helpClose
    case helpKeyboard
    case helpMouse
    case helpFooter
    case helpPageBackForward
    case helpPageReadingOrder
    case helpScreenForward
    case helpScreenBackward
    case helpScrollWebtoon
    case helpFirstLastPage
    case helpChapterBackForward
    case helpLayoutModes
    case helpDirection
    case helpFitModes
    case helpZoom
    case helpGoToPage
    case helpFullScreen
    case helpThisSheet
    case helpToLibrary
    case helpClickSides
    case helpDoubleClickCenter
    case helpSmartZoom
    case helpWheel
    case helpWheelAction
    case helpCommandWheel
    case helpZoomToCursor
    case helpDrag
    case helpDragAction
    case helpSideButtons
    case helpRightClick
    case helpCommandMenu
    case helpPinch
    case helpPinchAction
    case helpTwoFingerSwipe
    case helpTwoFingerSwipeAction
    case helpLeftEdge
    case helpLeftEdgeAction

    // Scan and decode errors
    case scanUnreadable
    case scanNotDirectory
    case decodeCannotOpen
    case decodeCannotDecode
    case decodeCannotReadSize

    // Pagination
    case rangeEmpty
    case rangeLabel

    // System panels and alerts
    case addCollectionsTitle
    case addCollectionsMessage
    case addCollectionsPrompt
    case alreadyAdded
    case collectionUnavailable
    case missingProjectPath

    // Counted nouns
    case countPageOne
    case countPageFew
    case countPageMany
    case countPageOther
    case countChapterOne
    case countChapterFew
    case countChapterMany
    case countChapterOther
    case countMangaOne
    case countMangaFew
    case countMangaMany
    case countMangaOther
    case countCollectionOne
    case countCollectionFew
    case countCollectionMany
    case countCollectionOther
    case compactPage
    case compactChapter
}

extension LocKey {
    /// English is the development language and the fallback. Every key must be
    /// present here.
    static let english: [LocKey: String] = [
        .ok: "OK",
        .errorTitle: "Error",
        .refresh: "Refresh",
        .checkAgain: "Check Again",
        .revealInFinder: "Show in Finder",
        .removeFromApp: "Remove from App",
        .addCollection: "Add Collection",
        .refreshCollection: "Refresh Collection",
        .defaultCollectionName: "Collection",
        .folderUnavailable: "Folder unavailable",
        .previousPage: "Previous Page",
        .nextPage: "Next Page",
        .previousChapter: "Previous Chapter",
        .nextChapter: "Next Chapter",
        .goToPage: "Go to Page…",
        .closeWindow: "Close Window",
        .minimizeWindow: "Minimize",
        .fullScreen: "Full Screen",
        .zoomIn: "Zoom In",
        .zoomOut: "Zoom Out",
        .resetZoom: "Reset Zoom",
        .backToLibrary: "Back to Library",
        .openControls: "Controls…",
        .menuAbout: "About Mangla",
        .menuHide: "Hide Mangla",
        .menuHideOthers: "Hide Others",
        .menuShowAll: "Show All",
        .menuQuit: "Quit Mangla",
        .menuFile: "File",
        .menuAddCollection: "Add Collection…",
        .menuCloseReader: "Close Reader",
        .menuEdit: "Edit",
        .menuUndo: "Undo",
        .menuRedo: "Redo",
        .menuCut: "Cut",
        .menuCopy: "Copy",
        .menuPaste: "Paste",
        .menuSelectAll: "Select All",
        .menuReading: "Reading",
        .menuView: "View",
        .menuToggleSidebar: "Show/Hide Sidebar",
        .menuActualSize: "Actual Size",
        .menuWindow: "Window",
        .menuWindowZoom: "Zoom",
        .menuHelp: "Help",
        .menuReaderControls: "Reader Controls",
        .welcomeTagline: "A quiet, fast manga reader for macOS",
        .welcomeDescription: "Add one or more collection folders — the app will keep them open at the same time.",
        .welcomeHowItWorks: "How It Works",
        .welcomeFooter: "Native AppKit · ProMotion",
        .structureCollection: "Collection",
        .structureAnyFolder: "any folder",
        .structureManga: "Manga",
        .structureNamedFolder: "folder with a name",
        .structureChapter: "Chapter",
        .structureImagesOrSubfolders: "images or subfolders",
        .collectionsHeader: "COLLECTIONS",
        .collectionHeader: "COLLECTION",
        .searchPlaceholder: "Search collection",
        .addCollectionHelp: "Add Collection (⌘O)",
        .refreshCollectionHelp: "Refresh Collection (⌘R)",
        .collectionActions: "Collection Actions",
        .scanningCollection: "Scanning collection…",
        .selectCollection: "Select a Collection",
        .nothingFound: "Nothing Found",
        .tryAnotherQuery: "Try a different query or filter.",
        .resetFilters: "Reset Filters",
        .showingRange: "Showing %@",
        .searchQuote: "“%@”",
        .emptyNoManga: "No Manga in This Collection",
        .emptyAddFolders: "Add manga folders to this collection — they will appear here automatically.",
        .unavailableCollectionTitle: "Collection Folder Is Unavailable",
        .checking: "Checking…",
        .filterAll: "All",
        .filterReading: "Reading",
        .filterCompleted: "Completed",
        .statusUnread: "NEW",
        .statusReading: "READING",
        .statusCompleted: "COMPLETED",
        .read: "Read",
        .continueAction: "Continue",
        .restart: "Start Over",
        .chaptersMenu: "Chapters",
        .markUnread: "Mark as Unread",
        .markRead: "Mark as Read",
        .continueHeader: "CONTINUE READING",
        .continueMeta: "%1$@ · p. %2$d of %3$d",
        .layoutSingle: "Single Page",
        .layoutSpread: "Spread",
        .layoutWebtoon: "Webtoon",
        .fitHeight: "Fit Height",
        .fitWidth: "Fit Width",
        .fitOriginal: "Actual Size",
        .fitHeightShort: "Height",
        .fitWidthShort: "Width",
        .directionLTR: "Left to Right",
        .directionRTL: "Right to Left",
        .library: "Library",
        .backToLibraryHelp: "Back to Library (Esc)",
        .fit: "Fit",
        .direction: "Direction",
        .zoom: "Zoom",
        .mode: "Mode",
        .page: "Page",
        .fitModeHelp: "Fit mode (H / W / O)",
        .zoomInHelp: "Zoom In (⌘+)",
        .zoomOutHelp: "Zoom Out (⌘−)",
        .resetZoomHelp: "Reset Zoom (0 or ⌘0)",
        .goToPageHelp: "Go to Page (G)",
        .previousChapterHelp: "Previous Chapter (⌘← or [)",
        .nextChapterHelp: "Next Chapter (⌘→ or ])",
        .previousPageLeftHelp: "Previous Page (←)",
        .nextPageLeftHelp: "Next Page (←)",
        .previousPageRightHelp: "Previous Page (→)",
        .nextPageRightHelp: "Next Page (→)",
        .controlsHelp: "Controls & Shortcuts (?)",
        .fullScreenHelp: "Full Screen (F)",
        .loadingChapter: "Loading chapter",
        .pageEntryHint: "Enter — go · Esc — cancel",
        .openPageFailed: "Couldn't open page\n%@",
        .toastLastChapter: "This is the last chapter in the collection",
        .toastFirstChapter: "This is the first chapter in the collection",
        .toastNextUp: "Next: %@",
        .toastInvalidPage: "Enter a page from 1 to %d",
        .exitFullScreenHelp: "Exit Full Screen (F)",
        .showSidebarHelp: "Show Sidebar (⌘\\)",
        .hideSidebarHelp: "Hide Sidebar (⌘\\)",
        .helpTitle: "Controls",
        .helpSubtitle: "cheat sheet",
        .helpClose: "Close (Esc)",
        .helpKeyboard: "KEYBOARD",
        .helpMouse: "MOUSE & TRACKPAD",
        .helpFooter:
            "In RTL, arrows and click zones are mirrored. Keys are read by physical position, so the layout doesn't matter.",
        .helpPageBackForward: "Page back / forward",
        .helpPageReadingOrder: "Same in reading order",
        .helpScreenForward: "Screen or page forward",
        .helpScreenBackward: "Screen or page back",
        .helpScrollWebtoon: "Scroll (webtoon) / page",
        .helpFirstLastPage: "First / last page",
        .helpChapterBackForward: "Chapter back / forward",
        .helpLayoutModes: "Page / spread / webtoon",
        .helpDirection: "Direction RTL ↔ LTR",
        .helpFitModes: "Fit height / width / 1:1",
        .helpZoom: "Zoom / reset to 100%",
        .helpGoToPage: "Go to page",
        .helpFullScreen: "Full screen",
        .helpThisSheet: "This cheat sheet",
        .helpToLibrary: "Back to library",
        .helpClickSides: "Click left / right",
        .helpDoubleClickCenter: "Double-click in the center",
        .helpSmartZoom: "2.5× and back",
        .helpWheel: "Wheel",
        .helpWheelAction: "Page if everything fits; otherwise scroll",
        .helpCommandWheel: "⌘ + wheel",
        .helpZoomToCursor: "Zoom to cursor",
        .helpDrag: "Dragging",
        .helpDragAction: "Pan when zoomed or on a long page",
        .helpSideButtons: "Side buttons",
        .helpRightClick: "Right-click",
        .helpCommandMenu: "Command menu",
        .helpPinch: "Pinch",
        .helpPinchAction: "Zoom; two fingers pan when zoomed",
        .helpTwoFingerSwipe: "Two-finger swipe",
        .helpTwoFingerSwipeAction: "Horizontal turns the page; pans when zoomed",
        .helpLeftEdge: "Left edge",
        .helpLeftEdgeAction: "Full-height panel: modes, pages, slider",
        .scanUnreadable: "Couldn't read folder %@",
        .scanNotDirectory: "%@ is not a folder",
        .decodeCannotOpen: "Couldn't open %@",
        .decodeCannotDecode: "Couldn't decode %@",
        .decodeCannotReadSize: "Couldn't read the size of %@",
        .rangeEmpty: "0 of 0",
        .rangeLabel: "%1$d–%2$d of %3$d",
        .addCollectionsTitle: "Add Collections",
        .addCollectionsMessage: "Choose one or more folders with manga or chapters.",
        .addCollectionsPrompt: "Add",
        .alreadyAdded: "These collections are already added.",
        .collectionUnavailable: "Collection folder is unavailable: %@",
        .missingProjectPath: "The --project option needs a folder path.",
        .countPageOne: "page",
        .countPageFew: "pages",
        .countPageMany: "pages",
        .countPageOther: "pages",
        .countChapterOne: "chapter",
        .countChapterFew: "chapters",
        .countChapterMany: "chapters",
        .countChapterOther: "chapters",
        .countMangaOne: "manga",
        .countMangaFew: "manga",
        .countMangaMany: "manga",
        .countMangaOther: "manga",
        .countCollectionOne: "collection",
        .countCollectionFew: "collections",
        .countCollectionMany: "collections",
        .countCollectionOther: "collections",
        .compactPage: "p.",
        .compactChapter: "ch.",
    ]

    /// Russian translations. A missing key falls back to English.
    static let russian: [LocKey: String] = [
        .ok: "Хорошо",
        .errorTitle: "Ошибка",
        .refresh: "Обновить",
        .checkAgain: "Проверить снова",
        .revealInFinder: "Показать в Finder",
        .removeFromApp: "Убрать из приложения",
        .addCollection: "Добавить коллекцию",
        .refreshCollection: "Обновить коллекцию",
        .defaultCollectionName: "Коллекция",
        .folderUnavailable: "Папка недоступна",
        .previousPage: "Предыдущая страница",
        .nextPage: "Следующая страница",
        .previousChapter: "Предыдущая глава",
        .nextChapter: "Следующая глава",
        .goToPage: "Перейти к странице…",
        .closeWindow: "Закрыть окно",
        .minimizeWindow: "Свернуть",
        .fullScreen: "Полный экран",
        .zoomIn: "Увеличить",
        .zoomOut: "Уменьшить",
        .resetZoom: "Сбросить масштаб",
        .backToLibrary: "В библиотеку",
        .openControls: "Управление…",
        .menuAbout: "О Mangla",
        .menuHide: "Скрыть Mangla",
        .menuHideOthers: "Скрыть остальные",
        .menuShowAll: "Показать все",
        .menuQuit: "Завершить Mangla",
        .menuFile: "Файл",
        .menuAddCollection: "Добавить коллекцию…",
        .menuCloseReader: "Закрыть читалку",
        .menuEdit: "Правка",
        .menuUndo: "Отменить",
        .menuRedo: "Повторить",
        .menuCut: "Вырезать",
        .menuCopy: "Копировать",
        .menuPaste: "Вставить",
        .menuSelectAll: "Выбрать всё",
        .menuReading: "Чтение",
        .menuView: "Вид",
        .menuToggleSidebar: "Показать/скрыть панель",
        .menuActualSize: "Фактический размер",
        .menuWindow: "Окно",
        .menuWindowZoom: "Масштаб",
        .menuHelp: "Справка",
        .menuReaderControls: "Управление читалкой",
        .welcomeTagline: "Тихая, быстрая читалка манги для macOS",
        .welcomeDescription:
            "Добавьте одну или несколько папок-коллекций — приложение будет держать их открытыми одновременно.",
        .welcomeHowItWorks: "Как это работает",
        .welcomeFooter: "Нативный AppKit · ProMotion",
        .structureCollection: "Коллекция",
        .structureAnyFolder: "любая папка",
        .structureManga: "Манга",
        .structureNamedFolder: "папка с названием",
        .structureChapter: "Глава",
        .structureImagesOrSubfolders: "картинки или подпапки",
        .collectionsHeader: "КОЛЛЕКЦИИ",
        .collectionHeader: "КОЛЛЕКЦИЯ",
        .searchPlaceholder: "Поиск в коллекции",
        .addCollectionHelp: "Добавить коллекцию (⌘O)",
        .refreshCollectionHelp: "Обновить коллекцию (⌘R)",
        .collectionActions: "Действия с коллекцией",
        .scanningCollection: "Сканирую коллекцию…",
        .selectCollection: "Выберите коллекцию",
        .nothingFound: "Ничего не найдено",
        .tryAnotherQuery: "Попробуйте изменить запрос или фильтр.",
        .resetFilters: "Сбросить фильтры",
        .showingRange: "Показано %@",
        .searchQuote: "«%@»",
        .emptyNoManga: "В коллекции нет манги",
        .emptyAddFolders: "Добавьте папки с мангой в эту коллекцию — они появятся здесь автоматически.",
        .unavailableCollectionTitle: "Папка коллекции недоступна",
        .checking: "Проверяю…",
        .filterAll: "Все",
        .filterReading: "Читаю",
        .filterCompleted: "Прочитано",
        .statusUnread: "НОВОЕ",
        .statusReading: "ЧИТАЮ",
        .statusCompleted: "ПРОЧИТАНО",
        .read: "Читать",
        .continueAction: "Продолжить",
        .restart: "Начать сначала",
        .chaptersMenu: "Главы",
        .markUnread: "Отметить непрочитанным",
        .markRead: "Отметить прочитанным",
        .continueHeader: "ПРОДОЛЖИТЬ ЧТЕНИЕ",
        .continueMeta: "%1$@ · стр. %2$d из %3$d",
        .layoutSingle: "Одна страница",
        .layoutSpread: "Разворот",
        .layoutWebtoon: "Webtoon",
        .fitHeight: "По высоте окна",
        .fitWidth: "По ширине окна",
        .fitOriginal: "Оригинальный размер",
        .fitHeightShort: "Высота",
        .fitWidthShort: "Ширина",
        .directionLTR: "Слева направо",
        .directionRTL: "Справа налево",
        .library: "Библиотека",
        .backToLibraryHelp: "Вернуться в библиотеку (Esc)",
        .fit: "Вписать",
        .direction: "Направление",
        .zoom: "Масштаб",
        .mode: "Режим",
        .page: "Страница",
        .fitModeHelp: "Режим вписывания (H / W / O)",
        .zoomInHelp: "Увеличить (⌘+)",
        .zoomOutHelp: "Уменьшить (⌘−)",
        .resetZoomHelp: "Сбросить масштаб (0 или ⌘0)",
        .goToPageHelp: "Перейти к странице (G)",
        .previousChapterHelp: "Предыдущая глава (⌘← или [)",
        .nextChapterHelp: "Следующая глава (⌘→ или ])",
        .previousPageLeftHelp: "Предыдущая страница (←)",
        .nextPageLeftHelp: "Следующая страница (←)",
        .previousPageRightHelp: "Предыдущая страница (→)",
        .nextPageRightHelp: "Следующая страница (→)",
        .controlsHelp: "Управление и горячие клавиши (?)",
        .fullScreenHelp: "Полный экран (F)",
        .loadingChapter: "Загрузка главы",
        .pageEntryHint: "Enter — перейти · Esc — отмена",
        .openPageFailed: "Не удалось открыть страницу\n%@",
        .toastLastChapter: "Это последняя глава в коллекции",
        .toastFirstChapter: "Это первая глава в коллекции",
        .toastNextUp: "Дальше: %@",
        .toastInvalidPage: "Введите страницу от 1 до %d",
        .exitFullScreenHelp: "Выйти из полного экрана (F)",
        .showSidebarHelp: "Показать панель (⌘\\)",
        .hideSidebarHelp: "Скрыть панель (⌘\\)",
        .helpTitle: "Управление",
        .helpSubtitle: "шпаргалка",
        .helpClose: "Закрыть (Esc)",
        .helpKeyboard: "КЛАВИАТУРА",
        .helpMouse: "МЫШЬ И ТРЕКПАД",
        .helpFooter:
            "В RTL стрелки и клик-зоны зеркальны. Нажатия читаются по физическим клавишам, поэтому раскладка не важна.",
        .helpPageBackForward: "Страница назад / вперёд",
        .helpPageReadingOrder: "То же в порядке чтения",
        .helpScreenForward: "Экран или страница вперёд",
        .helpScreenBackward: "Экран или страница назад",
        .helpScrollWebtoon: "Прокрутка (webtoon) / страница",
        .helpFirstLastPage: "Первая / последняя страница",
        .helpChapterBackForward: "Глава назад / вперёд",
        .helpLayoutModes: "Страница / разворот / webtoon",
        .helpDirection: "Направление RTL ↔ LTR",
        .helpFitModes: "Вписать по высоте / ширине / 1:1",
        .helpZoom: "Зум / сброс к 100%",
        .helpGoToPage: "Перейти к странице",
        .helpFullScreen: "Полный экран",
        .helpThisSheet: "Эта шпаргалка",
        .helpToLibrary: "В библиотеку",
        .helpClickSides: "Клик слева / справа",
        .helpDoubleClickCenter: "Двойной клик в центре",
        .helpSmartZoom: "2.5× и обратно",
        .helpWheel: "Колесо",
        .helpWheelAction: "Страница, если всё помещается; иначе прокрутка",
        .helpCommandWheel: "⌘ + колесо",
        .helpZoomToCursor: "Зум к курсору",
        .helpDrag: "Перетаскивание",
        .helpDragAction: "Панорама при зуме и длинной странице",
        .helpSideButtons: "Боковые кнопки",
        .helpRightClick: "Правый клик",
        .helpCommandMenu: "Меню команд",
        .helpPinch: "Пинч",
        .helpPinchAction: "Зум; два пальца при зуме — панорама",
        .helpTwoFingerSwipe: "Свайп двумя пальцами",
        .helpTwoFingerSwipeAction: "Горизонтально — страница; при зуме — панорама",
        .helpLeftEdge: "Левый край",
        .helpLeftEdgeAction: "Панель на всю высоту: режимы, страницы, слайдер",
        .scanUnreadable: "Не удалось прочитать папку %@",
        .scanNotDirectory: "%@ не является папкой",
        .decodeCannotOpen: "Не удалось открыть %@",
        .decodeCannotDecode: "Не удалось декодировать %@",
        .decodeCannotReadSize: "Не удалось прочитать размер %@",
        .rangeEmpty: "0 из 0",
        .rangeLabel: "%1$d–%2$d из %3$d",
        .addCollectionsTitle: "Добавить коллекции",
        .addCollectionsMessage: "Выберите одну или несколько папок с мангой или главами.",
        .addCollectionsPrompt: "Добавить",
        .alreadyAdded: "Эти коллекции уже добавлены.",
        .collectionUnavailable: "Папка коллекции недоступна: %@",
        .missingProjectPath: "Для параметра --project нужен путь к папке.",
        .countPageOne: "страница",
        .countPageFew: "страницы",
        .countPageMany: "страниц",
        .countPageOther: "страниц",
        .countChapterOne: "глава",
        .countChapterFew: "главы",
        .countChapterMany: "глав",
        .countChapterOther: "глав",
        .countMangaOne: "манга",
        .countMangaFew: "манги",
        .countMangaMany: "манг",
        .countMangaOther: "манг",
        .countCollectionOne: "коллекция",
        .countCollectionFew: "коллекции",
        .countCollectionMany: "коллекций",
        .countCollectionOther: "коллекций",
        .compactPage: "стр.",
        .compactChapter: "гл.",
    ]
}
