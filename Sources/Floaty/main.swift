import AppKit
import Foundation
import ImageIO
import SwiftUI

private let bundleIdentifier = "com.vyctorbrzezowski.floaty"
private let windowAutosaveName = "FloatyWindow"

@main
@MainActor
struct FloatyMain {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let delegate = AppDelegate()
        retainedDelegate = delegate

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingLyricsPanel?
    private var statusItem: NSStatusItem?
    private let viewModel = LyricsViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        createStatusItem()
        createPanel()
        viewModel.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showWindow() {
        if panel == nil { createPanel() }
        panel?.orderFrontRegardless()
    }

    @objc private func hideWindow() {
        panel?.orderOut(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Floaty")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "Floaty"
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide Window", action: #selector(hideWindow), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Floaty", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu

        statusItem = item
    }

    private func createPanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 430, height: 270)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 28,
            y: screenFrame.maxY - size.height - 52
        )

        let panel = FloatingLyricsPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Floaty"
        panel.identifier = NSUserInterfaceItemIdentifier(bundleIdentifier)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.minSize = NSSize(width: 230, height: 140)
        panel.maxSize = NSSize(width: 900, height: 700)

        let content = LyricsPiPView(model: viewModel)
        panel.contentView = DraggableHostingView(rootView: content)
        panel.setFrameAutosaveName(windowAutosaveName)
        _ = panel.setFrameUsingName(windowAutosaveName)

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makeMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Floaty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        return mainMenu
    }
}

final class FloatingLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        setup()
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
    }
}

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published private(set) var snapshot: SpotifySnapshot?
    @Published private(set) var lyrics: LyricsState = .waiting("Open Spotify")
    @Published private(set) var visual: AlbumVisual = .neutral

    private let spotify = SpotifyReader()
    private let provider = LyricsProvider()
    private let artworkProvider = ArtworkProvider()
    private var pollTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var cachedLyrics: [String: LyricsState] = [:]
    private var cachedVisuals: [String: AlbumVisual] = [:]
    private var lastTrackKey: String?

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    func currentPosition(at date: Date) -> TimeInterval {
        guard let snapshot else { return 0 }
        if snapshot.state == .playing {
            return min(snapshot.duration, snapshot.position + date.timeIntervalSince(snapshot.readAt))
        }
        return snapshot.position
    }

    func displayLines(at date: Date, maxLines: Int) -> [DisplayLine] {
        let limitedMax = max(1, maxLines)
        let position = currentPosition(at: date)

        switch lyrics {
        case .synced(let lines):
            guard !lines.isEmpty else { return [.message("No lyrics")] }
            let active = activeSyncedIndex(lines: lines, position: position)
            return slice(lines: lines, active: active, maxLines: limitedMax).map {
                DisplayLine(id: "synced-\($0.index)", text: $0.text, isActive: $0.index == active)
            }

        case .plain(let lines):
            guard !lines.isEmpty else { return [.message("No lyrics")] }
            let active = activePlainIndex(lineCount: lines.count, position: position)
            return slice(lines: lines.enumerated().map { IndexedText(index: $0.offset, text: $0.element) }, active: active, maxLines: limitedMax).map {
                DisplayLine(id: "plain-\($0.index)", text: $0.text, isActive: $0.index == active)
            }

        case .instrumental:
            return [.message("♪")]

        case .loading:
            return [.message("Loading lyrics")]

        case .waiting(let message), .failed(let message):
            return [.message(message)]
        }
    }

    private func refresh() async {
        do {
            let next = try spotify.read()
            snapshot = next

            guard next.state != .notRunning else {
                updateTrack(nil, lyrics: .waiting("Open Spotify"))
                return
            }

            guard next.state != .stopped, !next.name.isEmpty else {
                updateTrack(nil, lyrics: .waiting("Play a song"))
                return
            }

            if next.trackKey != lastTrackKey {
                lastTrackKey = next.trackKey
                refreshArtwork(for: next)

                if let cached = cachedLyrics[next.trackKey] {
                    lyrics = cached
                    return
                }

                lyrics = .loading
                fetchTask?.cancel()
                fetchTask = Task { [weak self, next] in
                    guard let self else { return }
                    let result: LyricsState
                    do {
                        result = try await provider.fetchLyrics(for: next)
                    } catch {
                        result = .failed("Lyrics unavailable")
                    }

                    if !Task.isCancelled, self.lastTrackKey == next.trackKey {
                        self.cachedLyrics[next.trackKey] = result
                        self.lyrics = result
                    }
                }
            }
        } catch SpotifyReadError.automationDenied {
            updateTrack(nil, lyrics: .failed("Allow Spotify automation"))
        } catch {
            updateTrack(nil, lyrics: .failed("Spotify unavailable"))
        }
    }

    private func refreshArtwork(for snapshot: SpotifySnapshot) {
        if let cached = cachedVisuals[snapshot.trackKey] {
            visual = cached
            return
        }

        guard let artworkURL = snapshot.artworkURL else {
            visual = .neutral
            return
        }

        visual = .neutral
        artworkTask?.cancel()
        artworkTask = Task { [weak self, artworkURL, snapshot] in
            guard let self else { return }
            guard let payload = try? await artworkProvider.fetchArtwork(url: artworkURL) else { return }

            let nextVisual = AlbumVisual(
                image: NSImage(data: payload.data),
                tint: payload.tint
            )

            if !Task.isCancelled, self.lastTrackKey == snapshot.trackKey {
                self.cachedVisuals[snapshot.trackKey] = nextVisual
                self.visual = nextVisual
            }
        }
    }

    private func updateTrack(_ trackKey: String?, lyrics: LyricsState) {
        lastTrackKey = trackKey
        fetchTask?.cancel()
        artworkTask?.cancel()
        visual = .neutral
        self.lyrics = lyrics
    }

    private func activeSyncedIndex(lines: [LyricLine], position: TimeInterval) -> Int {
        var active = 0
        for index in lines.indices where lines[index].time <= position + 0.15 {
            active = index
        }
        return active
    }

    private func activePlainIndex(lineCount: Int, position: TimeInterval) -> Int {
        guard let snapshot, snapshot.duration > 1, lineCount > 1 else { return 0 }
        let progress = min(max(position / snapshot.duration, 0), 1)
        return min(lineCount - 1, Int((Double(lineCount - 1) * progress).rounded(.down)))
    }

    private func slice(lines: [LyricLine], active: Int, maxLines: Int) -> [IndexedText] {
        slice(lines: lines.enumerated().map { IndexedText(index: $0.offset, text: $0.element.text) }, active: active, maxLines: maxLines)
    }

    private func slice(lines: [IndexedText], active: Int, maxLines: Int) -> [IndexedText] {
        guard lines.count > maxLines else { return lines }
        let desiredAfter = max(1, min(maxLines - 1, maxLines / 2))
        let desiredBefore = max(0, maxLines - 1 - desiredAfter)
        var start = max(0, active - desiredBefore)

        if active + desiredAfter >= start + maxLines {
            start = active + desiredAfter - maxLines + 1
        }

        if start + maxLines > lines.count {
            start = max(0, lines.count - maxLines)
        }

        let end = min(lines.count, start + maxLines)
        return Array(lines[start..<end])
    }
}

