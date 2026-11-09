import CoreGraphics

public enum Region {
    /// Points are relative to the display's top-left corner.
    public static func pixels(
        from start: CGPoint, to end: CGPoint, display: CGSize, bitmap: CGSize
    ) -> CGRect? {
        let values = [start.x, start.y, end.x, end.y, display.width, display.height,
                      bitmap.width, bitmap.height]
        guard values.allSatisfy(\.isFinite),
              display.width > 0, display.height > 0,
              bitmap.width > 0, bitmap.height > 0 else { return nil }

        let left = max(0, min(start.x, end.x))
        let top = max(0, min(start.y, end.y))
        let right = min(display.width, max(start.x, end.x))
        let bottom = min(display.height, max(start.y, end.y))
        guard right > left, bottom > top else { return nil }

        let x = (left / display.width * bitmap.width).rounded(.down)
        let y = (top / display.height * bitmap.height).rounded(.down)
        let maxX = (right / display.width * bitmap.width).rounded(.up)
        let maxY = (bottom / display.height * bitmap.height).rounded(.up)
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}
