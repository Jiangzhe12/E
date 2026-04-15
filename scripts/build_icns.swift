#!/usr/bin/env swift
import Foundation

enum ICNSError: LocalizedError {
    case invalidArguments
    case missingFile(String)
    case invalidChunkType(String)
    case invalidPNG(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: swift scripts/build_icns.swift <iconset_dir> <output_icns_path>"
        case .missingFile(let path):
            return "Missing icon PNG: \(path)"
        case .invalidChunkType(let type):
            return "Invalid ICNS chunk type: \(type)"
        case .invalidPNG(let path):
            return "Invalid PNG file: \(path)"
        }
    }
}

private let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])

private func appendASCII(_ value: String, to data: inout Data) throws {
    guard value.utf8.count == 4, let bytes = value.data(using: .ascii) else {
        throw ICNSError.invalidChunkType(value)
    }
    data.append(bytes)
}

private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    var be = value.bigEndian
    withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
}

private func createChunk(type: String, pngData: Data) throws -> Data {
    var chunk = Data()
    try appendASCII(type, to: &chunk)
    appendUInt32BE(UInt32(pngData.count + 8), to: &chunk)
    chunk.append(pngData)
    return chunk
}

do {
    let args = CommandLine.arguments
    guard args.count == 3 else {
        throw ICNSError.invalidArguments
    }

    let iconsetDir = URL(fileURLWithPath: args[1], isDirectory: true)
    let outputPath = URL(fileURLWithPath: args[2], isDirectory: false)

    let entries: [(filename: String, type: String)] = [
        ("icon_16x16.png", "icp4"),
        ("icon_16x16@2x.png", "ic11"),
        ("icon_32x32.png", "icp5"),
        ("icon_32x32@2x.png", "ic12"),
        ("icon_128x128.png", "ic07"),
        ("icon_128x128@2x.png", "ic13"),
        ("icon_256x256.png", "ic08"),
        ("icon_256x256@2x.png", "ic14"),
        ("icon_512x512.png", "ic09"),
        ("icon_512x512@2x.png", "ic10")
    ]

    var allChunks = Data()

    for entry in entries {
        let path = iconsetDir.appendingPathComponent(entry.filename)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ICNSError.missingFile(path.path)
        }
        let pngData = try Data(contentsOf: path)
        guard pngData.starts(with: pngSignature) else {
            throw ICNSError.invalidPNG(path.path)
        }
        let chunk = try createChunk(type: entry.type, pngData: pngData)
        allChunks.append(chunk)
    }

    var icns = Data()
    try appendASCII("icns", to: &icns)
    appendUInt32BE(UInt32(allChunks.count + 8), to: &icns)
    icns.append(allChunks)

    try FileManager.default.createDirectory(
        at: outputPath.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try icns.write(to: outputPath)
    print("Generated icns at: \(outputPath.path)")
} catch {
    fputs("ICNS generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
