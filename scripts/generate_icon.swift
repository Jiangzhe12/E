#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Minimal "letter E on a squircle gradient" icon, three variants:
//   pending        — blue gradient (default state)
//   completed      — green gradient (after today's learning is done)
//   completed-glow — green gradient + soft radial glow behind the letter
//                    (one frame of the completion pulse animation)
//
// Generates a 1024×1024 PNG. `build_app.sh` then downsamples into an .icns.

enum IconGenerationError: LocalizedError {
    case invalidArguments
    case unknownVariant(String)
    case contextUnavailable
    case bitmapExportFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: swift scripts/generate_icon.swift <output_png_path> <pending|completed|completed-glow>"
        case .unknownVariant(let value):
            return "Unknown icon variant: \(value)"
        case .contextUnavailable:
            return "Failed to create graphics context"
        case .bitmapExportFailed:
            return "Failed to export PNG data"
        }
    }
}

enum IconVariant: String {
    case pending
    case completed
    case completedGlow = "completed-glow"

    var isCompleted: Bool {
        self != .pending
    }
}

private struct Palette {
    let top: NSColor
    let bottom: NSColor
    let glow: NSColor
}

private func palette(for variant: IconVariant) -> Palette {
    switch variant {
    case .pending:
        // Deep ocean → bright azure. Reads as "ready, working" without looking cold.
        return Palette(
            top: NSColor(calibratedRed: 0.28, green: 0.56, blue: 0.96, alpha: 1),
            bottom: NSColor(calibratedRed: 0.09, green: 0.27, blue: 0.68, alpha: 1),
            glow: NSColor.clear
        )
    case .completed, .completedGlow:
        // Fresh mint → forest. Clearly "done" but not harsh.
        return Palette(
            top: NSColor(calibratedRed: 0.36, green: 0.82, blue: 0.60, alpha: 1),
            bottom: NSColor(calibratedRed: 0.08, green: 0.50, blue: 0.34, alpha: 1),
            glow: NSColor(calibratedRed: 0.82, green: 1.0, blue: 0.90, alpha: 0.70)
        )
    }
}

private func drawBackground(context: CGContext, canvas: CGRect, palette: Palette) {
    let cornerRadius: CGFloat = 236 // ~iOS/macOS squircle ratio for 832-side inner canvas
    let squircle = CGPath(
        roundedRect: canvas,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(squircle)
    context.clip()

    // Diagonal gradient, top-left (lighter) → bottom-right (deeper).
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray,
        locations: [0.0, 1.0]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: canvas.minX, y: canvas.maxY),
            end: CGPoint(x: canvas.maxX, y: canvas.minY),
            options: []
        )
    }

    // Very subtle top highlight so the gradient doesn't look flat.
    context.setFillColor(NSColor.white.withAlphaComponent(0.09).cgColor)
    context.fillEllipse(
        in: CGRect(
            x: canvas.minX - 120,
            y: canvas.maxY - 360,
            width: canvas.width + 240,
            height: 520
        )
    )

    context.restoreGState()

    // Hairline stroke keeps the silhouette crisp on light backgrounds.
    context.saveGState()
    context.addPath(squircle)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()
}

private func drawGlowBehindLetter(context: CGContext, canvas: CGRect, color: NSColor) {
    context.saveGState()
    let squircle = CGPath(
        roundedRect: canvas,
        cornerWidth: 236,
        cornerHeight: 236,
        transform: nil
    )
    context.addPath(squircle)
    context.clip()

    context.setBlendMode(.screen)
    let diameter: CGFloat = 700
    let glowRect = CGRect(
        x: canvas.midX - diameter / 2,
        y: canvas.midY - diameter / 2,
        width: diameter,
        height: diameter
    )
    if let radial = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color.cgColor,
            color.withAlphaComponent(0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        context.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
            startRadius: 0,
            endCenter: CGPoint(x: glowRect.midX, y: glowRect.midY),
            endRadius: diameter / 2,
            options: []
        )
    }
    context.setBlendMode(.normal)
    context.restoreGState()
}

private func drawLetter(context _: CGContext, side: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let font = NSFont.systemFont(ofSize: 560, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: -4 // slightly tighter — single letter, but heavy bowl feels better snug
    ]
    let attrString = NSAttributedString(string: "E", attributes: attributes)
    let textSize = attrString.size()

    // Nudge down ~4% to optically center a letter without descender.
    let rect = CGRect(
        x: (side - textSize.width) / 2,
        y: (side - textSize.height) / 2 - side * 0.04,
        width: textSize.width,
        height: textSize.height
    )
    attrString.draw(in: rect)
}

private func generateIcon(outputPath: String, variant: IconVariant) throws {
    let side: CGFloat = 1024
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw IconGenerationError.contextUnavailable
    }

    // Inset keeps the squircle slightly away from the 1024 edges — matches the
    // padding Apple uses for Dock tile previews.
    let inset: CGFloat = 96
    let canvas = CGRect(
        x: inset,
        y: inset,
        width: side - inset * 2,
        height: side - inset * 2
    )

    let pal = palette(for: variant)
    drawBackground(context: context, canvas: canvas, palette: pal)

    if variant == .completedGlow {
        drawGlowBehindLetter(context: context, canvas: canvas, color: pal.glow)
    }

    drawLetter(context: context, side: side)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.bitmapExportFailed
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
    print("Generated \(variant.rawValue) icon at: \(outputURL.path)")
}

do {
    let args = CommandLine.arguments.dropFirst()
    guard args.count == 2 else {
        throw IconGenerationError.invalidArguments
    }
    let outputPath = String(args[args.startIndex])
    let variantRaw = String(args[args.index(after: args.startIndex)])

    guard let variant = IconVariant(rawValue: variantRaw) else {
        throw IconGenerationError.unknownVariant(variantRaw)
    }

    try generateIcon(outputPath: outputPath, variant: variant)
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
