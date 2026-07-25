import Foundation
import NitroModules
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import CoreGraphics
import ImageIO

class NitroShareIntent: HybridNitroShareIntentSpec {

    // Keyed maps so multiple `useShareIntent()` hook instances (or any other
    // caller) can each register their own listener without stomping on one
    // another. `nextListenerId` is shared across both listener kinds so ids
    // stay unique and `removeListener` can safely look up either map.
    //
    // These are touched from the JS thread (the Nitro methods below), the
    // main thread (notification handlers) and a background utility queue
    // (file metadata reads), so every access goes through `stateLock` -
    // concurrent access to a Swift Dictionary is a crash, not just a race.
    private let stateLock = NSLock()
    private var intentListeners: [Double: (SharePayload) -> Void] = [:]
    private var errorListeners: [Double: (String) -> Void] = [:]
    private var pendingIntent: SharePayload?
    private var nextListenerId: Double = 0

    private func withLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
    private var processedFiles: Set<String> = []
    // The same URL open can reach us through more than one source (the
    // auto-installed AppDelegate hook, RCTLinkingManager's
    // RCTOpenURLNotification, and/or a legacy manual "ShareIntentReceived"
    // post), so identical URLs arriving within a short window are treated
    // as a single share.
    private var recentlyHandledURLs: [String: Date] = [:]
    private var isCheckingInbox = false
    private var hasCheckedInitialInbox = false
    private var inboxCheckTimer: Timer?
    private var hasFoundFileInCurrentSession = false

    static let instance = NitroShareIntent()

