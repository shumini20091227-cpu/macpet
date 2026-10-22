import AppKit
import MacPetCore

@MainActor
enum PetAsset {
    private static var cachedImage: NSImage?
    private static var cachedCGImage: CGImage?
    private static var cachedPixelSize: CGSize?

    static var supportDirectory: URL = PetCharacterStore.supportDirectory()

    static func reload() {
        cachedImage = nil
        cachedCGImage = nil
        cachedPixelSize = nil
    }

    static func hasCustomCharacter() -> Bool {
        PetCharacterStore.hasCustomImage(in: supportDirectory)
    }

    static func characterImage() -> NSImage? {
        if PetExpressions.isActive { return PetExpressions.image }
        if let cachedImage { return cachedImage }
        guard let url = PetCharacterStore.resolvedImageURL(directory: supportDirectory, bundled: bundledURLs),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.cacheMode = .always
        cachedImage = image
        return image
    }

    static func characterCGImage() -> CGImage? {
        if PetExpressions.isActive { return PetExpressions.cgImage }
        if let cachedCGImage { return cachedCGImage }
        guard let image = characterImage(),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        cachedCGImage = cgImage
        cachedPixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        return cgImage
    }

    static func characterPixelSize() -> CGSize {
        if let image = PetExpressions.cgImage { return CGSize(width: image.width, height: image.height) }
        if let cachedPixelSize { return cachedPixelSize }
        guard let cgImage = characterCGImage() else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static var bundledURLs: [URL] {
        bundledURLs(named: "pet_character.png")
    }

    static func bundledURLs(named fileName: String) -> [URL] {
        var urls: [URL] = []
        if let resource = Bundle.module.resourceURL {
            urls.append(resource.appendingPathComponent(fileName))
        }
        let fileManager = FileManager.default
        if let resource = Bundle.main.resourceURL {
            urls.append(resource.appendingPathComponent(fileName))
            urls.append(resource.appendingPathComponent("MacPet_MacPet.bundle/\(fileName)"))
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(executableDirectory.appendingPathComponent("MacPet_MacPet.bundle/\(fileName)"))
            urls.append(executableDirectory.appendingPathComponent(fileName))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(fileName)"))
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Sources/MacPet/Resources/\(fileName)"))
        return urls
    }
}

