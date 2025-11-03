import Foundation
import NitroModules
import Photos
import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import AVFoundation
import CoreGraphics
import ImageIO

class NitroShareIntent: HybridNitroShareIntentSpec {
  
  private var initialSharePayload: SharePayload?
  private var listeners: [(SharePayload) -> Void] = []
  
  static let shared = NitroShareIntent()
  
  override init() {
    super.init()
    setupNotificationObserver()
  }
  
  func getInitialShare() throws -> Promise<SharePayload?> {
    return Promise { resolve, reject in
      resolve(initialSharePayload)
    }
  }
  
  func addListener(listener: @escaping (SharePayload) -> Void) throws {
    listeners.append(listener)
  }
  
  func removeListener(listener: @escaping (SharePayload) -> Void) throws {
    listeners.removeAll()
  }
  
  // MARK: - Private Methods
  
  private func setupNotificationObserver() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleShareIntent(_:)),
      name: NSNotification.Name("ShareIntentReceived"),
      object: nil
    )
  }
  
  @objc private func handleShareIntent(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let payload = userInfo["payload"] as? SharePayload else {
      return
    }
    
    notifyListeners(payload)
  }
  
  func processShareIntent(from url: URL) {
    // Handle file URLs shared to the app
    if url.isFileURL {
      let fileInfo = getFileInfo(for: url)
      var extras: [String: String] = [:]
      
      // Add file metadata to extras
      if let fileName = fileInfo["fileName"] { extras["fileName"] = fileName }
      if let fileSize = fileInfo["fileSize"] { extras["fileSize"] = fileSize }
      if let mimeType = fileInfo["mimeType"] { extras["mimeType"] = mimeType }
      if let width = fileInfo["width"] { extras["width"] = width }
      if let height = fileInfo["height"] { extras["height"] = height }
      if let duration = fileInfo["duration"] { extras["duration"] = duration }
      
      let payload = SharePayload(
        type: .file,
        text: nil,
        files: [url.absoluteString],
        extras: extras
      )
      
      notifyListeners(payload)
    } else {
      // Handle web URLs
      var extras: [String: String] = [:]
      extras["url"] = url.absoluteString
      
      let payload = SharePayload(
        type: .text,
        text: url.absoluteString,
        files: nil,
        extras: extras
      )
      
      notifyListeners(payload)
    }
  }
  
  func processShareIntent(text: String, subject: String? = nil) {
    var extras: [String: String] = [:]
    if let subject = subject {
      extras["subject"] = subject
    }
    
    let payload = SharePayload(
      type: .text,
      text: text,
      files: nil,
      extras: extras
    )
    
    notifyListeners(payload)
  }
  
  func processShareIntent(files: [URL], text: String? = nil, subject: String? = nil) {
    var extras: [String: String] = [:]
    if let text = text {
      extras["text"] = text
    }
    if let subject = subject {
      extras["subject"] = subject
    }
    
    // Add file count for multiple files
    if files.count > 1 {
      extras["fileCount"] = String(files.count)
    }
    
    // Add metadata for single files
    if files.count == 1 {
      let fileInfo = getFileInfo(for: files[0])
      if let fileName = fileInfo["fileName"] { extras["fileName"] = fileName }
      if let fileSize = fileInfo["fileSize"] { extras["fileSize"] = fileSize }
      if let mimeType = fileInfo["mimeType"] { extras["mimeType"] = mimeType }
      if let width = fileInfo["width"] { extras["width"] = width }
      if let height = fileInfo["height"] { extras["height"] = height }
      if let duration = fileInfo["duration"] { extras["duration"] = duration }
    }
    
    let type: ShareType = files.count > 1 ? .multiple : .file
    
    let payload = SharePayload(
      type: type,
      text: text,
      files: files.map { $0.absoluteString },
      extras: extras
    )
    
    notifyListeners(payload)
  }
  
  private func notifyListeners(_ payload: SharePayload) {
    if initialSharePayload == nil {
      initialSharePayload = payload
    }
    
    // Notify all listeners
    for listener in listeners {
      listener(payload)
    }
  }
  
  private func getFileInfo(for url: URL) -> [String: String] {
    var fileInfo: [String: String] = [:]
    
    // Get basic file attributes
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
        fileInfo["mimeType"] = contentType.preferredMIMEType ?? "application/octet-stream"
        
        // Get image/video specific metadata
        if contentType.conforms(to: .image) {
          getImageInfo(for: url, into: &fileInfo)
        } else if contentType.conforms(to: .movie) {
          getVideoInfo(for: url, into: &fileInfo)
        }
      }
    } catch {
      print("Error getting file info: \(error)")
    }
    
    return fileInfo
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
    
    // Get video dimensions
    if let videoTrack = asset.tracks(withMediaType: .video).first {
      let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
      fileInfo["width"] = String(Int(abs(size.width)))
      fileInfo["height"] = String(Int(abs(size.height)))
    }
    
    // Get duration
    let duration = asset.duration
    if duration.isValid {
      let durationInSeconds = CMTimeGetSeconds(duration)
      fileInfo["duration"] = String(Int(durationInSeconds * 1000)) // Convert to milliseconds
    }
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
