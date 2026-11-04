#!/usr/bin/env swift
// Renders contracts/app-icon/*.svg into the iOS app icon. Run from the repository root:
//   swift ios/scripts/render-app-icon.swift
// iOS has one dark slot, so it uses black.svg. dark.svg (navy) is for Android and marketing.
import AppKit

let size = 1024
let outputs = [
    "light": "AppIcon-Light",
    "black": "AppIcon-Dark",
    "tinted": "AppIcon-Tinted",
]
let folder = "ios/Wingspot/Resources/Assets.xcassets/AppIcon.appiconset"

for (source, output) in outputs {
    guard let image = NSImage(contentsOfFile: "contracts/app-icon/\(source).svg") else {
        fatalError("Can't read \(source).svg")
    }
    // No alpha channel: App Store Connect rejects app icons that have one.
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Can't create the drawing surface")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.current = nil

    let pixels = UnsafeBufferPointer(
        start: context.data!.assumingMemoryBound(to: UInt32.self), count: context.bytesPerRow / 4 * size
    )
    guard Set(pixels.prefix(pixels.count)).count > 1 else {
        fatalError("\(source).svg rendered as a single color")
    }

    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: "\(folder)/\(output).png"))
}
