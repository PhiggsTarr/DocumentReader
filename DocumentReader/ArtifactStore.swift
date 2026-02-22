//
//  ArtifactStore.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/17/26.
//

import Foundation

enum ArtifactStore {

    // MARK: - Models

    struct BundleResult: Codable, Equatable, Identifiable {
        var id: String { "\(versionNumber)-\(pdfFilename)" }

        let versionNumber: Int
        let title: String
        let createdAt: Date

        let pdfFilename: String
        let analysisFilename: String
        let zipFilename: String?
    }

    struct Manifest: Codable {
        var conversationId: String
        var updatedAt: Date
        var bundles: [BundleResult]
    }

    // MARK: - Paths

    /// Documents/Artifacts/<conversationId>/
    static func conversationFolder(id: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func manifestURL(conversationId: String) throws -> URL {
        let folder = try conversationFolder(id: conversationId)
        return folder.appendingPathComponent("manifest").appendingPathExtension("json")
    }

    // MARK: - Save

    /// Saves:
    /// - Version-N-Title.pdf
    /// - Version-N-Title.json
    /// - (optional) Version-N-Title.zip   <-- only if you pass zipData
    /// - manifest.json (appends entry)
    static func saveBundle(
        conversationId: String,
        versionNumber: Int,
        title: String,
        pdfData: Data,
        analysisJSON: Data,
        zipData: Data? = nil
    ) throws -> BundleResult {

        let folder = try conversationFolder(id: conversationId)

        let safeTitle = sanitizeFilename(title.isEmpty ? "Draft-Response" : title)
        let base = "Version-\(versionNumber)-\(safeTitle)"

        let pdfFilename = base + ".pdf"
        let analysisFilename = base + ".json"
        let zipFilename = zipData != nil ? (base + ".zip") : nil

        let pdfURL = folder.appendingPathComponent(pdfFilename)
        let analysisURL = folder.appendingPathComponent(analysisFilename)

        try pdfData.write(to: pdfURL, options: [.atomic])
        try analysisJSON.write(to: analysisURL, options: [.atomic])

        if let zipData, let zipFilename {
            let zipURL = folder.appendingPathComponent(zipFilename)
            try zipData.write(to: zipURL, options: [.atomic])
        }

        let entry = BundleResult(
            versionNumber: versionNumber,
            title: title.isEmpty ? "Draft Response" : title,
            createdAt: Date(),
            pdfFilename: pdfFilename,
            analysisFilename: analysisFilename,
            zipFilename: zipFilename
        )

        try upsertManifest(conversationId: conversationId, adding: entry)
        return entry
    }

    // MARK: - Load

    static func loadManifest(conversationId: String) -> Manifest? {
        do {
            let url = try manifestURL(conversationId: conversationId)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder.iso8601.decode(Manifest.self, from: data)
        } catch {
            return nil
        }
    }

    static func listBundles(conversationId: String) -> [BundleResult] {
        loadManifest(conversationId: conversationId)?.bundles ?? []
    }

    static func resolvePDFURL(conversationId: String, pdfFilename: String) throws -> URL {
        let folder = try conversationFolder(id: conversationId)
        return folder.appendingPathComponent(pdfFilename)
    }

    static func resolveAnalysisURL(conversationId: String, analysisFilename: String) throws -> URL {
        let folder = try conversationFolder(id: conversationId)
        return folder.appendingPathComponent(analysisFilename)
    }

    static func resolveZipURL(conversationId: String, zipFilename: String) throws -> URL {
        let folder = try conversationFolder(id: conversationId)
        return folder.appendingPathComponent(zipFilename)
    }

    // MARK: - Manifest

    private static func upsertManifest(conversationId: String, adding entry: BundleResult) throws {
        let url = try manifestURL(conversationId: conversationId)

        var manifest = loadManifest(conversationId: conversationId) ?? Manifest(
            conversationId: conversationId,
            updatedAt: Date(),
            bundles: []
        )

        if let idx = manifest.bundles.firstIndex(where: { $0.versionNumber == entry.versionNumber }) {
            manifest.bundles[idx] = entry
        } else {
            manifest.bundles.append(entry)
        }

        manifest.bundles.sort { $0.versionNumber < $1.versionNumber }
        manifest.updatedAt = Date()

        let data = try JSONEncoder.iso8601.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Utils

    private static func sanitizeFilename(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
        return String(cleaned.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ISO8601 Codable

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
