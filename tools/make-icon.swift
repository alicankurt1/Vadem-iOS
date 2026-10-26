#!/usr/bin/env swift
// Uygulama ikonunu (açık, koyu, renklendirilmiş) CoreGraphics ile çizer.
// Kullanım: swift tools/make-icon.swift [çıktı klasörü]
// Varsayılan çıktı: Vadem/Assets.xcassets/AppIcon.appiconset
//
// Kurallar: 1024x1024, opak (alfa yok), köşeler yuvarlatılmaz (sistem maskeler).
// Motif: eğik duran bir kart; üstünde şerit, altında taksit dilimleri (3/5 dolu),
// yani "bu ay ne ödüyorum" sorusunun görsel karşılığı.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Vadem/Assets.xcassets/AppIcon.appiconset"

// 0xRRGGBB değerinden sRGB renk.
func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gray(_ white: CGFloat) -> CGColor {
    CGColor(gray: white, alpha: 1)
}

// Bir varyantın renkleri.
struct Palette {
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    var cardTop: CGColor
    var cardBottom: CGColor
    var stripe: CGColor
    var segmentFilled: CGColor
    var segmentEmpty: CGColor
    var shadow: CGColor
}

let light = Palette(
    backgroundTop: rgb(0x14B8A6),
    backgroundBottom: rgb(0x0F766E),
    cardTop: rgb(0xFFFFFF),
    cardBottom: rgb(0xECFDF5),
    stripe: rgb(0x115E59),
    segmentFilled: rgb(0x047857),
    segmentEmpty: rgb(0xA7F3D0),
    shadow: rgb(0x022C22, alpha: 0.35)
)

let dark = Palette(
    backgroundTop: rgb(0x0B1120),
    backgroundBottom: rgb(0x022C22),
    cardTop: rgb(0x14B8A6),
    cardBottom: rgb(0x0F766E),
    stripe: rgb(0x022C22),
    segmentFilled: rgb(0xECFDF5),
    segmentEmpty: rgb(0x115E59),
    shadow: rgb(0x000000, alpha: 0.5)
)

// Renklendirilmiş varyant: siyah zemin üzerinde gri tonlar; sistem renklendirir.
let tinted = Palette(
    backgroundTop: gray(0),
    backgroundBottom: gray(0),
    cardTop: gray(1),
    cardBottom: gray(0.85),
    stripe: gray(0.25),
    segmentFilled: gray(0.25),
    segmentEmpty: gray(0.65),
    shadow: CGColor(gray: 0, alpha: 0)
)

func draw(_ palette: Palette, in context: CGContext, colorSpace: CGColorSpace) {
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Zemin: yukarıdan aşağı degrade.
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 0, y: full.maxY),
        end: CGPoint(x: full.maxX, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Kart: merkezde, hafif eğik.
    context.saveGState()
    context.translateBy(x: full.midX, y: full.midY)
    context.rotate(by: 8 * .pi / 180)

    let cardWidth: CGFloat = 640
    let cardHeight: CGFloat = 420
    let card = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 56, cornerHeight: 56, transform: nil)

    // Gölge.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 48, color: palette.shadow)
    context.addPath(cardPath)
    context.setFillColor(palette.cardBottom)
    context.fillPath()
    context.restoreGState()

    // Kart yüzü: degrade.
    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    let cardGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [palette.cardTop, palette.cardBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        cardGradient,
        start: CGPoint(x: 0, y: card.maxY),
        end: CGPoint(x: 0, y: card.minY),
        options: []
    )

    // Manyetik şerit.
    context.setFillColor(palette.stripe)
    context.fill(CGRect(x: card.minX, y: card.maxY - 140, width: card.width, height: 76))
    context.restoreGState()

    // Taksit dilimleri: 5 dilimin 3'ü dolu.
    let segmentCount = 5
    let filledCount = 3
    let inset: CGFloat = 64
    let gap: CGFloat = 20
    let segmentHeight: CGFloat = 56
    let segmentWidth = (card.width - 2 * inset - CGFloat(segmentCount - 1) * gap) / CGFloat(segmentCount)
    for index in 0..<segmentCount {
        let rect = CGRect(
            x: card.minX + inset + CGFloat(index) * (segmentWidth + gap),
            y: card.minY + 72,
            width: segmentWidth,
            height: segmentHeight
        )
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        context.addPath(path)
        context.setFillColor(index < filledCount ? palette.segmentFilled : palette.segmentEmpty)
        context.fillPath()
    }

    context.restoreGState()
}

func render(_ palette: Palette, grayscale: Bool, to fileName: String) throws {
    let colorSpace = grayscale
        ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        : CGColorSpace(name: CGColorSpace.sRGB)!
    // Alfa kanalı yok: App Store ikonu opak olmalı.
    let bitmapInfo = grayscale
        ? CGImageAlphaInfo.none.rawValue
        : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "context"])
    }
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    draw(palette, in: context, colorSpace: colorSpace)

    guard let image = context.makeImage() else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "image"])
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(fileName)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw NSError(domain: "make-icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-icon", code: 4, userInfo: [NSLocalizedDescriptionKey: "write"])
    }
    print("wrote \(url.path)")
}

try render(light, grayscale: false, to: "AppIcon.png")
try render(dark, grayscale: false, to: "AppIcon-Dark.png")
try render(tinted, grayscale: true, to: "AppIcon-Tinted.png")
