import AppKit
import MacPetCore

@MainActor
enum ReleaseVerification {
    static func run() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "MacPet.release-test.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: temporary)
            preferences.removePersistentDomain(forName: suite)
        }
        PetAsset.supportDirectory = temporary
        PetExpressions.preferences = preferences
        PetExpressions.restoreSelection()
        let entries = PetExpressions.entries().filter { $0.id != PetExpressions.legacyID }
        guard entries.count == 9, PetExpressions.isActive, PetExpressions.playbackSpeed == 0.5 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for entry in entries {
            try PetExpressions.select(entry)
            PetExpressions.advance(at: Date().addingTimeInterval(0.5))
            guard PetExpressions.image != nil, let url = entry.url else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let animation = try PetAnimation(url: url)
            print("PASS \(entry.name): \(animation.frames.count) frames")
        }
        let deleted = entries[0]
        try FileManager.default.removeItem(at: deleted.url!.deletingLastPathComponent())
        try PetExpressions.installBundledExpressions()
        guard !PetExpressions.entries().contains(where: { $0.id == deleted.id }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        PetExpressions.restoreSelection()
        guard PetExpressions.isActive else { throw CocoaError(.fileReadCorruptFile) }
        print("PASS fresh installation, all 9 animations, half speed, no resurrection after deletion")
    }
}
