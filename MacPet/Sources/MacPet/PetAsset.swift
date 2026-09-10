import AppKit

@MainActor
enum PetAsset {
    private static var cachedImage: NSImage?
    private static var cachedCGImage: CGImage?
    private static var cachedPixelSize: CGSize?

    static func characterImage() -> NSImage? {
        if let cachedImage { return cachedImage }
        for url in candidateURLs {
            if FileManager.default.fileExists(atPath: url.path),
               let image = NSImage(contentsOf: url) {
                image.cacheMode = .always
                cachedImage = image
                return image
            }
        }
        return nil
    }

    static func characterCGImage() -> CGImage? {
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
        if let cachedPixelSize { return cachedPixelSize }
        guard let cgImage = characterCGImage() else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private static var candidateURLs: [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default
        if let resource = Bundle.main.resourceURL {
            urls.append(resource.appendingPathComponent("pet_character.png"))
            urls.append(resource.appendingPathComponent("MacPet_MacPet.bundle/pet_character.png"))
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(executableDirectory.appendingPathComponent("MacPet_MacPet.bundle/pet_character.png"))
            urls.append(executableDirectory.appendingPathComponent("pet_character.png"))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/pet_character.png"))
        urls.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Sources/MacPet/Resources/pet_character.png"))
        return urls
    }
}