struct SpotifySnapshot: Equatable {
    enum PlayerState: String {
        case playing
        case paused
        case stopped
        case notRunning
    }

    let id: String
    let name: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let duration: TimeInterval
    let position: TimeInterval
    let state: PlayerState
    let readAt: Date

    var trackKey: String {
        if !id.isEmpty { return id }
        return "\(artist)|\(album)|\(name)|\(Int(duration))"
    }
}

enum SpotifyReadError: Error {
    case malformedResult
    case automationDenied
}

final class SpotifyReader {
    private let script = NSAppleScript(source: """
    if application "Spotify" is running then
      tell application "Spotify"
        if player state is stopped then
          return {"", "", "", "", "", "0", "0", "stopped"}
        end if
        set t to current track
        return {((id of t) as string), ((name of t) as string), ((artist of t) as string), ((album of t) as string), ((artwork url of t) as string), ((duration of t) as string), ((player position) as string), ((player state) as string)}
      end tell
    else
      return {"", "", "", "", "", "0", "0", "not_running"}
    end if
    """)

    func read() throws -> SpotifySnapshot {
        var error: NSDictionary?
        guard let descriptor = script?.executeAndReturnError(&error) else {
            if let number = error?[NSAppleScript.errorNumber] as? Int, number == -1743 {
                throw SpotifyReadError.automationDenied
            }
            throw SpotifyReadError.malformedResult
        }

        var values: [String] = []
        for index in 1...descriptor.numberOfItems {
            values.append(descriptor.atIndex(index)?.stringValue ?? "")
        }

        guard values.count == 8 else { throw SpotifyReadError.malformedResult }

        let state = parsePlayerState(values[7])
        return SpotifySnapshot(
            id: values[0],
            name: values[1],
            artist: values[2],
            album: values[3],
            artworkURL: URL(string: values[4]),
            duration: parseAppleScriptNumber(values[5]) / 1000,
            position: parseAppleScriptNumber(values[6]),
            state: state,
            readAt: Date()
        )
    }