    override init() {
        super.init()
        setupNotificationObserver()
        setupAppLifecycleObservers()

        // Tell the launch hook (NitroShareIntentAppDelegateHook.m) that a
        // consumer exists - it replays any URLs it captured before this
        // instance was created (e.g. a cold-start custom-scheme open).
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("NitroShareIntentReady"),
                object: nil
            )
        }
    }

    func getInitialShare() throws -> Promise<SharePayload?> {
        // This runs on the JS thread, but the inbox monitoring state
        // (`processedFiles`, the timer, `hasFoundFileInCurrentSession`) is
        // main-thread confined - scanning from here directly would race with
        // a URL arriving through the AppDelegate hook and deliver the same
        // file twice.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.hasCheckedInitialInbox {
                self.hasCheckedInitialInbox = true
                self.startInboxMonitoring()
            }
        }

        return Promise.resolved(withResult: withLock { pendingIntent })
    }

    func onIntentListener(listener: @escaping (SharePayload) -> Void) throws -> Double {
        let (id, pending): (Double, SharePayload?) = withLock {
            nextListenerId += 1
            let id = nextListenerId
            intentListeners[id] = listener
            return (id, pendingIntent)
        }

        // Replay a pending intent to a newly attached listener so shares
        // that happened before this listener attached aren't lost.
        if let pending = pending {
            DispatchQueue.main.async {
                listener(pending)
            }
        }

        return id
    }

    func onErrorListener(listener: @escaping (String) -> Void) throws -> Double {
        return withLock {
            nextListenerId += 1
            let id = nextListenerId
            errorListeners[id] = listener
            return id
        }
    }

    func removeListener(listenerId: Double) throws {
        withLock {
            intentListeners.removeValue(forKey: listenerId)
            errorListeners.removeValue(forKey: listenerId)
        }
    }

    func clearShareIntent() throws {
        withLock { pendingIntent = nil }
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareIntent(_:)),
            name: NSNotification.Name("ShareIntentReceived"),
            object: nil
        )
        
        // Kept for backwards compatibility with pre-0.6.0 manual setups.
        // Posting this from the AppDelegate is no longer required - inbox
        // monitoring is already triggered by `getInitialShare()` and the
        // `didBecomeActive` observer.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidFinishLaunching(_:)),
            name: NSNotification.Name("AppDidFinishLaunching"),
            object: nil
        )

        // RCTLinkingManager posts this whenever the host app forwards
        // `application(_:open:options:)` to React Native's Linking module,
        // so apps with deep linking already wired up need no extra code.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRCTOpenURL(_:)),
            name: NSNotification.Name("RCTOpenURLNotification"),
            object: nil
        )
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidFinishLaunching(_ notification: Notification) {
        hasFoundFileInCurrentSession = false
        startInboxMonitoring()
    }
    
    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        hasFoundFileInCurrentSession = false
        // The Share Extension drop is checked first and unconditionally: it
        // runs while the app is backgrounded, so becoming active is the main
        // moment a share can be waiting there.
        checkForPendingSharedContainer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.checkForPendingDocuments()
        }
    }
    
    private func startInboxMonitoring() {
        inboxCheckTimer?.invalidate()
        hasFoundFileInCurrentSession = false

        checkForPendingSharedContainer()
        checkForPendingDocuments()
        
        let delays: [Double] = [0.3, 0.7, 1.2, 2.0, 3.0, 4.0, 5.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !self.hasFoundFileInCurrentSession {
                    self.checkForPendingDocuments()
                }
            }
        }
        
        inboxCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.hasFoundFileInCurrentSession {
                self.checkForPendingDocuments()
            } else {
                self.inboxCheckTimer?.invalidate()
                self.inboxCheckTimer = nil
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.inboxCheckTimer?.invalidate()
            self?.inboxCheckTimer = nil
        }
    }
    
    @objc private func handleShareIntent(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        if let url = userInfo["url"] as? URL {
            handleIncomingURL(url)
        } else if let text = userInfo["text"] as? String {
            let subject = userInfo["subject"] as? String
            processIntent(text: text, subject: subject)
        } else if let files = userInfo["files"] as? [URL] {
            let text = userInfo["text"] as? String
            let subject = userInfo["subject"] as? String
            processIntent(files: files, text: text, subject: subject)
        }
    }
    
    @objc private func handleRCTOpenURL(_ notification: Notification) {
        guard let urlString = notification.userInfo?["url"] as? String,
              let url = URL(string: urlString) else { return }
        handleIncomingURL(url)
    }

    /// Central entry point for a URL delivered by any supported source
    /// (auto-installed AppDelegate hook, RCTOpenURLNotification, or the
    /// legacy "ShareIntentReceived" notification). Always called on the
    /// main thread, since all of those notifications are posted there.
    private func handleIncomingURL(_ url: URL) {
        let key = url.absoluteString
        let now = Date()
        recentlyHandledURLs = recentlyHandledURLs.filter {
            now.timeIntervalSince($0.value) < 3.0
        }
        if recentlyHandledURLs[key] != nil {
            return
        }
        recentlyHandledURLs[key] = now

        if url.isFileURL {
            let fileKey = url.path
            if processedFiles.contains(fileKey) {
                return
            }
            processedFiles.insert(fileKey)
            hasFoundFileInCurrentSession = true

            inboxCheckTimer?.invalidate()
            inboxCheckTimer = nil
        }

        processIntent(url: url)
    }

    private func processIntent(url: URL) {
        if url.isFileURL {
            handleSingleShare(fileUrl: url)
        } else {
            handleTextShare(text: url.absoluteString, extras: ["url": url.absoluteString])
        }
    }
    
    private func processIntent(text: String, subject: String? = nil) {
        var extras: [String: String] = [:]
        if let subject = subject {
            extras["subject"] = subject
        }
        handleTextShare(text: text, extras: extras)
    }
    
    private func processIntent(files: [URL], text: String? = nil, subject: String? = nil) {
        if files.count == 1 {
            handleSingleShare(fileUrl: files[0], text: text, subject: subject)
        } else {
            handleMultipleShare(files: files, text: text, subject: subject)
        }
    }
    
    private func handleTextShare(text: String, extras: [String: String] = [:]) {
        let payload = SharePayload(
            type: .text,
            text: text,
            files: nil,
            extras: extras.isEmpty ? nil : extras
        )
        notifyListeners(payload)
    }
    
    private func handleSingleShare(fileUrl: URL, text: String? = nil, subject: String? = nil) {
        // `getFileInfo` can copy the shared file's bytes into the cache
        // directory (see `getAbsolutePath`), which can be slow for large
        // files - run it off the thread that delivered the intent (usually
        // main) so the UI never blocks on it.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let fileInfo = self.getFileInfo(for: fileUrl)
            var extras: [String: String] = [:]

            if let text = text { extras["text"] = text }
            if let subject = subject { extras["subject"] = subject }

            fileInfo.forEach { key, value in
                extras[key] = value
            }

            let filePath = fileInfo["filePath"] ?? fileUrl.absoluteString

            let payload = SharePayload(
                type: .file,
                text: nil,
                files: [filePath],
                extras: extras.isEmpty ? nil : extras
            )
            self.notifyListeners(payload)

            if fileUrl.path.contains("/Inbox/") {
                self.cleanupInboxFile(fileUrl)
            } else {
                // Files delivered outside of `/Inbox/` (e.g. a direct file
                // URL) are never cleaned up by `cleanupInboxFile`, so make
                // sure their dedup entry still expires - otherwise
                // re-sharing the same path again in this session would be
                // silently swallowed forever.
                self.scheduleProcessedFileExpiry(fileUrl)
            }
        }
    }

    private func handleMultipleShare(files: [URL], text: String? = nil, subject: String? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var extras: [String: String] = [:]

            if let text = text { extras["text"] = text }
            if let subject = subject { extras["subject"] = subject }
            extras["fileCount"] = String(files.count)

            let filePaths = files.map { url -> String in
                let fileInfo = self.getFileInfo(for: url)
                return fileInfo["filePath"] ?? url.absoluteString
            }

            let payload = SharePayload(
                type: .multiple,
                text: nil,
                files: filePaths,
                extras: extras.isEmpty ? nil : extras
            )
            self.notifyListeners(payload)

            files.forEach { url in
                if url.path.contains("/Inbox/") {
                    self.cleanupInboxFile(url)
                } else {
                    self.scheduleProcessedFileExpiry(url)
                }
            }
        }
    }
    
    private func getFileInfo(for url: URL) -> [String: String] {
        var fileInfo: [String: String] = [:]
        
        fileInfo["contentUri"] = url.absoluteString
        if let filePath = getAbsolutePath(for: url) {
            fileInfo["filePath"] = filePath
        }
        
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .nameKey,
                .contentTypeKey
            ])
            
            if let fileSize = resourceValues.fileSize {
                fileInfo["fileSize"] = String(fileSize)
            }
            
            if let fileName = resourceValues.name {
                fileInfo["fileName"] = fileName
            }
            
            if let contentType = resourceValues.contentType {
                let mimeType = contentType.preferredMIMEType ?? "application/octet-stream"
                fileInfo["mimeType"] = mimeType
                
                if mimeType.hasPrefix("image/") {
                    getImageInfo(for: url, into: &fileInfo)
                } else if mimeType.hasPrefix("video/") {
                    getVideoInfo(for: url, into: &fileInfo)
                }
            }
        } catch {
            notifyError("Failed to read file metadata for \(url.lastPathComponent): \(error.localizedDescription)")
        }

        return fileInfo
    }

    private func getAbsolutePath(for url: URL) -> String? {
        if url.isFileURL {
            return url.path
        }

        // For non-file URLs, copy to cache directory
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            notifyError("Failed to read shared file at \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }

        let fileName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let targetUrl = cacheDir.appendingPathComponent(fileName)

        do {
            try data.write(to: targetUrl)
            return targetUrl.path
        } catch {
            notifyError("Failed to copy shared file to \(targetUrl.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func getImageInfo(for url: URL, into fileInfo: inout [String: String]) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return
        }
        
        if let width = imageProperties[kCGImagePropertyPixelWidth as String] as? Int {
            fileInfo["width"] = String(width)
        }
        
        if let height = imageProperties[kCGImagePropertyPixelHeight as String] as? Int {
            fileInfo["height"] = String(height)
        }
    }
    
    private func getVideoInfo(for url: URL, into fileInfo: inout [String: String]) {
        let asset = AVAsset(url: url)
        
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            fileInfo["width"] = String(Int(abs(size.width)))
            fileInfo["height"] = String(Int(abs(size.height)))
        }
        
        let duration = asset.duration
        if duration.isValid {
            let durationInSeconds = CMTimeGetSeconds(duration)
            fileInfo["duration"] = String(Int(durationInSeconds * 1000))
        }
    }
    
    /// App Group id written into the host app's Info.plist by
    /// `NitroShareIntentSetup.rb`. Absent when the auto-generated Share
    /// Extension is disabled, in which case shared-container polling is a
    /// no-op and only `Documents/Inbox` is watched.
    private var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "NitroShareIntentAppGroup") as? String
    }

    /// Collects drops written by the Share Extension (see
    /// `ios/ShareExtension/NitroShareViewController.swift`). Each drop is a
    /// directory containing the copied files plus a `payload.json` written
    /// last - directories without it are still being filled and are skipped.
    private func checkForPendingSharedContainer() {
        guard let appGroup = appGroupIdentifier,
              let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return
        }

        let root = container.appendingPathComponent("NitroShareIntent", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        let drops: [URL]
        do {
            drops = try FileManager.default
                .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            notifyError("Failed to scan the shared container: \(error.localizedDescription)")
            return
        }

        for drop in drops {
            let manifest = drop.appendingPathComponent("payload.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }

            if let payload = readDrop(at: drop, manifest: manifest) {
                notifyListeners(payload)
            }

            // Consumed either way - a drop we can't parse would otherwise be
            // retried on every activation for the life of the install.
            try? FileManager.default.removeItem(at: drop)
        }
    }

    private func readDrop(at drop: URL, manifest: URL) -> SharePayload? {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            notifyError("Shared container drop \(drop.lastPathComponent) has an unreadable payload.json")
            return nil
        }

        let names = (json["files"] as? [String]) ?? []
        // The extension stores bare filenames; the host needs absolute paths,
        // and the files live in the group container which it can read directly.
        let paths = names.map { drop.appendingPathComponent($0).path }
        let text = json["text"] as? String

        var extras = (json["extras"] as? [String: String]) ?? [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            getFileInfo(for: url).forEach { key, value in
                if extras[key] == nil { extras[key] = value }
            }
        }

        let type: ShareType
        switch json["type"] as? String {
        case "multiple": type = .multiple
        case "file": type = .file
        default: type = paths.isEmpty ? .text : .file
        }

        return SharePayload(
            type: type,
            text: text,
            files: paths.isEmpty ? nil : paths,
            extras: extras.isEmpty ? nil : extras
        )
    }

    private func checkForPendingDocuments() {
        guard !isCheckingInbox else {
            return
        }
        
        guard !hasFoundFileInCurrentSession else {
            return
        }
        
        isCheckingInbox = true
        defer { isCheckingInbox = false }
        
        guard let documentsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            return
        }
        
        let inboxPath = documentsPath.appendingPathComponent("Inbox")
        
        guard FileManager.default.fileExists(atPath: inboxPath.path) else {
            return
        }
        
        do {
            let files = try FileManager.default
                .contentsOfDirectory(at: inboxPath, includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") }
            
            if files.count > 0 {
                for fileURL in files {
                    let fileKey = fileURL.path
                    if !processedFiles.contains(fileKey) {
                        processedFiles.insert(fileKey)
                        hasFoundFileInCurrentSession = true
                        
                        inboxCheckTimer?.invalidate()
                        inboxCheckTimer = nil
                        
                        processIntent(url: fileURL)
                        break
                    }
                }
            }
        } catch {
            notifyError("Failed to scan Inbox directory: \(error.localizedDescription)")
        }
    }

    private func cleanupInboxFile(_ url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            defer {
                // Always expire the dedup entry, regardless of whether the
                // file itself still existed/could be removed - otherwise a
                // failed cleanup would swallow re-shares of this path forever.
                self.processedFiles.remove(url.path)
            }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                self.notifyError("Failed to clean up Inbox file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Expires a `processedFiles` dedup entry for a file that isn't cleaned
    /// up via `cleanupInboxFile` (i.e. it wasn't delivered through
    /// `/Inbox/`), so re-sharing the same path again in the same session
    /// isn't silently swallowed forever.
    private func scheduleProcessedFileExpiry(_ url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.processedFiles.remove(url.path)
        }
    }

    private func notifyListeners(_ payload: SharePayload) {
        // Deliver on the main thread, since `handleSingleShare` /
        // `handleMultipleShare` may call this from a background utility
        // queue. The snapshot is taken under the lock and the callbacks are
        // invoked outside it, so a listener that calls back into
        // `removeListener` can't deadlock.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let listeners = self.withLock { () -> [(SharePayload) -> Void] in
                self.pendingIntent = payload
                return Array(self.intentListeners.values)
            }
            listeners.forEach { $0(payload) }
        }
    }

    private func notifyError(_ message: String) {
        let listeners = withLock { Array(errorListeners.values) }
        DispatchQueue.main.async {
            listeners.forEach { $0(message) }
        }
    }

    deinit {
        inboxCheckTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}