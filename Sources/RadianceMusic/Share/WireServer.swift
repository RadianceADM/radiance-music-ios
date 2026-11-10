import Foundation
import Network
import RadianceKit

/**
 * The listening side of the share wire (Android's Wire.Server): the device showing the QR. "get": it serves [offer]
 * (the scanner takes them); "put": songs sent come into [store]. Only the QR's key lets anyone in.
 */
final class WireServer: @unchecked Sendable {
    let mode: String
    let key = Wire.newKey()
    private let offer: Wire.Offer?
    private let store: Wire.Store?
    private let listener: NWListener
    private let queue = DispatchQueue(label: "radiance.wire")
    private var plan: [String: Wire.Item] = [:]
    private lazy var items: [Wire.Item] = offer?.items() ?? []
    private let onProgress: @Sendable (Wire.Progress) -> Void
    private var bytes: Int64 = 0, totalBytes: Int64 = 0, songs = 0
    /** Gentle with Bluetooth: the bytes a second it may move now (PhoneShare.pace). */
    private let pace: Wire.Pace = PhoneShare.pace
    private var pacer = Wire.Pacer()

    var port: Int { Int(listener.port?.rawValue ?? 0) }

    init(mode: String, offer: Wire.Offer?, store: Wire.Store?, progress: @escaping @Sendable (Wire.Progress) -> Void) throws {
        self.mode = mode
        self.offer = offer
        self.store = store
        self.onProgress = progress
        listener = try NWListener(using: .tcp, on: .any)
    }

    /** Listens; [ready] once it has its port. */
    func start(ready: @escaping @Sendable (Int) -> Void) {
        listener.stateUpdateHandler = { [weak self] s in
            if case .ready = s, let self { ready(self.port) }
        }
        listener.newConnectionHandler = { [weak self] c in self?.serve(c) }
        listener.start(queue: queue)
    }

    func close() { listener.cancel() }