    private func parsePlayerState(_ value: String) -> SpotifySnapshot.PlayerState {
        switch value.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "playing":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        case "not_running", "notrunning":
            return .notRunning
        default:
            return .paused
        }
    }

    private func parseAppleScriptNumber(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

struct RGBColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }

    static let neutral = RGBColor(red: 0.18, green: 0.18, blue: 0.18)
}

struct AlbumVisual {
    let image: NSImage?
    let tint: RGBColor

    static let neutral = AlbumVisual(image: nil, tint: .neutral)
}

struct ArtworkPayload: Sendable {
    let data: Data
    let tint: RGBColor
}

actor ArtworkProvider {
    func fetchArtwork(url: URL) async throws -> ArtworkPayload {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Floaty/0.1.0 (personal macOS app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return ArtworkPayload(data: data, tint: averageColor(from: data) ?? .neutral)
    }

    private func averageColor(from data: Data) -> RGBColor? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 28,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.08 else { continue }

            red += Double(pixels[offset]) * alpha
            green += Double(pixels[offset + 1]) * alpha
            blue += Double(pixels[offset + 2]) * alpha
            count += alpha
        }

        guard count > 0 else { return nil }

        return RGBColor(
            red: min(1, max(0.04, (red / count) / 255)),
            green: min(1, max(0.04, (green / count) / 255)),
            blue: min(1, max(0.04, (blue / count) / 255))
        )
    }
}

enum LyricsState {
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case waiting(String)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct LyricLine: Equatable {
    let time: TimeInterval
    let text: String
}

struct IndexedText {
    let index: Int
    let text: String
}

struct DisplayLine: Identifiable, Equatable {
    let id: String
    let text: String
    let isActive: Bool

    init(id: String, text: String, isActive: Bool) {
        self.id = id
        self.text = text
        self.isActive = isActive
    }

    static func message(_ text: String) -> DisplayLine {
        DisplayLine(id: "message-\(text)", text: text, isActive: true)
    }
}

actor LyricsProvider {
    private let decoder = JSONDecoder()

    func fetchLyrics(for snapshot: SpotifySnapshot) async throws -> LyricsState {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: snapshot.name),
            URLQueryItem(name: "artist_name", value: snapshot.artist),
            URLQueryItem(name: "album_name", value: snapshot.album)
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Floaty/0.1.0 (personal macOS app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let candidates = try decoder.decode([LRCLibTrack].self, from: data)
        guard let best = candidates.max(by: { score($0, snapshot: snapshot) < score($1, snapshot: snapshot) }) else {
            return .failed("No lyrics")
        }

        if best.instrumental == true {
            return .instrumental
        }

        if let synced = best.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }

        if let plain = best.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.isEmpty ? .failed("No lyrics") : .plain(lines)
        }

