#!/usr/bin/env swift

// Renders the macOS app icon for Moves. The glyph is U+265E (BLACK CHESS
// KNIGHT, ♞) on a flat-white rounded-square — the modern macOS look. Runs
// as a one-shot script: emits a .iconset directory and prints the
// `iconutil` command the caller should run to package it into .icns.
//
// Usage:
//   swift scripts/make-icon.swift            # writes build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
//
// The script is self-contained — no SwiftPM, no Xcode. Run from the
// project root.

import AppKit
import Foundation

let outDir = "build/AppIcon.iconset"
let icnsPath = "build/AppIcon.icns"
let glyph = "\u{265E}" // BLACK CHESS KNIGHT — ♞

// macOS icon spec: each logical size has a @1x and a @2x file. iconutil
// reads filenames literally, so the table below is the source of truth.
let sizes: [(name: String, pixels: Int)] = [
  ("icon_16x16.png",      16),
  ("icon_16x16@2x.png",   32),
  ("icon_32x32.png",      32),
  ("icon_32x32@2x.png",   64),
  ("icon_128x128.png",    128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png",    256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png",    512),
  ("icon_512x512@2x.png", 1024),
]

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, px) in sizes {
  let size = CGFloat(px)
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()

  guard let ctx = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write("no graphics context for \(name)\n".data(using: .utf8)!)
    exit(1)
  }
  ctx.setShouldAntialias(true)
  ctx.interpolationQuality = .high

  // Rounded-square background. macOS Big Sur+ icons use a "squircle"
  // shape with corner radius ≈ 22.5% of the inner edge length, inset
  // slightly from the canvas so it doesn't clip on hover/zoom contexts.
  let inset = size * 0.04
  let bgRect = NSRect(x: inset, y: inset,
                       width:  size - 2 * inset,
                       height: size - 2 * inset)
  let cornerRadius = (size - 2 * inset) * 0.225
  let bg = NSBezierPath(roundedRect: bgRect,
                        xRadius: cornerRadius,
                        yRadius: cornerRadius)
  NSColor.white.setFill()
  bg.fill()

  // Subtle 1pt edge so the icon reads against light docks.
  NSColor.black.withAlphaComponent(0.08).setStroke()
  bg.lineWidth = max(1, size / 256)
  bg.stroke()

  // Center the chess knight glyph. Empirically the ♞ glyph in the
  // system font sits slightly above the baseline midpoint, so we nudge
  // it down ~3% for visual centering. The font is .heavy so the figure
  // reads well even at 16×16.
  let fontSize = size * 0.66
  let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.black,
    .paragraphStyle: paragraph,
  ]
  let attr = NSAttributedString(string: glyph, attributes: attrs)
  let glyphSize = attr.size()
  // Use cap-height-based vertical alignment: NSAttributedString.size()
  // includes leading, which leaves the visible glyph slightly above
  // center. -3% trim corrects it across the size range.
  let originY = (size - glyphSize.height) / 2 - size * 0.03
  let drawRect = NSRect(
    x: (size - glyphSize.width) / 2,
    y: originY,
    width:  glyphSize.width,
    height: glyphSize.height
  )
  attr.draw(in: drawRect)

  image.unlockFocus()

  guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
  else {
    FileHandle.standardError.write("PNG encode failed for \(name)\n".data(using: .utf8)!)
    exit(1)
  }

  let url = URL(fileURLWithPath: "\(outDir)/\(name)")
  try png.write(to: url)
  print("✓ \(name) (\(px)×\(px))")
}

print("")
print("Wrote iconset → \(outDir)")
print("Now run:    iconutil -c icns \(outDir) -o \(icnsPath)")