    // MARK: - one request

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        readHead(c, Data())
    }

    /** Reads up to the end of the headers, then the body (to a file for a song's file). */
    private func readHead(_ c: NWConnection, _ have: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = have
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                let rest = buf[end.upperBound...]
                self.handle(c, head: head, rest: Data(rest))
            } else if done || err != nil || buf.count > 64 * 1024 {
                c.cancel()
            } else {
                self.readHead(c, buf)
            }
        }
    }

    private func handle(_ c: NWConnection, head: String, rest: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return c.cancel() }
        let method = String(first[0]), target = String(first[1])
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let path = String(target.split(separator: "?").first ?? "")
        let q = target.contains("?") ? Wire.query(String(target[target.index(after: target.firstIndex(of: "?")!)...])) : [:]
        guard (q["k"] ?? "") == key else { return reply(c, 403, "not this share") }
        let length = Int64(headers["content-length"] ?? "0") ?? 0

        switch (mode, method, path) {
        case ("get", "GET", "/list"):
            reply(c, 200, JSON.object(["v": .number(Double(Wire.version)), "songs": .array(items.map(\.json))]).text())
        case ("get", "GET", "/file"):
            guard let item = items.first(where: { $0.key == q["key"] }), let kind = q["kind"], let info = item.files[kind],
                  let f = offer?.open(item.key, kind) else { return reply(c, 404, "no such file") }
            sendFile(c, f, size: info.size, title: item.title)
        case ("put", "POST", "/plan"):
            guard length > 0 && length < 64 << 20 else { return reply(c, 413, "too big") }
            readBody(c, rest, Int(length)) { [weak self] body in
                guard let self, let store = self.store, let a = JSON.parse(body)?["songs"]?.array else { return self?.reply(c, 400, "bad plan") ?? () }
                Task {
                    var want: [String: JSON] = [:]
                    var planned: [String: Wire.Item] = [:]
                    var total: Int64 = 0
                    for item in a.compactMap(Wire.Item.from) {
                        let have = await store.have(item)
                        let missing = item.files.keys.filter { !have.contains($0) }.sorted()
                        if missing.isEmpty { continue }
                        planned[item.key] = item
                        want[item.key] = .array(missing.map { .string($0) })
                        total += missing.reduce(Int64(0)) { $0 + (item.files[$1]?.size ?? 0) }
                    }
                    self.queue.async {
                        self.plan = planned
                        self.totalBytes = total
                        self.onProgress(Wire.Progress(bytes: 0, totalBytes: total, songs: 0, totalSongs: planned.count, now: nil))
                        self.reply(c, 200, JSON.object(["want": .object(want)]).text())
                    }
                }
            }
        case ("put", "PUT", "/file"):
            guard let item = plan[q["key"] ?? ""], let kind = q["kind"], let info = item.files[kind] else { return reply(c, 404, "not asked for") }
            guard length == info.size, length <= Wire.mostBytes else { return reply(c, 400, "wrong size") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wire-in-\(UUID().uuidString)")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            guard let out = try? FileHandle(forWritingTo: tmp) else { return reply(c, 500, "can't write") }
            onProgress(Wire.Progress(bytes: bytes, totalBytes: totalBytes, songs: songs, totalSongs: plan.count, now: item.title))
            streamBody(c, out, rest, left: length) { [weak self] ok in
                try? out.close()
                guard let self, ok, let store = self.store else { try? FileManager.default.removeItem(at: tmp); return self?.reply(c, 400, "cut short") ?? () }
                Task {
                    do { try await store.write(item, kind, tmp) } catch { Log.say("share", "couldn't keep \(kind): \(error)") }
                    try? FileManager.default.removeItem(at: tmp)
                    self.queue.async {
                        self.bytes += length
                        self.onProgress(Wire.Progress(bytes: self.bytes, totalBytes: self.totalBytes, songs: self.songs, totalSongs: self.plan.count, now: item.title))
                        self.reply(c, 200, "ok")
                    }
                }
            }
        case ("put", "POST", "/done"):
            guard let item = plan[q["key"] ?? ""], let store else { return reply(c, 404, "not asked for") }
            Task {
                await store.done(item)
                self.queue.async {
                    self.songs += 1
                    self.onProgress(Wire.Progress(bytes: self.bytes, totalBytes: self.totalBytes, songs: self.songs, totalSongs: self.plan.count, now: nil))
                    self.reply(c, 200, "ok")
                }
            }
        default:
            reply(c, 404, "no")
        }
    }

    private func readBody(_ c: NWConnection, _ have: Data, _ length: Int, then: @escaping (Data) -> Void) {
        if have.count >= length { return then(have.prefix(length)) }
        c.receive(minimumIncompleteLength: 1, maximumLength: length - have.count) { [weak self] data, _, done, err in
            var buf = have
            if let data { buf.append(data) }
            if buf.count >= length { then(buf.prefix(length)) } else if done || err != nil { c.cancel() } else { self?.readBody(c, buf, length, then: then) }
        }
    }

    private func streamBody(_ c: NWConnection, _ out: FileHandle, _ first: Data, left: Int64, then: @escaping (Bool) -> Void) {
        var left = left
        if !first.isEmpty {
            let take = first.prefix(Int(min(Int64(first.count), left)))
            try? out.write(contentsOf: take)
            left -= Int64(take.count)
        }
        if left <= 0 { return then(true) }
        let wait = pacer.wait(after: first.count, limit: pace(), now: DispatchTime.now().uptimeNanoseconds)
        queue.asyncAfter(deadline: .now() + .nanoseconds(Int(min(wait, 2_000_000_000)))) { [weak self] in
            c.receive(minimumIncompleteLength: 1, maximumLength: Int(min(left, 256 * 1024))) { data, _, done, err in
                if let data, !data.isEmpty { self?.streamBody(c, out, data, left: left, then: then) }
                else if done || err != nil { then(false) }
                else { self?.streamBody(c, out, Data(), left: left, then: then) }
            }
        }
    }

    private func sendFile(_ c: NWConnection, _ f: URL, size: Int64, title: String) {
        guard let input = try? FileHandle(forReadingFrom: f) else { return reply(c, 404, "gone") }
        let head = "HTTP/1.1 200 OK\r\nContent-Length: \(size)\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        func next() {
            let chunk = (try? input.read(upToCount: 256 * 1024)) ?? nil
            guard let chunk, !chunk.isEmpty else {
                try? input.close()
                c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
                return
            }
            c.send(content: chunk, completion: .contentProcessed { [weak self] e in
                guard let self, e == nil else { try? input.close(); c.cancel(); return }
                self.bytes += Int64(chunk.count)
                self.onProgress(Wire.Progress(bytes: self.bytes, totalBytes: 0, songs: self.songs, totalSongs: 0, now: title))
                let wait = self.pacer.wait(after: chunk.count, limit: self.pace(), now: DispatchTime.now().uptimeNanoseconds)
                if wait > 1_000_000 { self.queue.asyncAfter(deadline: .now() + .nanoseconds(Int(min(wait, 2_000_000_000)))) { next() } } else { next() }
            })
        }
        next()
    }

    private func reply(_ c: NWConnection, _ code: Int, _ body: String) {
        let b = Data(body.utf8)
        let type = body.hasPrefix("{") ? "application/json" : "text/plain"
        let head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "No")\r\nContent-Length: \(b.count)\r\nContent-Type: \(type); charset=utf-8\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + b, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }
}

/** This iPhone's address on its Wi-Fi (or its Personal Hotspot), for the QR. */
func wifiAddress() -> String? {
    var addr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addr) == 0, let first = addr else { return nil }
    defer { freeifaddrs(addr) }
    var best: String?
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let i = p.pointee
        guard let sa = i.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: i.ifa_name)
        guard name == "en0" || name.hasPrefix("bridge") || name == "en2" else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        let ip = String(cString: host)
        if name == "en0" { return ip }
        best = best ?? ip
    }
    return best
}
