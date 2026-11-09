import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** A file to send to a server: its name there, where it is here, its type. */
public struct Upload: Sendable {
    public let name: String
    public let file: URL
    public let mime: String
    public init(name: String, file: URL, mime: String) { self.name = name; self.file = file; self.mime = mime }

    /** The type a file's ending says. */
    public static func mime(_ name: String) -> String {
        switch (name.split(separator: ".").last.map(String.init) ?? "").lowercased() {
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "flac": return "audio/flac"
        case "opus", "ogg": return "audio/ogg"
        case "mp3": return "audio/mpeg"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "lrc", "txt": return "text/plain"
        case "yaml", "yml": return "application/yaml"
        default: return "application/octet-stream"
        }
    }
}

/** POST /api/songs's answer: added, or skipped (the server has it), the extras it kept, the song. */
public struct Uploaded: Sendable {
    public let added: Bool
    public let skipped: Bool
    public let song: ServerSong?
}

/** POST /api/songs/ID/parts's answer: the parts it kept, the ones it had already, the song now. */
public struct PartsAdded: Sendable {
    public let added: [String]
    public let skipped: [String]
    public let song: ServerSong?
}

extension Rms {
    /**
     * Adds a song to the server (rms/README.md): its file, its details, its cover and lyrics when there are.
     * [partsComing]: its parts follow (the server doesn't split it itself). A song the server has is skipped.
     */
    public func upload(song: Upload, artist: String, title: String, seconds: Int, cover: Upload?, lyrics: Upload?,
                       partsComing: Bool) async throws -> Uploaded {
        var fields: [(String, String)] = [("artist", artist), ("title", title)]
        if seconds > 0 { fields.append(("seconds", "\(seconds)")) }
        var files = [("song", song)]
        if let cover { files.append(("cover", cover)) }
        if let lyrics { files.append(("lyrics", lyrics)) }
        let o = try await multipart(partsComing ? "/api/songs?parts=coming" : "/api/songs", fields: fields, files: files)
        return Uploaded(added: o.flag("added"), skipped: o.flag("skipped"), song: o["song"].flatMap { ServerSong.from($0, id) })
    }

    /** A song split on this iPhone brings its parts to the server's copy of it ([song]: its id). */
    public func uploadParts(song: Int64, parts: [String: Upload], lyrics: Upload? = nil) async throws -> PartsAdded {
        var files = parts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        if let lyrics { files.append(("lyrics", lyrics)) }
        let o = try await multipart("/api/songs/\(song)/parts", fields: [], files: files)
        return PartsAdded(added: (o["added"]?.array ?? []).compactMap { $0.string }, skipped: (o["skipped"]?.array ?? []).compactMap { $0.string },
                          song: o["song"].flatMap { ServerSong.from($0, id) })
    }

    /** A multipart form, written to a file first (a big song never sits in memory), sent, and its answer read. */
    func multipart(_ path: String, fields: [(String, String)], files: [(String, Upload)]) async throws -> JSON {
        let boundary = "radiance-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: body.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: body) }
        let out = try FileHandle(forWritingTo: body)
        func text(_ s: String) throws { try out.write(contentsOf: Data(s.utf8)) }
        for (k, v) in fields {
            try text("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n")
        }
        for (k, f) in files {
            let safe = f.name.replacingOccurrences(of: "\"", with: "'")
            try text("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"; filename=\"\(safe)\"\r\nContent-Type: \(f.mime)\r\n\r\n")
            let input = try FileHandle(forReadingFrom: f.file)
            while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { try out.write(contentsOf: chunk) }
            try input.close()
            try text("\r\n")
        }
        try text("--\(boundary)--\r\n")
        try out.close()
        var r = try request(path, method: "POST")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 600
        let (data, response): (Data, HTTPURLResponse) = try await withCheckedThrowingContinuation { cont in
            Http.session.uploadTask(with: r, fromFile: body) { data, resp, err in
                if let err { return cont.resume(throwing: err) }
                guard let http = resp as? HTTPURLResponse else { return cont.resume(throwing: Plain("Something went wrong. Try again.", "no HTTP answer")) }
                cont.resume(returning: (data ?? Data(), http))
            }.resume()
        }
        return try Rms.answer(response.statusCode, data)
    }
}
