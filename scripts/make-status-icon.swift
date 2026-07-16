#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: make-status-icon.swift <src.png> <size> <out.png>\n", stderr)
    exit(1)
}

let srcPath = CommandLine.arguments[1]
let size = Int(CommandLine.arguments[2])!
let outPath = CommandLine.arguments[3]

guard let src = NSImage(contentsOfFile: srcPath) else {
    fputs("Failed to load \(srcPath)\n", stderr)
    exit(1)
}

guard let outRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outRep)
NSGraphicsContext.current?.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let inset = CGFloat(size) * 0.06
src.draw(
    in: NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2),
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0
)

NSGraphicsContext.restoreGraphicsState()

for y in 0..<size {
    for x in 0..<size {
        guard let c = outRep.colorAt(x: x, y: y) else { continue }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        if a < 0.05 || lum > 0.88 {
            outRep.setColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
        } else {
            let alpha = min(1.0, (1.0 - lum) * a * 1.2 + (1.0 - lum) * 0.85)
            outRep.setColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: min(1, max(0.35, alpha))), atX: x, y: y)
        }
    }
}

guard let png = outRep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
