import Foundation
import AppKit

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: inputPath),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let cgImage = bitmap.cgImage else {
    fputs("Failed to load \(inputPath)\n", stderr)
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let bitsPerComponent = 8
let colorSpace = CGColorSpaceCreateDeviceRGB()
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: bitsPerComponent,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create context\n", stderr)
    exit(1)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

func isEmptyCanvas(_ offset: Int) -> Bool {
    let r = Int(pixels[offset])
    let g = Int(pixels[offset + 1])
    let b = Int(pixels[offset + 2])
    let a = Int(pixels[offset + 3])
    if a < 16 { return true }
    // Dark shoes, hair, and outlines stay. Only punch the empty canvas.
    return a < 40 && r < 5 && g < 5 && b < 5 && (r + g + b) < 8
}

var visited = [Bool](repeating: false, count: width * height)
var queue: [Int] = []

func enqueue(_ x: Int, _ y: Int) {
    guard x >= 0, y >= 0, x < width, y < height else { return }
    let index = y * width + x
    if visited[index] { return }
    visited[index] = true
    let offset = index * bytesPerPixel
    if isEmptyCanvas(offset) {
        queue.append(index)
    }
}

enqueue(0, 0)
enqueue(width - 1, 0)
enqueue(0, height - 1)
enqueue(width - 1, height - 1)

var head = 0
while head < queue.count {
    let index = queue[head]
    head += 1
    let x = index % width
    let y = index / width
    let offset = index * bytesPerPixel
    pixels[offset] = 0
    pixels[offset + 1] = 0
    pixels[offset + 2] = 0
    pixels[offset + 3] = 0
    enqueue(x + 1, y)
    enqueue(x - 1, y)
    enqueue(x, y + 1)
    enqueue(x, y - 1)
}

guard let keyed = context.makeImage() else {
    fputs("Failed to export keyed image\n", stderr)
    exit(1)
}

let outputRep = NSBitmapImageRep(cgImage: keyed)
guard let png = outputRep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
