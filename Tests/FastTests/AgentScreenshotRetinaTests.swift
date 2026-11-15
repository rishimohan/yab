import AppKit
import Testing
@testable import Fast

/// yab-mcp#7: screenshot's retina gives every pixel as PNG; the default
/// stays a 1024-wide JPEG, the size click's points are in.
struct AgentScreenshotRetinaTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    @Test func defaultStaysA1024WideJPEG() throws {
        let (data, wide, high) = try #require(Bench.encode(try image(width: 2560, height: 1600), width: 1024, png: false))
        #expect((wide, high) == (1024, 640))
        #expect(data.starts(with: [0xFF, 0xD8]))
    }

    @Test func retinaKeepsEveryPixelAsPNG() throws {
        let (data, wide, high) = try #require(Bench.encode(try image(width: 2560, height: 1600), width: nil, png: true))
        #expect((wide, high) == (2560, 1600))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
