import AVFoundation
import CoreImage.CIFilterBuiltins
import RadianceKit
import SwiftUI

/**
 * Sharing songs by QR (Android's ShareSongs): show a QR for another device to take your songs (or to send you
 * theirs), or scan theirs. The same Wi-Fi (or this iPhone's Personal Hotspot); what's there already never goes again.
 */
struct ShareScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /** A share QR read by the Camera app (radiancemusic://share?…): taken at once, as if scanned here. */
    var opened: String? = nil
    @State private var server: WireServer?
    @State private var ticket: Wire.Ticket?
    @State private var progress: Wire.Progress?
    @State private var scanning = false
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let ticket, let image = qr(ticket.uri) {
                        Text(ticket.mode == "get" ? "Scan this on the other phone or computer to take your songs." : "Scan this on the other device to send its songs here.")
                            .font(.system(size: 15)).foregroundStyle(.white).multilineTextAlignment(.center)
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 280).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        Text("Both on the same Wi-Fi (or this iPhone's Personal Hotspot).").font(.system(size: 13)).foregroundStyle(Brand.dim)
                        Button("Stop sharing") { stopServer() }.buttonStyle(.bordered)
                    } else if !working {
                        Text("Songs go straight from one device to another: an iPhone, an Android phone or the computer. Songs already there aren't sent again.")
                            .font(.system(size: 15)).foregroundStyle(Brand.dim).multilineTextAlignment(.center)
                        big("Send my songs", "qrcode", "Your liked songs saved here, with their parts, lyrics and covers.") { startServer("get") }
                        big("Get songs", "square.and.arrow.down", "Another device sends its songs here.") { startServer("put") }
                        big("Scan a QR", "qrcode.viewfinder", "Another device's share QR, or a Radiance Music Server's invite.") { scanning = true }
                    }
                    if let p = progress { progressView(p) }
                    if let problem { Text(problem).font(.system(size: 14)).foregroundStyle(Brand.heart).multilineTextAlignment(.center) }
                }
                .padding(20)
            }
            .background(Brand.sheet)
            .navigationTitle("Share songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { stopServer(); dismiss() } } }
            .sheet(isPresented: $scanning) {
                QRScanner { code in
                    scanning = false
                    scanned(code)
                }
                .ignoresSafeArea()
            }
        }
        .onDisappear { stopServer() }
        .task { if let opened { scanned(opened) } }
    }

    private func big(_ title: String, _ icon: String, _ under: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Brand.orange).frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Text(under).font(.system(size: 13)).foregroundStyle(Brand.dim).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(16).background(Brand.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func progressView(_ p: Wire.Progress) -> some View {
        VStack(spacing: 8) {
            if p.totalBytes > 0 { ProgressView(value: Double(p.bytes), total: Double(max(p.totalBytes, 1))).tint(Brand.orange) }
            Text(p.totalSongs > 0 ? "\(p.songs) of \(p.totalSongs) songs" + (p.now.map { " · \($0)" } ?? "") : (p.now.map { "Sending “\($0)”" } ?? "Waiting for the other device…"))
                .font(.system(size: 14)).foregroundStyle(.white)
            if p.totalSongs > 0 && p.songs == p.totalSongs { Text("All done.").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.lossless) }
        }
    }

    // MARK: - showing a QR

    private func startServer(_ mode: String) {
        problem = nil
        guard let host = wifiAddress() else { problem = "Connect to Wi-Fi (or turn on Personal Hotspot) first."; return }
        do {
            let offer: Wire.Offer? = mode == "get" ? PhoneOffer(app) : nil
            let store: Wire.Store? = mode == "put" ? PhoneStore(app: app) : nil
            if mode == "get", (offer?.items().isEmpty ?? true) { problem = "No saved songs to send yet: like songs and they're saved here."; return }
            let s = try WireServer(mode: mode, offer: offer, store: store) { p in Task { @MainActor in progress = p } }
            server = s
            s.start { port in
                Task { @MainActor in ticket = Wire.Ticket(mode: mode, host: host, port: port, key: s.key, name: AppModel.deviceName) }
            }
        } catch {
            problem = "Couldn't start sharing. \(Errors.say(error))"
        }
    }

    private func stopServer() {
        server?.close()
        server = nil
        ticket = nil
    }

    private func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - scanning one

    private func scanned(_ code: String) {
        problem = nil
        if let t = Wire.Ticket.parse(code) {
            guard let host = t.host else { problem = "That device has no Wi-Fi address in its QR. Put both on the same Wi-Fi."; return }
            let base = "http://\(host):\(t.port)"
            working = true
            Task {
                defer { working = false }
                guard await Wire.reachable(base, key: t.key, mode: t.mode) else {
                    problem = "Can't reach \(t.name). Put both on the same Wi-Fi (or join this iPhone's Personal Hotspot from it)."
                    return
                }
                do {
                    let n: Int
                    if t.mode == "get" {
                        n = try await Wire.pull(base, key: t.key, store: PhoneStore(app: app), pace: PhoneShare.pace) { p in Task { @MainActor in progress = p } }
                        app.tell(n == 0 ? "You have all of \(t.name)'s songs already." : "\(n) songs from \(t.name) are in Liked Songs.")
                    } else {
                        n = try await Wire.push(base, key: t.key, offer: PhoneOffer(app), pace: PhoneShare.pace) { p in Task { @MainActor in progress = p } }
                        app.tell(n == 0 ? "\(t.name) has all your songs already." : "Sent \(n) songs to \(t.name).")
                    }
                } catch {
                    problem = (error as? Plain)?.words ?? Errors.say(error, online: app.online)
                }
            }
        } else if Servers.invite(code) != nil {
            Task {
                do {
                    let s = try await app.servers.join(code, deviceName: AppModel.deviceName)
                    app.tell("Joined \(s.name).")
                } catch {
                    problem = (error as? Refused)?.words ?? (error as? Plain)?.words ?? Errors.say(error, online: app.online)
                }
            }
        } else {
            problem = "That QR isn't a Radiance Music share or invite."
        }
    }
}

/** The camera, reading one QR code. */
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.found = found
        return c
    }

    func updateUIViewController(_ c: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var found: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else {
                let l = UILabel()
                l.text = "The camera isn't available. Allow it in Settings → Radiance Music."
                l.textColor = .white
                l.numberOfLines = 0
                l.textAlignment = .center
                l.frame = view.bounds.insetBy(dx: 24, dy: 0)
                l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(l)
                return
            }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(self, queue: .main)
            out.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.first { $0 is AVCaptureVideoPreviewLayer }?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            done = true
            found?(code)
        }
    }
}
