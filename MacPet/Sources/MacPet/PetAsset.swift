import AppKit
import MacPetCore

@MainActor
enum PetAsset {
    private static var cachedImage: NSImage?
    private static var cachedCGImage: CGImage?
    private static var cachedPixelSize: CGSize?
    private static var cachedStudyImage: NSImage?
    private static var cachedStudyCGImage: CGImage?

    static var supportDirectory: URL = PetCharacterStore.supportDirectory()

    static func reload() {
        cachedImage = nil
        cachedCGImage = nil
        cachedPixelSize = nil
        cachedStudyImage = nil
        cachedStudyCGImage = nil
    }

    static func hasCustomCharacter() -> Bool {
        PetCharacterStore.hasCustomImage(in: supportDirectory)
    }

    static func characterImage() -> NSImage? {
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

    static func usesStudyArt(state: PetState, isEditingGlints: Bool) -> Bool {
        state == .study && !isEditingGlints && !hasCustomCharacter() && studyImage() != nil
    }

    static func displayedImage(state: PetState, isEditingGlints: Bool) -> NSImage? {
        if usesStudyArt(state: state, isEditingGlints: isEditingGlints) {
            return studyImage()
        }
        return characterImage()
    }

    static func displayedCGImage(state: PetState, isEditingGlints: Bool) -> CGImage? {
        if usesStudyArt(state: state, isEditingGlints: isEditingGlints) {
            return studyCGImage() ?? characterCGImage()
        }
        return characterCGImage()
    }

    static func studyImage() -> NSImage? {
        if let cachedStudyImage { return cachedStudyImage }
        guard let url = bundledURLs(named: "pet_study.png").first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.cacheMode = .always
        cachedStudyImage = image
        return image
    }

    static func studyCGImage() -> CGImage? {
        if let cachedStudyCGImage { return cachedStudyCGImage }
        guard let image = studyImage(),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        cachedStudyCGImage = cgImage
        return cgImage
    }

    private static var bundledURLs: [URL] {
        bundledURLs(named: "pet_character.png")
    }

    private static func bundledURLs(named fileName: String) -> [URL] {
        var urls: [URL] = []
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
