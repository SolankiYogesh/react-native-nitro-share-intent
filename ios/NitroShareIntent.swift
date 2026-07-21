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
    private var intentListeners: [Double: (SharePayload) -> Void] = [:]
    private var errorListeners: [Double: (String) -> Void] = [:]
    private var pendingIntent: SharePayload?
    private var nextListenerId: Double = 0
    private var processedFiles: Set<String> = []
    private var isCheckingInbox = false
    private var hasCheckedInitialInbox = false
    private var inboxCheckTimer: Timer?
    private var hasFoundFileInCurrentSession = false

    static let instance = NitroShareIntent()

    override init() {
        super.init()
        setupNotificationObserver()
        setupAppLifecycleObservers()
    }

    func getInitialShare() throws -> Promise<SharePayload?> {
        if !hasCheckedInitialInbox {
            hasCheckedInitialInbox = true
            startInboxMonitoring()
        }

        return Promise.resolved(withResult: pendingIntent)
    }

    func onIntentListener(listener: @escaping (SharePayload) -> Void) throws -> Double {
        nextListenerId += 1
        let id = nextListenerId
        intentListeners[id] = listener

        // Replay a pending intent to a newly attached listener so shares
        // that happened before this listener attached aren't lost.
        if let pending = pendingIntent {
            DispatchQueue.main.async {
                listener(pending)
            }
        }

        return id
    }

    func onErrorListener(listener: @escaping (String) -> Void) throws -> Double {
        nextListenerId += 1
        let id = nextListenerId
        errorListeners[id] = listener
        return id
    }

    func removeListener(listenerId: Double) throws {
        intentListeners.removeValue(forKey: listenerId)
        errorListeners.removeValue(forKey: listenerId)
    }

    func clearShareIntent() throws {
        pendingIntent = nil
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShareIntent(_:)),
            name: NSNotification.Name("ShareIntentReceived"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidFinishLaunching(_:)),
            name: NSNotification.Name("AppDidFinishLaunching"),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.checkForPendingDocuments()
        }
    }
    
    private func startInboxMonitoring() {
        inboxCheckTimer?.invalidate()
        hasFoundFileInCurrentSession = false
        
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
            let fileKey = url.path
            if processedFiles.contains(fileKey) {
                return
            }
            processedFiles.insert(fileKey)
            hasFoundFileInCurrentSession = true
            
            inboxCheckTimer?.invalidate()
            inboxCheckTimer = nil
            
            processIntent(url: url)
        } else if let text = userInfo["text"] as? String {
            let subject = userInfo["subject"] as? String
            processIntent(text: text, subject: subject)
        } else if let files = userInfo["files"] as? [URL] {
            let text = userInfo["text"] as? String
            let subject = userInfo["subject"] as? String
            processIntent(files: files, text: text, subject: subject)
        }
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
        // Confine the mutation of `pendingIntent`/`intentListeners` to the
        // main thread, since `handleSingleShare`/`handleMultipleShare` may
        // now call this from a background utility queue.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pendingIntent = payload
            self.intentListeners.values.forEach { $0(payload) }
        }
    }

    private func notifyError(_ message: String) {
        let listeners = errorListeners.values
        DispatchQueue.main.async {
            listeners.forEach { $0(message) }
        }
    }

    deinit {
        inboxCheckTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}