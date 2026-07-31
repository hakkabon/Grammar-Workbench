#!/usr/bin/env swift
import AppKit
import Foundation

let arguments: [String]
if let separator = CommandLine.arguments.lastIndex(of: "--") {
    arguments = Array(CommandLine.arguments.suffix(from: CommandLine.arguments.index(after: separator)))
} else {
    arguments = Array(CommandLine.arguments.suffix(2))
}
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift OUTPUT_ICONSET OUTPUT_ICNS\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
let icnsOutput = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

func circle(center: CGPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
}

for (name, pixels) in variants {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Could not allocate icon bitmap") }
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    let tile = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 210, yRadius: 210)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.10, blue: 0.38, alpha: 1)
    ])!.draw(in: tile, angle: -45)

    let root = CGPoint(x: 512, y: 760)
    let left = CGPoint(x: 300, y: 500)
    let right = CGPoint(x: 724, y: 500)
    let leaf = CGPoint(x: 512, y: 250)
    let edge = NSBezierPath()
    edge.lineWidth = 54
    edge.lineCapStyle = .round
    edge.move(to: root); edge.line(to: left)
    edge.move(to: root); edge.line(to: right)
    edge.move(to: left); edge.line(to: leaf)
    edge.move(to: right); edge.line(to: leaf)
    NSColor(calibratedRed: 0.34, green: 0.84, blue: 0.94, alpha: 1).setStroke()
    edge.stroke()

    let halo = NSColor(calibratedRed: 0.56, green: 0.42, blue: 0.98, alpha: 1)
    for point in [root, left, right, leaf] { circle(center: point, radius: 104, color: halo) }
    let core = NSColor(calibratedWhite: 0.98, alpha: 1)
    for point in [root, left, right, leaf] { circle(center: point, radius: 58, color: core) }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
    try data.write(to: output.appendingPathComponent(name), options: .atomic)
}

let chunks: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_128x128@2x.png"),
    ("ic09", "icon_256x256@2x.png"),
    ("ic10", "icon_512x512@2x.png")
]
func bigEndian(_ value: Int) -> Data {
    var encoded = UInt32(value).bigEndian
    return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}
var icns = Data("icns".utf8) + Data(repeating: 0, count: 4)
for (type, filename) in chunks {
    let png = try Data(contentsOf: output.appendingPathComponent(filename))
    icns.append(Data(type.utf8))
    icns.append(bigEndian(png.count + 8))
    icns.append(png)
}
icns.replaceSubrange(4..<8, with: bigEndian(icns.count))
try icns.write(to: icnsOutput, options: .atomic)
