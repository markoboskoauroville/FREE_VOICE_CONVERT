// Free Voice Convert Equalizer (Mantra): pick the voice, drop the clips, every clip comes out sounding the same.
// The window only drives the engine (engine/fvc.py, bundled in Resources/engine); Python, Seed-VC and the models
// live in ~/Library/Application Support/FreeVoiceConvert, installed by engine/setup.sh at the first start.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

let VERSION = 4
let APPNAME = "Free Voice Convert Equalizer (Mantra)"
let SITE = "https://freevoiceconvert.pages.dev"

// MARK: - paths
enum Paths {
    static let home: URL = {
        if let h = ProcessInfo.processInfo.environment["FVC_HOME"] { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeVoiceConvert")
    }()
    static var python: URL { home.appendingPathComponent("venv/bin/python") }
    static var engine: URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("engine"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("fvc.py").path) { return r }
        // running from the repository (swift run / tests)
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("engine")
    }
}

struct Profile: Identifiable, Hashable, Decodable { let id: String; let name: String; let source: String; let dir: String }

struct Clip: Identifiable, Hashable { let id = UUID(); let url: URL }

// MARK: - the engine runner
final class Engine: ObservableObject {
    @Published var ready = false
    @Published var busy = false
    @Published var pct: Double = 0
    @Published var msg = "checking the engine"
    @Published var log: [String] = []
    @Published var profiles: [Profile] = []
    @Published var outputs: [String] = []
    @Published var error: String?
    @Published var totalS: Double = 0       // the length of all the clips
    @Published var doneS: Double = 0        // how much of it is converted
    @Published var startedAt: Date?         // when the first second was converted (the model's loading is not counted)
    @Published var startedS: Double = 0
    @Published var fps: Double = 25         // the clips' frame rate (25 for sound only): the speed is frames per second
    private var proc: Process?

    func run(_ exe: URL, _ args: [String], done: @escaping (Int32) -> Void) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["FVC_HOME"] = Paths.home.path
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { return }
            buffer.append(d)
            while let r = buffer.firstRange(of: Data([10])) ?? buffer.firstRange(of: Data([13])) {
                let line = String(decoding: buffer[..<r.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<r.upperBound)
                DispatchQueue.main.async { self?.line(line) }
            }
        }
        p.terminationHandler = { [weak self] t in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.proc = nil; self?.busy = false; done(t.terminationStatus) }
        }
        do { try p.run(); proc = p; busy = true; error = nil } catch {
            self.error = "could not start: \(error.localizedDescription)"
        }
    }

    private func line(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return }
        if t.hasPrefix("@"), let j = try? JSONSerialization.jsonObject(with: Data(t.dropFirst().utf8)) as? [String: Any] {
            if let p = j["pct"] as? Double { pct = p }
            if let m = j["msg"] as? String { msg = m }
            if let e = j["error"] as? String { error = e; msg = e }
            if let o = j["outputs"] as? [String], !o.isEmpty { outputs = o }
            if let t = j["total_s"] as? Double { totalS = t }
            if let f = j["fps"] as? Double, f > 0 { fps = f }
            if let d = j["done_s"] as? Double {
                // the clock starts at the first clip really converted (clips done before a STOP are only read back)
                if startedAt == nil && j["clip"] != nil && j["cached"] == nil { startedAt = Date(); startedS = d }
                doneS = d
            }
            return
        }
        log.append(t)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func stop() { proc?.terminate() }

    func py(_ args: [String], done: @escaping (Int32) -> Void) {
        run(Paths.python, [Paths.engine.appendingPathComponent("fvc.py").path] + args, done: done)
    }

    private var autoResumed = false

    /// Is everything here? If not, the installation goes on by itself from where it stopped (once per start;
    /// uv, Hugging Face and curl all continue partial downloads, so nothing is fetched twice).
    func check() {
        guard FileManager.default.fileExists(atPath: Paths.python.path) else { ready = false; resume(); return }
        py(["check"]) { [weak self] code in
            guard let self else { return }
            self.ready = code == 0
            if code == 0 { self.msg = "ready"; self.loadProfiles() } else { self.resume() }
        }
    }

    private func resume() {
        if autoResumed { msg = "the installation stopped (see the log); press INSTALL to go on"; return }
        autoResumed = true
        install()
    }

    func install() {
        log = []; msg = "installing (continues where it stopped)"
        run(URL(fileURLWithPath: "/bin/bash"), [Paths.engine.appendingPathComponent("setup.sh").path]) { [weak self] code in
            if code == 0 { self?.check() } else { self?.msg = "the installation stopped (see the log); it goes on by itself at the next start, or press INSTALL" }
        }
    }

    func loadProfiles() {
        let p = Process()
        p.executableURL = Paths.python
        p.arguments = [Paths.engine.appendingPathComponent("fvc.py").path, "profiles"]
        var env = ProcessInfo.processInfo.environment; env["FVC_HOME"] = Paths.home.path; p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        if let lines = String(data: d, encoding: .utf8)?.split(separator: "\n"),
           let last = lines.last, let ps = try? JSONDecoder().decode([Profile].self, from: Data(last.utf8)) {
            profiles = ps
        }
    }
}

