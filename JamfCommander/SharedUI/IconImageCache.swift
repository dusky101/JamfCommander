//
//  IconImageCache.swift
//  JamfCommander
//
//  Small two-tier cache for Self Service icon images: an in-memory `NSCache` backed by a
//  per-icon file in the app's Caches directory. Icons in Jamf are immutable by id, so
//  caching each image under its id never goes stale — there is no need to "count and
//  refresh". The set of *available* icons is fetched live per search (see the picker), so
//  newly added icons always appear.
//
//  Image bytes are resolved by asking the Jamf Pro API for the icon's CDN URL
//  (`GET /api/v1/icon/{id}`) and downloading it; the bearer token is host-guarded in
//  `JamfAPIService.downloadIconData`, so it is never sent to the CDN.
//

import SwiftUI
import AppKit

@MainActor
final class IconImageCache {
    static let shared = IconImageCache()

    private let memory = NSCache<NSNumber, NSImage>()
    private let directory: URL?

    private init() {
        let fileManager = FileManager.default
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = caches.appendingPathComponent("JamfCommanderIcons", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
        } else {
            directory = nil
        }
    }

    /// Returns a cached image (memory, then disk) for the icon id, or nil if not cached.
    func cachedImage(id: Int) -> NSImage? {
        let key = NSNumber(value: id)
        if let image = memory.object(forKey: key) {
            return image
        }
        guard let directory else { return nil }
        let fileURL = directory.appendingPathComponent("\(id).img")
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            memory.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    /// Stores raw image bytes for an icon id in both tiers.
    func store(id: Int, data: Data) {
        guard let image = NSImage(data: data) else { return }
        memory.setObject(image, forKey: NSNumber(value: id))
        if let directory {
            try? data.write(to: directory.appendingPathComponent("\(id).img"))
        }
    }

    /// Returns a cached icon image, or resolves its CDN URL via the Jamf Pro API,
    /// downloads it, caches it, and returns it. Returns nil if it can't be loaded.
    func loadImage(id: Int, using api: JamfAPIService) async -> NSImage? {
        if let cached = cachedImage(id: id) {
            return cached
        }
        guard let urlString = try? await api.fetchIconURL(id: id),
              let data = try? await api.downloadIconData(from: urlString),
              NSImage(data: data) != nil else {
            return nil
        }
        store(id: id, data: data)
        return cachedImage(id: id)
    }
}
