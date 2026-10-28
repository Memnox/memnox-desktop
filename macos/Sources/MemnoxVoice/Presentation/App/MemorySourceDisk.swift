import Foundation
import MemnoxVoiceCore

/// The Add source sheet's reads of this disk: what a path is and the notes under it, and a Notion zip unzipped beside
/// itself. Nothing here decides what is read; it only gathers what `MemoryImport` needs to say so before adding.
enum MemorySourceDisk {
    /// The most files one look lists, enough to count a person's notes without stalling the sheet on a huge tree.
    private static let mostLooked = 2_000
    /// How deep a look goes, the runtime's own bound on its walk.
    private static let mostDepth = 8
    private static let ditto = "/usr/bin/ditto"

    /// Every path looked at off the main thread, since a large folder takes a moment to walk.
    static func look(_ paths: [String], kind: MemorySourceKind) async -> [PathLook] {
        await Task.detached(priority: .userInitiated) {
            paths.map { MemorySourceDisk.look($0, kind: kind) }
        }.value
    }

    private static func look(_ path: String, kind: MemorySourceKind) -> PathLook {
        guard LaunchLines.isAbsoluteFolder(path) else { return PathLook(path: path, kind: .missing) }
        let files = FileManager.default
        var folder: ObjCBool = false
        guard files.fileExists(atPath: path, isDirectory: &folder) else { return PathLook(path: path, kind: .missing) }
        let readable = files.isReadableFile(atPath: path)
        guard folder.boolValue else {
            let regular = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            return PathLook(path: path, kind: regular ? .file : .other, readable: readable)
        }
        guard readable else { return PathLook(path: path, kind: .folder, readable: false) }
        let (found, cut) = kind == .instructions ? instructionFiles(path) : notes(under: path, kind: kind)
        return PathLook(path: path, kind: .folder, found: found, cut: cut)
    }

    private static func notes(under root: String, kind: MemorySourceKind) -> ([String], Bool) {
        let base = URL(fileURLWithPath: root, isDirectory: true)
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return ([], false)
        }
        var found: [String] = []
        let prefix = base.standardizedFileURL.path + "/"
        while let url = walk.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                if walk.level >= mostDepth || MemoryImport.skippedFolders.contains(url.lastPathComponent) { walk.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            let relative = full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : url.lastPathComponent
            if MemoryImport.counts(relativePath: relative, kind: kind) { found.append(relative) }
            if found.count >= mostLooked { return (found.sorted(), true) }
        }
        return (found.sorted(), false)
    }

    private static func instructionFiles(_ root: String) -> ([String], Bool) {
        let files = FileManager.default
        var found = MemoryImport.instructionNames.filter { files.fileExists(atPath: (root as NSString).appendingPathComponent($0)) }
        let rules = (root as NSString).appendingPathComponent(MemoryImport.cursorRules)
        let inRules = ((try? files.contentsOfDirectory(atPath: rules)) ?? []).sorted()
            .map { "\(MemoryImport.cursorRules)/\($0)" }
            .filter { MemoryImport.counts(relativePath: $0, kind: .instructions) }
        found += inRules
        return (found, false)
    }

    /// Unzips a Notion export into a folder beside it, as Finder would, and the zips Notion nests inside it too. A folder
    /// already there by that name is taken as this export unzipped before, so nothing is written over.
    static func unzip(_ zip: String) async -> Result<String, UnzipFailure> {
        await Task.detached(priority: .userInitiated) {
            let into = (zip as NSString).deletingPathExtension
            let files = FileManager.default
            var folder: ObjCBool = false
            if files.fileExists(atPath: into, isDirectory: &folder) {
                return folder.boolValue ? .success(into) : .failure(UnzipFailure(reason: "\(MemoryImport.lastPart(into)) is already a file beside the zip."))
            }
            if let failure = MemorySourceDisk.run(zip, into: into) { return .failure(failure) }
            // Notion splits a large export into part zips inside the first one.
            let inner = ((try? files.contentsOfDirectory(atPath: into)) ?? []).filter(MemoryImport.isZip)
            for part in inner {
                let path = (into as NSString).appendingPathComponent(part)
                if let failure = MemorySourceDisk.run(path, into: into) { return .failure(failure) }
                try? files.removeItem(atPath: path)
            }
            return .success(into)
        }.value
    }

    private static func run(_ zip: String, into folder: String) -> UnzipFailure? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ditto)
        process.arguments = ["-x", "-k", zip, folder]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return UnzipFailure(reason: "macOS could not start unzipping it.")
        }
        return process.terminationStatus == 0 ? nil : UnzipFailure(reason: "\(MemoryImport.lastPart(zip)) could not be unzipped.")
    }
}

/// Why a Notion zip was not unzipped, said under the field.
struct UnzipFailure: Error, Equatable {
    let reason: String
}
