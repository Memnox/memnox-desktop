import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A QR drawn from a link with CoreImage's own generator, so pairing a phone needs no package.
enum QRImage {
    /// Medium correction, enough to read through glare on a screen without making the code dense.
    private static let correction = "M"
    /// Each module drawn this many pixels wide, so the edges stay sharp when the view scales it.
    private static let moduleScale: CGFloat = 10

    /// The code as an image, or nil when CoreImage could not draw it.
    static func make(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction
        guard let drawn = filter.outputImage else { return nil }
        let scaled = drawn.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        guard let pixels = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: pixels, size: scaled.extent.size)
    }
}
