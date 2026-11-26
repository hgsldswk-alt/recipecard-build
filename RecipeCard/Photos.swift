import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RecipePhoto {
    static func normalized(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 40_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...24_000).contains(width), (1...24_000).contains(height), width * height <= 160_000_000,
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw RecipeIssue.filePhoto }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RecipeIssue.filePhoto
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest), output.length <= RecipeTransfer.maxPhotoBytes,
              let check = CGImageSourceCreateWithData(output as CFData, nil),
              CGImageSourceGetCount(check) == 1, CGImageSourceGetStatus(check) == .statusComplete else {
            throw RecipeIssue.filePhoto
        }
        return output as Data
    }
}
