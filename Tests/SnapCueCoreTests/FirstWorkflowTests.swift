import AppKit
import ImageIO
import Testing
@testable import SnapCueCore

struct FirstWorkflowTests {
    @Test("CAP-01 rounds outwards and clips to the starting display")
    func scaledEdgeSelection() {
        let display = CGSize(width: 100, height: 50)
        let bitmap = CGSize(width: 200, height: 100)
        #expect(Region.pixels(from: CGPoint(x: 110, y: 49.25), to: CGPoint(x: 90.25, y: 40.25),
                              display: display, bitmap: bitmap) == CGRect(x: 180, y: 80, width: 20, height: 19))
        #expect(Region.pixels(from: CGPoint(x: 12, y: 3), to: CGPoint(x: 12, y: 30),
                              display: display, bitmap: bitmap) == nil)
        #expect(Region.pixels(from: CGPoint(x: -20, y: 3), to: CGPoint(x: -1, y: 30),
                              display: display, bitmap: bitmap) == nil)
    }

    @Test("P-CAP-GEOMETRY is reversible and bounded", arguments: [UInt64(7), 21, 41, 99])
    func generatedSelections(seed: UInt64) {
        var generator = Generator(state: seed)
        var accepted = 0
        for index in 0..<100 {
            let display = CGSize(width: generator.next(1...120), height: generator.next(1...80))
            let scale = CGFloat(generator.next(1...2))
            let bitmap = CGSize(width: display.width * scale, height: display.height * scale)
            let start = generator.point(in: display)
            let end = generator.point(in: display)
            let forward = Region.pixels(from: start, to: end, display: display, bitmap: bitmap)
            let reverse = Region.pixels(from: end, to: start, display: display, bitmap: bitmap)
            let input: Comment = "seed \(seed), case \(index), display \(display), bitmap \(bitmap), drag \(start) → \(end)"
            #expect(forward == reverse, input)
            if let selection = forward {
                accepted += 1
                #expect(!selection.isEmpty && CGRect(origin: .zero, size: bitmap).contains(selection), input)
                #expect(selection == selection.integral, input)
            }
        }
        #expect(accepted > 0)
    }

    @MainActor
    @Test("EDT-01 and OUT-01 flatten an arrow and label at native size")
    func markedPNG() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let width = 160
        let height = 100
        let bitmap = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(red: 0, green: 1, blue: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 90, width: width, height: 10))

        var draft = Draft(image: try #require(bitmap.makeImage()))
        draft.marks = [.arrow(CGPoint(x: 10, y: 20), CGPoint(x: 65, y: 20)),
                       .label(CGPoint(x: 85, y: 60), "Check")]
        let data = try #require(draft.png())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width)
        #expect(image.height == height)

        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y * bitmap.bytesPerRow + x * 4
            return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
        }
        #expect(pixel(2, 2) == [0, 255, 0, 255])
        #expect(pixel(2, 97) == [0, 255, 255, 255])
        let arrow = pixel(30, 20)
        #expect(arrow[0] > arrow[1] && arrow[0] > arrow[2])
        let label = pixel(90, 63)
        #expect(label[1] < 100 && label[2] < 100)

        let arrowIndex = try #require(draft.markIndex(at: CGPoint(x: 30, y: 20), tolerance: 5))
        let labelIndex = try #require(draft.markIndex(at: CGPoint(x: 90, y: 63), tolerance: 5))
        draft.marks[arrowIndex] = draft.movedMark(at: arrowIndex, by: CGPoint(x: 0, y: 20))
        draft.marks[labelIndex] = draft.movedMark(at: labelIndex, by: CGPoint(x: -35, y: 0))
        #expect(draft.markIndex(at: CGPoint(x: 30, y: 20), tolerance: 5) == nil)
        #expect(draft.markIndex(at: CGPoint(x: 30, y: 40), tolerance: 5) == arrowIndex)
        #expect(draft.markIndex(at: CGPoint(x: 55, y: 63), tolerance: 5) == labelIndex)

        let movedPNG = try #require(draft.png())
        let movedSource = try #require(CGImageSourceCreateWithData(movedPNG as CFData, nil))
        let movedImage = try #require(CGImageSourceCreateImageAtIndex(movedSource, 0, nil))
        bitmap.draw(movedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        #expect(pixel(30, 20) == [0, 255, 255, 255])
        #expect(pixel(30, 40)[0] > pixel(30, 40)[1])
        #expect(pixel(55, 63)[1] < 100)
    }
}

private struct Generator {
    var state: UInt64

    mutating func next(_ range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1
        return range.lowerBound + Int((state >> 32) % UInt64(range.count))
    }

    mutating func point(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(next(-40...(Int(size.width) * 4 + 40))) / 4,
                y: CGFloat(next(-40...(Int(size.height) * 4 + 40))) / 4)
    }
}