// MARK: - the window
struct Word: View {
    let text: String; let lit: Bool; var color: Color = .green; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(lit ? color : Color.gray.opacity(0.55))
                .padding(.horizontal, 6).padding(.vertical, 3).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(text)
    }
}

struct ContentView: View {
    @StateObject var engine = Engine()
    @State var clips: [Clip] = []
    @State var selection = Set<Clip.ID>()
    @AppStorage("profile") var profileID = ""
    @AppStorage("voice") var voice = "convert"
    @AppStorage("quality") var quality = "speech"
    @AppStorage("export") var export = "individual"
    @AppStorage("clean") var clean = true
    @AppStorage("onTop") var onTop = false
    @StateObject var sys = SysMeters()
    @State var clipsTotal: Double = 0
    @State var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topRow
            if !engine.ready { installPanel; if engine.busy { logView } } else { step1; step2; step3 }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 520)
        .onAppear {
            engine.check()
            applyTop()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in add(providers); return true }
        .onChange(of: clips) { _, cs in
            let urls = cs.map { $0.url }
            Task {
                var t = 0.0
                for u in urls { if let d = try? await AVURLAsset(url: u).load(.duration), d.isNumeric { t += d.seconds } }
                clipsTotal = t
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fvcOpen)) { n in
            if let us = n.object as? [URL] { clips += us.map { Clip(url: $0) } }
        }
    }

    var topRow: some View {
        HStack(spacing: 2) {
            Text("FREE VOICE CONVERT").font(.system(size: 12, weight: .bold, design: .monospaced))
            Word(text: "ON", lit: true) {}
            Word(text: "OFF", lit: false) { engine.stop(); NSApp.terminate(nil) }
            Spacer(minLength: 4)
            Word(text: "TOP", lit: onTop) { onTop.toggle(); applyTop() }
            Button { if let u = URL(string: SITE) { NSWorkspace.shared.open(u) } } label: {
                Text("v\(VERSION)").font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
            }.buttonStyle(.plain).accessibilityLabel("version \(VERSION)")
            Button { NSApp.keyWindow?.close() } label: {
                Image(systemName: "xmark").foregroundColor(.gray).frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("close")
        }
    }

    var installPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The voice models are installed once (about 3 GB: Python, torch, Seed-VC). Then everything runs on this Mac, offline.")
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: engine.pct, total: 100)
            HStack {
                Text(engine.msg).font(.callout).foregroundColor(engine.error == nil ? .secondary : .red)
                Spacer()
                Button(engine.busy ? "INSTALLING…" : "INSTALL") { engine.install() }.disabled(engine.busy)
            }
        }
    }

    var currentProfile: Profile? { engine.profiles.first { $0.id == profileID } ?? engine.profiles.first }

    var voiceRow: some View {
        HStack(spacing: 8) {
            Button("SOURCE VOICE…") { pickVoice() }.help("A clean recording of the voice every clip should have (a studio-sounding recording is ideal)")
            if !engine.profiles.isEmpty {
                Picker("", selection: Binding(get: { currentProfile?.id ?? "" }, set: { profileID = $0 })) {
                    ForEach(engine.profiles) { Text($0.name).tag($0.id) }
                }.labelsHidden().frame(maxWidth: 260)
            } else {
                Text("no voice yet: pick a recording").foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    var clipList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("ADD FILES…") { pickClips() }
                Text("audio or video; drag to reorder; the order is the stitch order").font(.caption).foregroundColor(.secondary)
                Spacer()
                if !clips.isEmpty { Button("CLEAR") { clips = [] } }
            }
            List(selection: $selection) {
                ForEach(clips) { c in
                    HStack {
                        Image(systemName: isVideo(c.url) ? "film" : "waveform")
                        Text(c.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { clips.removeAll { $0.id == c.id } } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).accessibilityLabel("remove \(c.url.lastPathComponent)")
                    }
                }.onMove { clips.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 140)
            .overlay { if clips.isEmpty { Text("drop clips here").foregroundColor(.secondary) } }
        }
    }

    var optionsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text("VOICE").font(.caption.bold()).frame(width: 64, alignment: .leading)
                Word(text: "CONVERT", lit: voice == "convert") { voice = "convert" }
                Word(text: "KEEP", lit: voice == "keep") { voice = "keep" }
                Spacer()
                Text("CLEAN").font(.caption.bold())
                Word(text: "ON", lit: clean) { clean = true }
                Word(text: "OFF", lit: !clean) { clean = false }
            }
            HStack(spacing: 2) {
                Text("QUALITY").font(.caption.bold()).frame(width: 64, alignment: .leading)
                Word(text: "SPEECH", lit: quality == "speech") { quality = "speech" }
                Word(text: "STUDIO", lit: quality == "studio") { quality = "studio" }
                Text(quality == "studio" ? "44.1 kHz, the melody kept" : "22 kHz, the safest").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 2) {
                Text("EXPORT").font(.caption.bold()).frame(width: 64, alignment: .leading)
                Word(text: "ONE BY ONE", lit: export == "individual") { export = "individual" }
                Word(text: "STITCHED", lit: export == "stitched") { export = "stitched" }
                Word(text: "BOTH", lit: export == "both") { export = "both" }
            }
        }
    }

    var convertRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(engine.busy ? "STOP" : "CONVERT") { engine.busy ? engine.stop() : convert() }
                    .keyboardShortcut(.return).disabled(!engine.busy && (clips.isEmpty || currentProfile == nil))
                ProgressView(value: engine.pct, total: 100)
                Button(showLog ? "HIDE LOG" : "LOG") { showLog.toggle() }
            }
            HStack {
                Text(engine.msg).font(.callout).foregroundColor(engine.error == nil ? .secondary : .red).lineLimit(2)
                Spacer()
                if !engine.outputs.isEmpty && !engine.busy {
                    Button("SHOW") { NSWorkspace.shared.activateFileViewerSelecting(engine.outputs.map { URL(fileURLWithPath: $0) }) }
                }
            }
        }
    }

    var logView: some View {
        ScrollViewReader { sv in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(engine.log.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).id(i)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 160)
            .onChange(of: engine.log.count) { _, n in sv.scrollTo(n - 1) }
        }
    }

    // MARK: the workflow, three steps top to bottom (Marko, 1.11.2026: "make all my interface a workflow, 1, 2, 3")
    func stepTitle(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)").font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.black)
                .frame(width: 22, height: 22).background(Circle().fill(Color.green.opacity(0.55)))
            Text(t).font(.system(size: 13, weight: .bold, design: .monospaced))
        }
    }

    /// A step whose round number is its button (Marko, 1.11.2026: "This round number becomes a button on hover").
    struct StepButton: View {
        let n: Int; let title: String; var enabled = true; let action: () -> Void
        @State private var hover = false
        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text("\(n)").font(.system(size: hover ? 15 : 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(width: hover ? 28 : 22, height: hover ? 28 : 22)
                        .background(Circle().fill(enabled ? (hover ? Color(red: 0.55, green: 1, blue: 0.6) : Color.green) : Color.gray.opacity(0.5)))
                        .overlay(Circle().stroke(Color.white.opacity(hover && enabled ? 0.9 : 0), lineWidth: 2))
                        .frame(width: 28, height: 28)
                    Text(title).font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(enabled ? (hover ? .green : .primary) : .secondary)
                        .underline(hover && enabled)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(title)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h }; if h && enabled { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
    }

    var step1: some View {
        VStack(alignment: .leading, spacing: 6) {
            StepButton(n: 1, title: "ADD FILES") { pickClips() }
            List {
                ForEach(clips) { c in
                    HStack {
                        Image(systemName: isVideo(c.url) ? "film" : "waveform")
                        Text(c.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { clips.removeAll { $0.id == c.id } } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).accessibilityLabel("remove \(c.url.lastPathComponent)")
                    }
                }.onMove { clips.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 160)
            .overlay { if clips.isEmpty { Text("drop any audio or video file here\n(drag to change the order)").multilineTextAlignment(.center).foregroundColor(.secondary) } }
        }
    }

    var step2: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepTitle(2, "HOW TO EXPORT")
            HStack(spacing: 2) {
                Word(text: "ONE BY ONE", lit: export == "individual") { export = "individual" }
                pipe
                Word(text: "STITCHED", lit: export == "stitched") { export = "stitched" }
                pipe
                Word(text: "BOTH", lit: export == "both") { export = "both" }
            }.padding(.leading, 26)
        }
    }

    // choices on one line are parted by pipes (Marko, 1.11.2026: "You need to give me pipes")
    var pipe: some View {
        Text("|").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.gray.opacity(0.6))
            .accessibilityHidden(true)
    }

    var step3: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                StepButton(n: 3, title: engine.busy ? "STOP" : "CONVERT", enabled: engine.busy || !clips.isEmpty) {
                    engine.busy ? engine.stop() : convert()
                }.keyboardShortcut(.return)
                // the percentage beside it; after a STOP: "CONVERTED 50 %", and CONVERT goes on from there
                if engine.totalS > 0 && (engine.busy || engine.doneS > 0) && engine.outputs.isEmpty {
                    let p = Int((engine.doneS / engine.totalS * 100).rounded(.down))
                    Text(engine.busy ? "\(p) %" : "CONVERTED \(p) %")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(engine.busy ? .green : .orange)
                        .accessibilityLabel("converted \(p) percent")
                }
            }
            ProgressView(value: engine.pct, total: 100).padding(.leading, 26)
            Text(engine.msg).font(.callout).foregroundColor(engine.error == nil ? .secondary : .red)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true).padding(.leading, 26)
            stats.padding(.leading, 26)
        }
    }

    // where we are, how long it still takes (counting down), and the clock time it finishes
    var stats: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let e = engine
            let total = e.totalS > 0 ? e.totalS : clipsTotal
            let rate: Double? = {
                guard let st = e.startedAt, e.doneS - e.startedS > 0.5 else { return nil }
                return (e.doneS - e.startedS) / ctx.date.timeIntervalSince(st)  // seconds of sound per second
            }()
            let left: Double? = rate.map { max(0, (total - e.doneS) / $0) }
            let elapsed = e.startedAt.map { ctx.date.timeIntervalSince($0) } ?? 0
            let progress = total > 0 ? e.doneS / total : 0
            let timeFill = left.map { elapsed / max(elapsed + $0, 1) } ?? progress
            let fpsNow = rate.map { $0 * e.fps }
            // one table: label above, value, a hairline under (Marko, 1.11.2026: "Make a table layout")
            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Cell(label: "CONVERTED", value: "\(clock(e.doneS)) / \(clock(total))  \(Int((progress * 100).rounded(.down)))%", fill: progress)
                    Cell(label: "TIME LEFT", value: e.busy ? (left.map { clock($0) } ?? "…") : "–", fill: timeFill)
                    Cell(label: "ENDS AT", value: e.busy ? (left.map { Date().addingTimeInterval($0).formatted(date: .omitted, time: .shortened) } ?? "…") : "–", fill: timeFill)
                    Cell(label: "RUNNING", value: e.busy && e.startedAt != nil ? clock(elapsed) : "–", fill: timeFill)
                    Cell(label: "SPEED", value: fpsNow.map { String(format: "%.1f fps", $0) } ?? "–", fill: (fpsNow ?? 0) / max(e.fps, 1))
                }
                GridRow {
                    Cell(label: "CPU", value: "\(Int(sys.cpu * 100))%", fill: sys.cpu, warn: true)
                    Cell(label: "RAM FREE", value: gb(sys.ramFree), fill: sys.ramTotal > 0 ? sys.ramFree / sys.ramTotal : 0, warn: true, invert: true)
                    Cell(label: "GPU", value: "\(Int(sys.gpu * 100))%", fill: sys.gpu, warn: true)
                    Cell(label: "VRAM FREE", value: gb(sys.vramFree), fill: sys.vramTotal > 0 ? sys.vramFree / sys.vramTotal : 0, warn: true, invert: true)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
        }
    }

    func statRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.secondary).frame(width: 76, alignment: .leading)
            Text(v).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: actions
    func applyTop() {
        DispatchQueue.main.async { NSApp.windows.forEach { $0.level = onTop ? .floating : .normal } }
    }

    func isVideo(_ u: URL) -> Bool { ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(u.pathExtension.lowercased()) }

    func add(_ providers: [NSItemProvider]) {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { u, _ in
                if let u { DispatchQueue.main.async { clips.append(Clip(url: u)) } }
            }
        }
    }

    func pickClips() {
        let o = NSOpenPanel()
        o.allowsMultipleSelection = true  // any file ffmpeg can read: no type filter
        if o.runModal() == .OK { clips += o.urls.map { Clip(url: $0) } }
    }

    func pickVoice(thenConvert: Bool = false) {
        let o = NSOpenPanel()
        o.message = "Pick a clean recording of the voice (10 to 30 seconds of speech is enough)"
        guard o.runModal() == .OK, let u = o.url else { return }
        let name = u.deletingPathExtension().lastPathComponent
        engine.py(["profile", u.path, name]) { code in
            if code == 0 {
                engine.loadProfiles()
                profileID = engine.profiles.first { $0.name == name }?.id ?? profileID
                if thenConvert { convert() }
            }
        }
    }

    func convert() {
        guard let p = currentProfile else {  // no voice yet: asked once, then it stays
            pickVoice(thenConvert: true); return
        }
        engine.outputs = []; engine.log = []; engine.pct = 0
        engine.totalS = 0; engine.doneS = 0; engine.startedAt = nil
        let job: [String: Any] = ["clips": clips.map { $0.url.path }, "profile": p.dir, "voice": "convert",
                                  "quality": "speech", "export": export, "clean": true, "steps": 30]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fvc-job-\(UUID().uuidString).json")
        try? JSONSerialization.data(withJSONObject: job).write(to: url)
        engine.py(["run", url.path]) { code in
            try? FileManager.default.removeItem(at: url)
            if code == 0 && !engine.outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(engine.outputs.map { URL(fileURLWithPath: $0) })
            }
        }
    }
}

extension Notification.Name { static let fvcOpen = Notification.Name("fvcOpen") }

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {  // files dropped on the Dock icon or `open -a`
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: .fvcOpen, object: urls) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct FreeVoiceConvertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window(APPNAME, id: "main") { ContentView() }
            .defaultSize(width: 540, height: 620)
    }
}