        return .failed("No lyrics")
    }

    private func score(_ candidate: LRCLibTrack, snapshot: SpotifySnapshot) -> Int {
        let track = canonical(candidate.trackName ?? candidate.name ?? "")
        let artist = canonical(candidate.artistName ?? "")
        let album = canonical(candidate.albumName ?? "")
        let wantedTrack = canonical(snapshot.name)
        let wantedArtist = canonical(snapshot.artist)
        let wantedAlbum = canonical(snapshot.album)

        var total = 0
        if track == wantedTrack { total += 80 }
        if track.contains(wantedTrack) || wantedTrack.contains(track) { total += 25 }
        if artist == wantedArtist { total += 55 }
        if artist.contains(wantedArtist) || wantedArtist.contains(artist) { total += 20 }
        if album == wantedAlbum { total += 20 }
        if let duration = candidate.duration {
            let delta = abs(duration - snapshot.duration)
            if delta < 2 { total += 25 }
            else if delta < 6 { total += 14 }
            else if delta > 25 { total -= 20 }
        }
        if candidate.syncedLyrics?.isEmpty == false { total += 12 }
        if candidate.instrumental == true { total -= 30 }
        return total
    }

    private func canonical(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseLRC(_ raw: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []
        for row in raw.components(separatedBy: .newlines) {
            let nsRow = row as NSString
            let fullRange = NSRange(location: 0, length: nsRow.length)
            let matches = regex.matches(in: row, range: fullRange)
            guard let lastMatch = matches.last else { continue }

            let textStart = lastMatch.range.location + lastMatch.range.length
            let lyricText = nsRow.substring(from: textStart)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = lyricText.isEmpty ? "♪" : lyricText

            for match in matches {
                let minutes = Double(nsRow.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsRow.substring(with: match.range(at: 2))) ?? 0
                var time = minutes * 60 + seconds
                let fractionRange = match.range(at: 3)
                if fractionRange.location != NSNotFound {
                    let fraction = nsRow.substring(with: fractionRange)
                    if let value = Double(fraction) {
                        time += value / pow(10, Double(fraction.count))
                    }
                }
                lines.append(LyricLine(time: time, text: text))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }
}

struct LRCLibTrack: Decodable {
    let name: String?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

enum BackgroundMode: String {
    case album
    case neutral
}

enum TextTuning: String {
    case compact
    case balanced
    case large

    var multiplier: CGFloat {
        switch self {
        case .compact: 0.9
        case .balanced: 1
        case .large: 1.12
        }
    }
}

struct LyricsPiPView: View {
    @ObservedObject var model: LyricsViewModel
    @State private var now = Date()
    @State private var isHovering = false
    @State private var isTweaksOpen = false
    @AppStorage("backgroundMode") private var backgroundModeRaw = BackgroundMode.album.rawValue
    @AppStorage("textTuning") private var textTuningRaw = TextTuning.balanced.rawValue

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let backgroundMode = BackgroundMode(rawValue: backgroundModeRaw) ?? .album
            let textTuning = TextTuning(rawValue: textTuningRaw) ?? .balanced
            let metrics = LyricsMetrics(size: proxy.size, textScale: textTuning.multiplier)
            let lines = metrics.fittingDisplayLines(model.displayLines(at: now, maxLines: metrics.maxLines))

            ZStack(alignment: .topLeading) {
                PiPBackground(
                    visual: model.visual,
                    mode: backgroundMode,
                    cornerRadius: metrics.cornerRadius
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                lyricsContent(lines: lines, metrics: metrics)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .allowsHitTesting(false)

                EdgeFadeOverlay(cornerRadius: metrics.cornerRadius)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            tweakButton
                                .opacity(isHovering || isTweaksOpen ? 1 : 0)

                            if isTweaksOpen {
                                tweaksPanel
                                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                            }
                        }
                        .animation(.easeOut(duration: 0.16), value: isHovering)
                        .animation(.easeOut(duration: 0.16), value: isTweaksOpen)
                    }
                    Spacer()
                }
                .padding(metrics.menuInset)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onHover {
            isHovering = $0
            if !$0 { isTweaksOpen = false }
        }
        .onReceive(ticker) { now = $0 }
    }

    private var tweakButton: some View {
        Button {
            isTweaksOpen.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 30, height: 26)
                .background(.black.opacity(0.24), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tweaksPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                tweakLabel("Bg")
                TweakChip(title: "Album", isSelected: backgroundModeRaw == BackgroundMode.album.rawValue) {
                    backgroundModeRaw = BackgroundMode.album.rawValue
                }
                TweakChip(title: "Neutral", isSelected: backgroundModeRaw == BackgroundMode.neutral.rawValue) {
                    backgroundModeRaw = BackgroundMode.neutral.rawValue
                }
            }

            HStack(spacing: 8) {
                tweakLabel("Text")
                TweakChip(title: "S", isSelected: textTuningRaw == TextTuning.compact.rawValue) {
                    textTuningRaw = TextTuning.compact.rawValue
                }
                TweakChip(title: "M", isSelected: textTuningRaw == TextTuning.balanced.rawValue) {
                    textTuningRaw = TextTuning.balanced.rawValue
                }
                TweakChip(title: "L", isSelected: textTuningRaw == TextTuning.large.rawValue) {
                    textTuningRaw = TextTuning.large.rawValue
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.045, green: 0.045, blue: 0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
    }

    private func tweakLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(width: 30, alignment: .leading)
    }

    @ViewBuilder
    private func lyricsContent(lines: [DisplayLine], metrics: LyricsMetrics) -> some View {
        if model.lyrics.isLoading {
            LoadingLyricsView(metrics: metrics)
        } else {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                if shouldCenter(lines) {
                    Spacer(minLength: 0)
                }

                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: metrics.fontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(line.isActive ? Color.white : Color.white.opacity(0.52))
                        .multilineTextAlignment(.leading)
                        .lineLimit(metrics.slotLineLimit)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: metrics.lyricSlotHeight, maxHeight: metrics.lyricSlotHeight, alignment: .topLeading)
                        .shadow(color: .black.opacity(line.isActive ? 0.28 : 0.18), radius: 8, y: 2)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func shouldCenter(_ lines: [DisplayLine]) -> Bool {
        lines.count <= 2
    }
}

struct EdgeFadeOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct TweakChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(isSelected ? Color.black.opacity(0.9) : Color.white.opacity(0.88))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.94) : Color(red: 0.28, green: 0.28, blue: 0.28))
                )
        }
        .buttonStyle(.plain)
    }
}

