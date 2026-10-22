import CoreGraphics
import Foundation
import ImageIO

public struct PetAnimation {
    public let frames: [CGImage]
    public let frameEnds: [TimeInterval]
    public let duration: TimeInterval

    public init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= 1000 else { throw CocoaError(.fileReadTooLarge) }
        var decoded: [CGImage] = []
        var ends: [TimeInterval] = []
        var elapsed: TimeInterval = 0
        var bytes = 0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            guard width > 0, height > 0, width <= 4096, height <= 4096 else {
                throw CocoaError(.fileReadTooLarge)
            }
            bytes += width * height * 4
            guard bytes <= 256 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            elapsed += delay.isFinite && delay >= 0.02 ? delay : 0.1
            // Normalize indexed GIF pixels to RGBA for transparent hit testing.
            guard let context = CGContext(data: nil, width: frame.width, height: frame.height,
                bitsPerComponent: 8, bytesPerRow: frame.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
            guard let rgba = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
            decoded.append(rgba)
            ends.append(elapsed)
        }
        frames = decoded
        frameEnds = ends
        duration = elapsed
    }

    /// No timer is needed for a static image. Frame limits skip frames without slowing the timeline.
    public func nextFrameDelay(elapsed: TimeInterval, speed: Double, maximumFPS: Double) -> TimeInterval? {
        guard frames.count > 1, speed.isFinite, speed > 0,
              maximumFPS.isFinite, maximumFPS > 0 else { return nil }
        let safeElapsed = elapsed.isFinite ? max(0, elapsed) : 0
        let position = safeElapsed.truncatingRemainder(dividingBy: duration)
        let index = frameIndex(elapsed: safeElapsed)
        let untilChange = (frameEnds[index] - position) / speed
        return max(1 / maximumFPS, untilChange + 0.001)
    }

    public func frameIndex(elapsed: TimeInterval) -> Int {
        guard elapsed.isFinite, elapsed >= 0 else { return 0 }
        let time = elapsed.truncatingRemainder(dividingBy: duration)
        return frameEnds.firstIndex(where: { time < $0 }) ?? 0
    }
}
