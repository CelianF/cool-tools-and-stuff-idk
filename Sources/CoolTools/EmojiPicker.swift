import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Floating Liquid Glass emoji picker. It's a non-activating panel, so the app you were typing in
/// stays frontmost and the chosen emoji is typed straight into it.
final class EmojiPicker: NSObject, NSWindowDelegate {
    static let shared = EmojiPicker()
    static let columns = 9
    static let size = NSSize(width: 412, height: 452)

    let model = PickerModel()
    private var keyMonitor: Any?
    private lazy var panel: KeyPanel = {
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let host = NSHostingView(rootView: EmojiPickerView(model: model, picker: self))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    var isOpen: Bool { panel.isVisible }

    func toggle() { isOpen ? close() : open() }

    func open() {
        model.reset()
        panel.setFrameOrigin(origin())
        panel.makeKeyAndOrderFront(nil)
        model.openCount += 1
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] in self?.handleKey($0) ?? $0 }
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    func insert(_ text: String, keepOpen: Bool = false) {
        AppSettings.shared.noteRecent(text)
        if !keepOpen { close() }
        DispatchQueue.main.asyncAfter(deadline: .now() + (keepOpen ? 0 : 0.05)) { EmojiTyper.type(text) }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let shift = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { insert(item.text, keepOpen: shift) }
        case kVK_LeftArrow: model.move(dx: -1, dy: 0)
        case kVK_RightArrow: model.move(dx: 1, dy: 0)
        case kVK_UpArrow: model.move(dx: 0, dy: -1)
        case kVK_DownArrow: model.move(dx: 0, dy: 1)
        default: return event
        }
        return nil
    }

    /// Below the text caret when the focused app exposes it, otherwise next to the mouse.
    private func origin() -> NSPoint {
        let size = Self.size
        let anchor = caretRect() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main!
        let frame = screen.visibleFrame
        var point = NSPoint(x: anchor.minX - 20, y: anchor.minY - size.height - 8)
        if point.y < frame.minY { point.y = anchor.maxY + 8 }
        point.x = min(max(point.x, frame.minX + 8), frame.maxX - size.width - 8)
        point.y = min(max(point.y, frame.minY + 8), frame.maxY - size.height - 8)
        return point
    }

    private func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        let el = element as! AXUIElement
        var range: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success, let bounds else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.origin != .zero || rect.height > 0 else { return nil }
        // AX uses top-left screen coordinates; flip to Cocoa's bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: max(rect.width, 1), height: rect.height)
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum EmojiTyper {
    /// Types text into the frontmost app as synthetic key events, without touching the clipboard.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.setIntegerValueField(.eventSourceUserData, value: KeyEngine.syntheticMarker)
                e.post(tap: .cghidEventTap)
            }
            chunk.removeAll()
        }
        for character in text {
            let units = Array(String(character).utf16)
            if chunk.count + units.count > 20 { flush() }
            chunk += units
        }
        flush()
    }
}

// MARK: - Model

struct PickerItem: Identifiable {
    let id: Int        // position in the flat list
    let text: String   // what gets typed (skin tone applied)
    let emoji: Emoji
}

struct PickerSection: Identifiable {
    let id: String
    let title: String
    let items: [PickerItem]
}

@Observable
final class PickerModel {
    var query = "" { didSet { if query != oldValue { rebuild(); selection = 0 } } }
    var selection = 0
    var openCount = 0
    var scrollTarget: Int?
    private(set) var sections: [PickerSection] = []
    @ObservationIgnored private var flat: [(section: Int, index: Int)] = []

    private var settings: AppSettings { .shared }
    var french: Bool { settings.emojiLanguage.isFrench }

    var selectedItem: PickerItem? {
        guard selection < flat.count else { return nil }
        let pos = flat[selection]
        return sections[pos.section].items[pos.index]
    }

    func reset() {
        query = ""
        rebuild()
        selection = 0
        scrollTarget = 0
    }

