import Foundation
import AVFoundation
import Combine

// MARK: - AudioManager — AVPlayer equivalent of the web app's <audio> element.
// Browser always plays at volume 1.0; the volume settings are server-side only.

@MainActor
final class AudioManager: ObservableObject {
    @Published var isPlaying = false
    @Published var bannerText: String? = nil      // nil = hidden
    @Published var playingIsPrayer = false        // prayer audio keeps card pulsing
    @Published var serverPlaying = false          // audio currently playing on the Pi (stop = API call)

    /// True while ANY audio (local playback or server playback) is active → a stop control must be visible.
    var isActive: Bool { isPlaying || serverPlaying || bannerText != nil }
    private var serverBannerTask: Task<Void, Never>?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var stopTimer: Task<Void, Never>?

    /// Master gate wired to "iOS notifications" (Settings → General): when it
    /// returns false the app emits no sound at all, whatever is configured in
    /// Athan call / Tasbih & Objectives / Quran recitation.
    var playbackGate: (() -> Bool)?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    /// Play a remote audio URL. `limit30s` trims like the web 30s previews.
    func play(url: URL, banner: String, limit30s: Bool = false, isPrayer: Bool = false) {
        guard playbackGate?() ?? true else { return }
        stopLocal()
        try? AVAudioSession.sharedInstance().setActive(true)
        bannerText = banner
        playingIsPrayer = isPrayer
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.volume = 1.0
        player?.play()
        isPlaying = true

        if limit30s {
            stopTimer?.cancel()
            stopTimer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.stopLocal()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnded() }
        }
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            if item.status == .failed {
                Task { @MainActor in self?.handleEnded() }
            }
        }
    }

    private func handleEnded() {
        stopTimer?.cancel()
        isPlaying = false
        playingIsPrayer = false
        bannerText = nil
        cleanupPlayer()
    }

    /// Stop only local playback (equivalent of audioElement.pause()).
    func stopLocal() {
        serverBannerTask?.cancel()
        serverPlaying = false
        stopTimer?.cancel()
        player?.pause()
        cleanupPlayer()
        isPlaying = false
        playingIsPrayer = false
        bannerText = nil
    }

    private func cleanupPlayer() {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        statusObserver = nil
        player = nil
    }

    func hideBanner() { bannerText = nil }

    /// Banner for audio played by the server; auto-clears (the Pi gives no end-of-playback event).
    func showServerBanner(_ text: String, duration: TimeInterval) {
        serverPlaying = true
        bannerText = text
        serverBannerTask?.cancel()
        serverBannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.clearServerBanner()
        }
    }

    func clearServerBanner() {
        serverBannerTask?.cancel()
        guard serverPlaying else { return }
        serverPlaying = false
        if !isPlaying { bannerText = nil }
    }
}
