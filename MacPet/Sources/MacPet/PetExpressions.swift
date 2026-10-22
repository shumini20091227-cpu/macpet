import AppKit
import MacPetCore

@MainActor
enum PetExpressions {
    struct Entry {
        let id: String
        let name: String
        let url: URL?
    }
    static let legacyID = "legacy"
    static var preferences = UserDefaults.standard
    private struct Pack: Decodable {
        struct Expression: Decodable {
            let id: String
            let name: String
            let file: String
        }
        let defaultExpressionID: String
        let expressions: [Expression]
    }
    private static var bundledPack: Pack? {
        guard let url = PetAsset.bundledURLs(named: "expression-pack.json").first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Pack.self, from: data)
    }

    static func installBundledExpressions() throws {
        guard let pack = bundledPack else { return }
        let key = "installedPackExpressionIDs"
        var installed = Set(preferences.stringArray(forKey: key) ?? [])
        for entry in pack.expressions where !installed.contains(entry.id) {
            guard UUID(uuidString: entry.id) != nil,
                  URL(fileURLWithPath: entry.file).lastPathComponent == entry.file,
                  let source = PetAsset.bundledURLs(named: entry.file).first(where: {
                      FileManager.default.fileExists(atPath: $0.path)
                  }) else { throw CocoaError(.fileReadCorruptFile) }
            let folder = directory.appendingPathComponent(entry.id, isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    let file = folder.appendingPathComponent(entry.name)
                        .appendingPathExtension(source.pathExtension)
                    try Data(contentsOf: source).write(to: file, options: .atomic)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
            }
            installed.insert(entry.id)
            preferences.set(Array(installed).sorted(), forKey: key)
        }
    }
    private static let selectionKey = "selectedExpression"
    private(set) static var selectedID = ""
    private static var animation: PetAnimation?
    private static var images: [NSImage] = []
    private static var startedAt = Date()
    static let playbackSpeeds: [(String, Double)] = [
        ("很慢（0.25×）", 0.25), ("舒缓（0.5×，默认）", 0.5),
        ("稍慢（0.75×）", 0.75), ("原速（1×）", 1.0)
    ]
    private(set) static var playbackSpeed: Double = {
        let saved = preferences.double(forKey: "expressionPlaybackSpeed")
        return [0.25, 0.5, 0.75, 1.0].contains(saved) ? saved : 0.5
    }()

    static func setPlaybackSpeed(_ speed: Double, at date: Date = Date()) {
        guard playbackSpeeds.contains(where: { $0.1 == speed }) else { return }
        // Preserve the current animation position when changing speed.
        let elapsed = max(0, date.timeIntervalSince(startedAt)) * playbackSpeed
        startedAt = date.addingTimeInterval(-elapsed / speed)
        playbackSpeed = speed
        preferences.set(speed, forKey: "expressionPlaybackSpeed")
        advance(at: date)
    }
    private(set) static var frameIndex = 0
    static var isActive: Bool { animation != nil }
    static var image: NSImage? { images.isEmpty ? nil : images[frameIndex] }
    static var cgImage: CGImage? { animation?.frames[frameIndex] }
    private static var directory: URL {
        PetAsset.supportDirectory.appendingPathComponent("Expressions", isDirectory: true)
    }

    static func entries() -> [Entry] {
        var result = [Entry(id: legacyID, name: "原版形象", url: nil)]
        if bundledPack == nil, !preferences.bool(forKey: "hideBundledThinking"),
           let bundled = PetAsset.bundledURLs(named: "思考中.gif").first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            result.append(Entry(id: "bundled-thinking", name: "思考中", url: bundled))
        }
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)) ?? []
        var imported: [Entry] = []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: nil)) ?? []
            for file in files where ["gif", "png"].contains(file.pathExtension.lowercased()) {
                imported.append(Entry(id: folder.lastPathComponent,
                    name: file.deletingPathExtension().lastPathComponent, url: file))
            }
        }
        result += imported.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    static func restoreSelection() {
        do { try installBundledExpressions() }
        catch { NSLog("Unable to install bundled expressions: %@", error.localizedDescription) }
        let all = entries()
        let saved = preferences.string(forKey: selectionKey)
        let preferred = all.first(where: { $0.id == saved })
            ?? all.first(where: { $0.id == bundledPack?.defaultExpressionID })
            ?? all.first(where: { $0.id == "bundled-thinking" }) ?? all[0]
        do { try select(preferred) } catch { try? select(all[0]) }
    }

    static func select(_ entry: Entry) throws {
        // Failed decoding leaves the current pet intact.
        let next = try entry.url.map { try PetAnimation(url: $0) }
        animation = next
        images = next?.frames.map { NSImage(cgImage: $0, size: .zero) } ?? []
        frameIndex = 0
        startedAt = Date()
        selectedID = entry.id
        preferences.set(entry.id, forKey: selectionKey)
    }

    static var energySaving: Bool {
        get { preferences.object(forKey: "energySaving") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "energySaving") }
    }

    static func nextFrameDelay(at date: Date, maximumFPS: Double) -> TimeInterval? {
        animation?.nextFrameDelay(
            elapsed: date.timeIntervalSince(startedAt) * playbackSpeed,
            speed: playbackSpeed, maximumFPS: maximumFPS)
    }

    static func advance(at date: Date) {
        frameIndex = animation?.frameIndex(elapsed: date.timeIntervalSince(startedAt) * playbackSpeed) ?? 0
    }

    static func remove(_ entry: Entry) throws {
        guard entry.id != legacyID else { return }
        try removeFile(entry)
        selectRemainingIfNeeded()
    }

    static func remove(_ entries: [Entry]) -> [String] {
        var failures: [String] = []
        for entry in entries where entry.id != legacyID {
            do { try removeFile(entry) } catch { failures.append(entry.name) }
        }
        selectRemainingIfNeeded()
        return failures
    }

    private static func removeFile(_ entry: Entry) throws {
        if entry.id == "bundled-thinking" {
            preferences.set(true, forKey: "hideBundledThinking")
        } else {
            guard UUID(uuidString: entry.id) != nil else { throw CocoaError(.fileNoSuchFile) }
            let folder = directory.appendingPathComponent(entry.id, isDirectory: true)
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    private static func selectRemainingIfNeeded() {
        let remaining = entries()
        if !remaining.contains(where: { $0.id == selectedID }) {
            let fallback = remaining.first(where: { $0.id != legacyID }) ?? remaining[0]
            do { try select(fallback) } catch { try? select(remaining[0]) }
        }
    }

    static func importExpression(from url: URL) throws -> Entry {
        _ = try PetAnimation(url: url)
        let id = UUID().uuidString
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do { try FileManager.default.copyItem(at: url, to: destination) }
        catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return Entry(id: id, name: url.deletingPathExtension().lastPathComponent, url: destination)
    }
}