    func rebuild() {
        let store = EmojiStore.shared
        let tone = settings.skinTone
        var counter = 0
        func items(_ list: [(String, Emoji)]) -> [PickerItem] {
            list.map { text, emoji in
                defer { counter += 1 }
                return PickerItem(id: counter, text: text, emoji: emoji)
            }
        }
        var result: [PickerSection] = []
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            let recents = settings.recentEmoji.compactMap { s in store.byChar[s].map { (s, $0) } }
            if !recents.isEmpty {
                result.append(.init(id: "recent", title: french ? "Récents" : "Recently Used", items: items(recents)))
            }
            var groups = Array(repeating: [Emoji](), count: EmojiGroup.all.count)
            for e in store.all { groups[e.group].append(e) }
            for (i, list) in groups.enumerated() where !list.isEmpty {
                let group = EmojiGroup.all[i]
                result.append(.init(id: "g\(i)", title: french ? group.fr : group.en,
                                    items: items(list.map { ($0.display(tone: tone), $0) })))
            }
        } else {
            let hits = store.search(query)
            result.append(.init(id: "results", title: french ? "Résultats" : "Results",
                                items: items(hits.map { ($0.display(tone: tone), $0) })))
        }
        sections = result
        flat = result.enumerated().flatMap { s, section in section.items.indices.map { (s, $0) } }
    }

    /// Arrow-key navigation that respects section breaks in the grid.
    func move(dx: Int, dy: Int) {
        guard !flat.isEmpty else { return }
        let cols = EmojiPicker.columns
        var (s, i) = flat[min(selection, flat.count - 1)]
        if dx != 0 {
            selection = min(max(selection + dx, 0), flat.count - 1)
        } else {
            let col = i % cols
            if dy > 0 {
                if i + cols < sections[s].items.count { i += cols }
                else if i / cols < (sections[s].items.count - 1) / cols { i = sections[s].items.count - 1 }
                else if s + 1 < sections.count { s += 1; i = min(col, sections[s].items.count - 1) }
            } else {
                if i >= cols { i -= cols }
                else if s > 0 {
                    s -= 1
                    let count = sections[s].items.count
                    let lastRow = (count - 1) / cols
                    i = min(lastRow * cols + col, count - 1)
                }
            }
            selection = sections[s].items[i].id
        }
        scrollTarget = selection
    }
}

// MARK: - Views

private struct EmojiPickerView: View {
    @Bindable var model: PickerModel
    let picker: EmojiPicker
    @FocusState private var searchFocused: Bool
    @State private var store = EmojiStore.shared
    @State private var settings = AppSettings.shared

    private let grid = Array(repeating: GridItem(.fixed(40), spacing: 2), count: EmojiPicker.columns)

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if model.query.isEmpty { categoryBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: grid, spacing: 2) {
                        ForEach(model.sections) { section in
                            Section {
                                ForEach(section.items) { item in cell(item) }
                            } header: {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 8)
                                    .id(section.id)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    if model.sections.allSatisfy(\.items.isEmpty) && !store.all.isEmpty {
                        Text(model.french ? "Aucun emoji trouvé" : "No emoji found")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: model.scrollTarget) { _, target in
                    guard let target else { return }
                    if target == 0 { proxy.scrollTo(model.sections.first?.id, anchor: .top) }
                    else { proxy.scrollTo(target) }
                    model.scrollTarget = nil
                }
                .onChange(of: categoryJump) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
                    categoryJump = nil
                }
            }
            footer
        }
        .frame(width: EmojiPicker.size.width, height: EmojiPicker.size.height)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .onChange(of: model.openCount) { searchFocused = true }
        .onChange(of: store.all.count) { model.rebuild() }
        .onChange(of: settings.skinTone) { model.rebuild() }
        .onAppear { searchFocused = true }
    }

    @State private var categoryJump: String?

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(model.french ? "Rechercher un emoji" : "Search emoji", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding([.horizontal, .top], 12)
        .padding(.bottom, 6)
    }

    private var categoryBar: some View {
        HStack(spacing: 0) {
            if !settings.recentEmoji.isEmpty { categoryButton("clock", "recent") }
            ForEach(EmojiGroup.all.indices, id: \.self) { i in
                categoryButton(EmojiGroup.all[i].symbol, "g\(i)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func categoryButton(_ symbol: String, _ id: String) -> some View {
        Button { categoryJump = id } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func cell(_ item: PickerItem) -> some View {
        let selected = item.id == model.selection
        let base = Text(item.text)
            .font(.system(size: 27))
            .frame(width: 40, height: 40)
            .background {
                if selected { RoundedRectangle(cornerRadius: 9).fill(.tint.opacity(0.35)) }
            }
            .contentShape(.rect)
            .id(item.id)
            .onHover { if $0 { model.selection = item.id } }
            .onTapGesture { picker.insert(item.text, keepOpen: NSEvent.modifierFlags.contains(.shift)) }
        if let tones = item.emoji.tones {
            base.contextMenu {
                Button(item.emoji.char) { picker.insert(item.emoji.char) }
                ForEach(tones, id: \.self) { tone in Button(tone) { picker.insert(tone) } }
            }
        } else {
            base
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let item = model.selectedItem {
                Text(item.text).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.emoji.name(french: model.french).capitalizedFirst)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(item.emoji.name(french: !model.french).capitalizedFirst)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("⇧↩ keep open")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.primary.opacity(0.04))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
