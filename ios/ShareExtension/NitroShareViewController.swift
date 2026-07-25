//
//  NitroShareViewController.swift
//
//  The Share Extension's principal class, shipped inside the pod so the
//  generated extension target contains no consumer-authored source at all
//  (see ios/NitroShareIntentSetup.rb, which creates that target during
//  `pod install` and points NSExtensionPrincipalClass here).
//
//  A share extension runs in its own sandbox and cannot write into the host
//  app's `Documents/Inbox`, so everything is handed over through the shared
//  App Group container:
//
//      <appGroup>/NitroShareIntent/<uuid>/
//          <copied files...>
//          payload.json      <- written LAST, marks the drop as complete
//
//  The host app picks those up in `NitroShareIntent.swift`. `payload.json` is
//  written after the files so a half-copied drop is never consumed.
//

import UIKit
import UniformTypeIdentifiers

open class NitroShareViewController: UIViewController {

  /// Injected by the setup script into the extension's Info.plist.
  private var appGroupIdentifier: String? {
    Bundle.main.object(forInfoDictionaryKey: "NitroShareIntentAppGroup") as? String
  }

  /// Custom URL scheme of the host app, used to foreground it after the drop.
  private var hostURLScheme: String? {
    Bundle.main.object(forInfoDictionaryKey: "NitroShareIntentHostURLScheme") as? String
  }

  private var shouldOpenHostApp: Bool {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "NitroShareIntentOpenHostApp") else {
      return true
    }
    return (value as? Bool) ?? true
  }

  open override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    processShare()
  }

  private func processShare() {
    guard let appGroup = appGroupIdentifier,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
      completeRequest()
      return
    }

    let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    let attachments = items.flatMap { $0.attachments ?? [] }

    guard !attachments.isEmpty else {
      completeRequest()
      return
    }

    let dropURL = container
      .appendingPathComponent("NitroShareIntent", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    do {
      try FileManager.default.createDirectory(at: dropURL, withIntermediateDirectories: true)
    } catch {
      completeRequest()
      return
    }

    var files: [String] = []
    var text: String?
    var extras: [String: String] = [:]
    let lock = NSLock()
    let group = DispatchGroup()

    for attachment in attachments {
      group.enter()
      load(attachment: attachment, into: dropURL) { result in
        lock.lock()
        switch result {
        case .file(let name):
          files.append(name)
        case .text(let value):
          // Multiple text attachments are rare; keep the first non-empty one
          // and expose the rest through `extras` rather than dropping them.
          if text == nil {
            text = value
          } else {
            extras["text\(extras.count + 1)"] = value
          }
        case .none:
          break
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self = self else { return }
      self.writePayload(at: dropURL, files: files, text: text, extras: extras)
      self.openHostAppIfNeeded()
      self.completeRequest()
    }
  }

  private enum LoadResult {
    case file(String)
    case text(String)
    case none
  }

  private func load(
    attachment: NSItemProvider,
    into dropURL: URL,
    completion: @escaping (LoadResult) -> Void
  ) {
    // `registeredTypeIdentifiers` is ordered most- to least-specific, so the
    // first identifier that yields a file URL is the richest representation.
    let typeIdentifier = attachment.registeredTypeIdentifiers.first ?? (UTType.data.identifier)

    attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
      guard let self = self else {
        completion(.none)
        return
      }

      switch item {
      case let url as URL where url.isFileURL:
        completion(self.copy(fileURL: url, into: dropURL))

      case let url as URL:
        // A web URL arrives as a URL that isn't a file - treat it as text so
        // JS receives it the same way a shared link does anywhere else.
        completion(.text(url.absoluteString))

      case let string as String:
        completion(.text(string))

      case let image as UIImage:
        completion(self.write(image: image, into: dropURL))

      case let data as Data:
        let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin"
        completion(self.write(data: data, name: "\(UUID().uuidString).\(ext)", into: dropURL))

      default:
        completion(.none)
      }
    }
  }

  private func copy(fileURL: URL, into dropURL: URL) -> LoadResult {
    let name = fileURL.lastPathComponent.isEmpty ? UUID().uuidString : fileURL.lastPathComponent
    let target = uniqueURL(for: name, in: dropURL)
    do {
      try FileManager.default.copyItem(at: fileURL, to: target)
      return .file(target.lastPathComponent)
    } catch {
      return .none
    }
  }

  private func write(image: UIImage, into dropURL: URL) -> LoadResult {
    guard let data = image.pngData() else { return .none }
    return write(data: data, name: "\(UUID().uuidString).png", into: dropURL)
  }

  private func write(data: Data, name: String, into dropURL: URL) -> LoadResult {
    let target = uniqueURL(for: name, in: dropURL)
    do {
      try data.write(to: target)
      return .file(target.lastPathComponent)
    } catch {
      return .none
    }
  }

  /// Two attachments can carry the same filename (e.g. `IMG_0001.jpg` from
  /// different albums); suffix collisions instead of overwriting.
  private func uniqueURL(for name: String, in dropURL: URL) -> URL {
    var candidate = dropURL.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var index = 1
    repeat {
      let suffixed = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
      candidate = dropURL.appendingPathComponent(suffixed)
      index += 1
    } while FileManager.default.fileExists(atPath: candidate.path)

    return candidate
  }

  private func writePayload(at dropURL: URL, files: [String], text: String?, extras: [String: String]) {
    var payload: [String: Any] = [:]

    if files.isEmpty {
      payload["type"] = "text"
    } else {
      payload["type"] = files.count > 1 ? "multiple" : "file"
    }

    payload["files"] = files
    if let text = text { payload["text"] = text }

    var allExtras = extras
    if files.count > 1 { allExtras["fileCount"] = String(files.count) }
    if !allExtras.isEmpty { payload["extras"] = allExtras }

    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    // Written last: the host treats `payload.json` as the completion marker.
    try? data.write(to: dropURL.appendingPathComponent("payload.json"), options: .atomic)
  }

  private func openHostAppIfNeeded() {
    guard shouldOpenHostApp,
          let scheme = hostURLScheme,
          let url = URL(string: "\(scheme)://nitro-share-intent") else {
      return
    }

    // Extensions have no `UIApplication` of their own, so reach the host's
    // one through the responder chain. Set `openHostApp` to false in the
    // package config to skip this and let the app collect the share the next
    // time it becomes active instead.
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: Selector(("openURL:"))) {
        _ = current.perform(Selector(("openURL:")), with: url)
        return
      }
      responder = current.next
    }
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
