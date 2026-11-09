import Foundation

/**
 * A YouTube song through your Radiance Music Server (owner, 2026-11-09: "if not yet exists in server download from
 * youtube"; radiance-music#73): the server has it already, or gets it from YouTube (a job in its queue), and the
 * iPhone plays the server's copy. The iPhone never fetches YouTube's sound itself.
 */
public struct FetchAnswer: Equatable, Sendable {
    /** The server had it: here it is. */
    public let already: Bool
    public let queued: Bool
    public let song: ServerSong?
    public let job: Job?
}

extension Rms {
    /** POST /api/fetch: the server's copy of YouTube song [t], or its job getting it. */
    public func fetch(_ t: Track) async throws -> FetchAnswer {
        var body: [String: JSON] = ["youtube_id": .string(t.id), "artist": .string(t.artist), "title": .string(t.title)]
        if t.seconds > 0 { body["seconds"] = .number(Double(t.seconds)) }
        let o: JSON
        do {
            o = try await post("/api/fetch", body)
        } catch let r as Refused where r.code == 404 || r.code == 405 {
            // a server from before radiance-music#73
            throw Refused(code: r.code, words: "This server can't get songs from YouTube yet. It needs an update.")
        }
        return FetchAnswer(already: o.flag("already"), queued: o.flag("queued"), song: o["song"].flatMap { ServerSong.from($0, id) },
                           job: o["job"].flatMap { $0.object != nil ? Job.from($0) : nil })
    }

    /**
     * The server's copy of YouTube song [t], waiting while it gets it ([progress]: the job's note and how far, 0-1).
     * Asked again once the job is done, so it doesn't depend on how a finished job names its song.
     */
    public func fetched(_ t: Track, every: Duration = .milliseconds(1500), most: Duration = .seconds(240),
                        progress: @escaping @Sendable (String, Double) -> Void = { _, _ in }) async throws -> ServerSong {
        var answer = try await fetch(t)
        let start = ContinuousClock.now
        while true {
            if let s = answer.song, answer.already || answer.job == nil || !(answer.job!.open) { return s }
            guard let job = answer.job else { throw Refused(code: 500, words: "The server didn't say how it's getting that song.") }
            if ContinuousClock.now - start > most { throw Plain("The server is taking too long to get that song from YouTube. Try again in a bit.") }
            try await Task.sleep(for: every)
            let q = try await queue()
            if let now = q.jobs.first(where: { $0.id == job.id }) {
                if now.state == "failed" || now.state == "error" {
                    throw Refused(code: 502, words: now.note.isEmpty ? "The server couldn't get that song from YouTube." : now.note)
                }
                if now.open {
                    progress(now.note, now.progress)
                    continue
                }
            }
            // done (or gone from the queue): the server has it now
            answer = try await fetch(t)
            if answer.song == nil && answer.job.map({ !$0.open }) ?? true {
                throw Refused(code: 502, words: "The server couldn't get that song from YouTube.")
            }
        }
    }
}
