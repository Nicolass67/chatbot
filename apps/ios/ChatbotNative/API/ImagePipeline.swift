import UIKit
import ImageIO

/// Cache miniatures thread-safe — actor + NSCache mémoire + disque.
actor ImageThumbCache {
    static let shared = ImageThumbCache()

    private let memory = NSCache<NSString, UIImage>()

    func image(forKey key: String) -> UIImage? {
        if let mem = memory.object(forKey: key as NSString) { return mem }
        if let disk = Self.loadFromDisk(key: key) {
            memory.setObject(disk, forKey: key as NSString)
            return disk
        }
        return nil
    }

    func store(_ image: UIImage, forKey key: String) {
        memory.setObject(image, forKey: key as NSString)
        Task.detached(priority: .utility) {
            guard let data = image.jpegData(compressionQuality: 0.82) else { return }
            let url = Self.diskURL(for: key)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func diskURL(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("att-thumbs", isDirectory: true)
            .appendingPathComponent("\(safe).jpg")
    }

    private static func loadFromDisk(key: String) -> UIImage? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

enum ImagePipeline {
    /// Réduit fortement le poids avant upload (cible ~1400px, JPEG 0.68).
    static func compressForUpload(_ data: Data, maxDimension: CGFloat = 1400, quality: CGFloat = 0.68) -> (Data, String) {
        guard let image = downsample(data: data, maxPixelSize: maxDimension)
            ?? UIImage(data: data) else {
            return (data, "image/jpeg")
        }
        let jpeg = image.jpegData(compressionQuality: quality) ?? data
        return (jpeg, "image/jpeg")
    }

    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    static func thumbnail(data: Data, maxPixelSize: CGFloat = 240) -> UIImage? {
        downsample(data: data, maxPixelSize: maxPixelSize) ?? UIImage(data: data)
    }

    static func cached(_ key: String) async -> UIImage? {
        await ImageThumbCache.shared.image(forKey: key)
    }

    static func store(_ image: UIImage, key: String) async {
        await ImageThumbCache.shared.store(image, forKey: key)
    }
}
