import CoreText
import Foundation
import Observation

struct Emoji: Identifiable, Hashable {
    let id: Int
    let char: String
    let en: String
    let fr: String
    let group: Int
    let tones: [String]?
    fileprivate let nameTokens: [String]
    fileprivate let keywordTokens: [String]
    fileprivate let names: [String]

    static func == (a: Emoji, b: Emoji) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func name(french: Bool) -> String { french && !fr.isEmpty ? fr : en }

    func display(tone: Int) -> String {
        guard tone > 0, let tones, tones.count == 5 else { return char }
        return tones[tone - 1]
    }
}

struct EmojiGroup {
    let en: String
    let fr: String
    let symbol: String

    static let all: [EmojiGroup] = [
        .init(en: "Smileys & Emotion", fr: "Smileys et émotions", symbol: "face.smiling"),
        .init(en: "People & Body", fr: "Personnes et corps", symbol: "hand.wave"),
        .init(en: "Animals & Nature", fr: "Animaux et nature", symbol: "leaf"),
        .init(en: "Food & Drink", fr: "Nourriture et boissons", symbol: "fork.knife"),
        .init(en: "Travel & Places", fr: "Voyages et lieux", symbol: "car"),
        .init(en: "Activities", fr: "Activités", symbol: "soccerball"),
        .init(en: "Objects", fr: "Objets", symbol: "lightbulb"),
        .init(en: "Symbols", fr: "Symboles", symbol: "heart"),
        .init(en: "Flags", fr: "Drapeaux", symbol: "flag"),
    ]
}

/// The emoji index (English + French names and keywords from Unicode CLDR), loaded once in the background.
@Observable
final class EmojiStore {
    static let shared = EmojiStore()
    private(set) var all: [Emoji] = []
    @ObservationIgnored private(set) var byChar: [String: Emoji] = [:]

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let emoji = Self.read()
            var byChar: [String: Emoji] = [:]
            for e in emoji {
                byChar[e.char] = e
                e.tones?.forEach { byChar[$0] = e }
            }
            DispatchQueue.main.async {
                self.all = emoji
                self.byChar = byChar
            }
        }
    }

    func loadNow() {
        all = Self.read()
        for e in all { byChar[e.char] = e }
    }

    private static func read() -> [Emoji] {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        let font = CTFontCreateUIFontForLanguage(.system, 27, nil)!
        var out: [Emoji] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            guard row.count == 7, let char = row[0] as? String, isRenderable(char, font: font),
                  let en = row[1] as? String, let fr = row[2] as? String,
                  let enKw = row[3] as? String, let frKw = row[4] as? String, let group = row[5] as? Int else { continue }
            let tones = (row[6] as? [String]).map { $0.filter { isRenderable($0, font: font) } }
            out.append(Emoji(
                id: out.count, char: char, en: en, fr: fr, group: group,
                tones: tones?.count == 5 ? tones : nil,
                nameTokens: tokens(en + " " + fr),
                keywordTokens: tokens(enKw + " " + frKw),
                names: [fold(en), fold(fr)]))
        }
        return out
    }

    /// Supported emoji are drawn by Apple Color Emoji as one visible glyph. Emoji newer than the
    /// installed font fall back to LastResort (a box) or split into several glyphs, so they're hidden.
    private static func isRenderable(_ s: String, font: CTFont) -> Bool {
        let attr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attr)
        var visible = 0
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attrs[kCTFontAttributeName] as! CTFont?,
                  (CTFontCopyPostScriptName(runFont) as String).contains("AppleColorEmoji") else { return false }
            let count = CTRunGetGlyphCount(run)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
            visible += advances.filter { $0.width > 0.5 }.count
        }
        return visible == 1
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
    }

    private static func tokens(_ s: String) -> [String] {
        Array(Set(fold(s).split { !$0.isLetter && !$0.isNumber }.map(String.init)))
    }

    /// Every query word must prefix-match a name or keyword word (in either language).
    func search(_ query: String) -> [Emoji] {
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        let terms = q.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !terms.isEmpty else {
            return all.filter { $0.char.contains(query.trimmingCharacters(in: .whitespaces)) }
        }
        var scored: [(Emoji, Int)] = []
        for e in all {
            var score = 0
            for term in terms {
                if e.nameTokens.contains(term) { score += 4 }
                else if e.nameTokens.contains(where: { $0.hasPrefix(term) }) { score += 3 }
                else if e.keywordTokens.contains(term) { score += 2 }
                else if e.keywordTokens.contains(where: { $0.hasPrefix(term) }) { score += 1 }
                else { score = -1; break }
            }
            guard score >= 0 else { continue }
            if e.names.contains(q) { score += 20 } else if e.names.contains(where: { $0.hasPrefix(q) }) { score += 8 }
            scored.append((e, score))
        }
        // Equal scores: shorter names are usually the more "canonical" emoji (❤️ before 💘).
        return scored.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.names[0].count != $1.0.names[0].count { return $0.0.names[0].count < $1.0.names[0].count }
            return $0.0.id < $1.0.id
        }.map(\.0)
    }
}
