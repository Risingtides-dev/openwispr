import Foundation
import os

private let cloudSyncLog = Logger(subsystem: "dev.smathdaddy.openwispr", category: "CloudNotesSync")

enum KordCloudNotesSync {
    static let containerIdentifier = "iCloud.dev.smathdaddy.kord"

    private static let folderName = "Kord"
    private static let fileName = "notes-sync.json"

    struct Result {
        var notes: [OpenwisprNote]
        var tombstones: [KordNoteTombstone]
    }

    private struct Envelope: Codable {
        var schema: Int
        var updatedAt: Double
        var sourceDevice: String
        var notes: [OpenwisprNote]
        var deletedNotes: [KordNoteTombstone]
    }

    @discardableResult
    static func syncFromStore() throws -> Result {
        let localNotes = SharedConfig.notes
        let localTombstones = SharedConfig.noteTombstones
        let result = try sync(localNotes: localNotes, localTombstones: localTombstones)
        KordStore.shared.replaceNotesAndTombstones(notes: result.notes, tombstones: result.tombstones)
        return result
    }

    @discardableResult
    static func sync(localNotes: [OpenwisprNote], localTombstones: [KordNoteTombstone]) throws -> Result {
        let url = try syncFileURL()
        let remote = try readEnvelope(at: url)
        let merged = merge(
            localNotes: localNotes,
            localTombstones: localTombstones,
            remoteNotes: remote?.notes ?? [],
            remoteTombstones: remote?.deletedNotes ?? []
        )
        let envelope = Envelope(
            schema: 1,
            updatedAt: Date().timeIntervalSince1970 * 1000,
            sourceDevice: "iOS",
            notes: merged.notes,
            deletedNotes: merged.tombstones
        )
        try write(envelope, to: url)
        cloudSyncLog.info("notes synced count=\(merged.notes.count, privacy: .public) deleted=\(merged.tombstones.count, privacy: .public)")
        return merged
    }

    private static func syncFileURL() throws -> URL {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw NSError(
                domain: "kord.cloudsync",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud is not available for Kord on this device."]
            )
        }
        let folder = root.appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    private static func readEnvelope(at url: URL) throws -> Envelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Envelope.self, from: data)
    }

    private static func write(_ envelope: Envelope, to url: URL) throws {
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: [.atomic])
    }

    private static func merge(
        localNotes: [OpenwisprNote],
        localTombstones: [KordNoteTombstone],
        remoteNotes: [OpenwisprNote],
        remoteTombstones: [KordNoteTombstone]
    ) -> Result {
        var tombstonesByID: [String: KordNoteTombstone] = [:]
        for tombstone in localTombstones + remoteTombstones {
            if let existing = tombstonesByID[tombstone.id], existing.deletedAt >= tombstone.deletedAt {
                continue
            }
            tombstonesByID[tombstone.id] = tombstone
        }

        var notesByID: [String: OpenwisprNote] = [:]
        for note in localNotes + remoteNotes {
            if let tombstone = tombstonesByID[note.id], tombstone.deletedAt >= note.updatedAt {
                continue
            }
            if let existing = notesByID[note.id], existing.updatedAt > note.updatedAt {
                continue
            }
            notesByID[note.id] = note
        }

        for (id, tombstone) in tombstonesByID {
            if let note = notesByID[id], tombstone.deletedAt >= note.updatedAt {
                notesByID.removeValue(forKey: id)
            }
        }

        let notes = Array(notesByID.values)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(SharedConfig.maxNotes)
        let tombstones = Array(tombstonesByID.values)
            .sorted { $0.deletedAt > $1.deletedAt }
            .prefix(1000)

        return Result(notes: Array(notes), tombstones: Array(tombstones))
    }
}
