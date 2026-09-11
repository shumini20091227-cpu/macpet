import Foundation

public enum PetCharacterStore {
    public static let fileName = "custom_character.png"

    public static func supportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacPet", isDirectory: true)
    }

    public static func customImageURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public static func hasCustomImage(in directory: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: customImageURL(in: directory).path)
    }

    public static func resolvedImageURL(
        directory: URL,
        bundled: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        let custom = customImageURL(in: directory)
        if fileManager.fileExists(atPath: custom.path) {
            return custom
        }
        return bundled.first { fileManager.fileExists(atPath: $0.path) }
    }

    public static func install(
        from source: URL,
        into directory: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = customImageURL(in: directory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    public static func removeCustom(in directory: URL, fileManager: FileManager = .default) throws {
        let destination = customImageURL(in: directory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }
}