struct LoadingLyricsView: View {
    let metrics: LyricsMetrics
    @State private var phase = false

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing + 2) {
            skeleton(width: 0.74, height: metrics.fontSize * 0.78, opacity: phase ? 0.30 : 0.16)
            skeleton(width: 0.52, height: metrics.fontSize * 0.78, opacity: phase ? 0.18 : 0.30)
            if metrics.maxLines > 2 {
                skeleton(width: 0.38, height: metrics.fontSize * 0.70, opacity: phase ? 0.14 : 0.24)
            }
            Spacer(minLength: 0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private func skeleton(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.white.opacity(opacity))
                .frame(width: max(36, proxy.size.width * width), height: max(8, height))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
        .frame(height: max(10, height))
    }
}

struct PiPBackground: View {
    let visual: AlbumVisual
    let mode: BackgroundMode
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if mode == .album, let image = visual.image {
                    visual.tint.swiftUIColor

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.22)
                        .blur(radius: 30)
                        .saturation(1.32)
                        .contrast(1.08)
                        .opacity(0.92)

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 7)
                        .saturation(1.12)
                        .opacity(0.24)

                    visual.tint.swiftUIColor.opacity(0.16)
                    Color.black.opacity(0.36)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.055),
                            Color.clear,
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    RGBColor.neutral.swiftUIColor
                        .overlay(Color.black.opacity(0.06))

                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.035),
                            Color.clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.9
                    )

                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .compositingGroup()
        }
    }
}

struct LyricsMetrics {
    let size: CGSize
    let textScale: CGFloat

    var fontSize: CGFloat {
        let base = min(size.width * 0.064, size.height * 0.16)
        return min(50, max(15, base)) * textScale
    }

    var horizontalPadding: CGFloat {
        min(54, max(18, size.width * 0.078))
    }

    var verticalPadding: CGFloat {
        min(34, max(15, size.height * 0.095))
    }

    var rowSpacing: CGFloat {
        min(18, max(6, fontSize * 0.26))
    }

    var slotLineLimit: Int {
        2
    }

    var textLineHeight: CGFloat {
        max(18, fontSize * 1.08)
    }

    var lyricSlotHeight: CGFloat {
        textLineHeight * CGFloat(slotLineLimit)
    }

    var cornerRadius: CGFloat {
        min(22, max(13, size.width * 0.025))
    }

    var menuInset: CGFloat {
        min(14, max(8, size.width * 0.018))
    }

    var maxLines: Int {
        let usableHeight = max(40, size.height - verticalPadding * 2)
        let rowHeight = lyricSlotHeight + rowSpacing
        return max(1, min(8, Int(usableHeight / rowHeight)))
    }

    func fittingDisplayLines(_ lines: [DisplayLine]) -> [DisplayLine] {
        guard lines.count > 1 else { return lines }

        var fitted = lines
        while fitted.count > 1, estimatedHeight(for: fitted) > usableTextHeight {
            let activeIndex = fitted.firstIndex(where: \.isActive) ?? 0
            let leadingCount = activeIndex
            let trailingCount = fitted.count - activeIndex - 1

            if leadingCount >= trailingCount, leadingCount > 0 {
                fitted.removeFirst()
            } else if trailingCount > 0 {
                fitted.removeLast()
            } else {
                break
            }
        }

        return fitted
    }

    private var usableTextHeight: CGFloat {
        max(40, size.height - verticalPadding * 2)
    }

    private var estimatedLineHeight: CGFloat {
        textLineHeight
    }

    private func estimatedHeight(for lines: [DisplayLine]) -> CGFloat {
        let textRows = lines.reduce(0) { total, line in
            total + estimatedTextRows(for: line.text)
        }

        return CGFloat(textRows) * estimatedLineHeight + CGFloat(max(0, lines.count - 1)) * rowSpacing
    }

    private func estimatedTextRows(for text: String) -> Int {
        let normalizedLength = max(1, text.trimmingCharacters(in: .whitespacesAndNewlines).count)
        let availableWidth = max(80, size.width - horizontalPadding * 2)
        let averageGlyphWidth = max(7, fontSize * 0.55)
        let charactersPerRow = max(8, Int(availableWidth / averageGlyphWidth))
        return max(1, Int(ceil(Double(normalizedLength) / Double(charactersPerRow))))
    }
}
