import Foundation
import CoreGraphics

struct ControlSpec {
    let name: String
    let minimum: Double
    let maximum: Double
    let step: Double
    let fine: Double
    let decimals: Int
    static let all: [ControlSpec] = [
        .init(name: "Temp", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Tint", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Exposure", minimum: -5, maximum: 5, step: 0.05, fine: 0.01, decimals: 2),
        .init(name: "Contrast", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Highlights", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Shadows", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Whites", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Blacks", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Texture", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Clarity", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Dehaze", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Vibrance", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0),
        .init(name: "Saturation", minimum: -100, maximum: 100, step: 1, fine: 1, decimals: 0)
    ]
    func adjusted(_ value: Double, ticks: Int, fineMode: Bool, fast: Bool = false) -> Double {
        let quantum = (fineMode ? fine : step) * (fast ? 5 : 1)
        return min(maximum, max(minimum, ((value + Double(ticks) * quantum) * 100).rounded() / 100))
    }
    func format(_ value: Double) -> String { String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, value) }
}

struct TextBox { let text: String; let rect: CGRect; let confidence: Float }
struct SliderRow {
    let spec: ControlSpec
    let track: CGRect
    let valuePoint: CGPoint
    let value: Double
    let window: CGRect
    let windowID: UInt32
    let seen: TimeInterval
}

enum Detector {
    static func number(_ text: String) -> Double? {
        let s = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        guard s.range(of: #"^[+-]?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        return Double(s)
    }
    static func rows(_ boxes: [TextBox], window: CGRect, windowID: UInt32, seen: TimeInterval) -> [SliderRow] {
        // When the heading is scrolled out, require Basic-only context and many pairs.
        let basic = boxes.first(where: { $0.text == "Basic" && $0.confidence >= 0.5 })
        let context = boxes.filter { ["Profile:", "Profile", "WB:", "WB", "Tone", "Presence"].contains($0.text) && $0.confidence >= 0.6 }
        let hasProfile = context.contains(where: { $0.text.hasPrefix("Profile") || $0.text.hasPrefix("WB") })
        let hasSections = context.contains(where: { $0.text == "Tone" }) && context.contains(where: { $0.text == "Presence" })
        let hasVibrance = boxes.contains(where: { $0.text == "Vibrance" && $0.confidence >= 0.6 })
        guard basic != nil || ((hasProfile || (hasSections && hasVibrance)) && context.contains(where: { $0.text == "Tone" || $0.text == "Presence" })) else { return [] }
        let startY = basic?.rect.maxY ?? window.minY
        let endY = boxes.filter { ["Tone Curve", "Color Mixer", "Detail", "Lens Corrections"].contains($0.text) && $0.rect.minY > startY }.map(\.rect.minY).min() ?? window.maxY
        var output: [SliderRow] = []
        for spec in ControlSpec.all {
            let tone = boxes.first(where: { $0.text == "Tone" && $0.confidence >= 0.6 })
            let presence = boxes.first(where: { $0.text == "Presence" && $0.confidence >= 0.6 })
            let isWB = ["Temp","Tint"].contains(spec.name)
            let isPresence = ["Texture","Clarity","Dehaze","Vibrance","Saturation"].contains(spec.name)
            let lower = isPresence ? max(startY,presence?.rect.maxY ?? startY) : (isWB ? startY : max(startY,tone?.rect.maxY ?? startY))
            let upper = isWB ? min(endY,tone?.rect.minY ?? endY) : (isPresence ? endY : min(endY,presence?.rect.minY ?? endY))
            guard let label = boxes.first(where: { $0.text == spec.name && $0.confidence >= 0.6 && $0.rect.minY > lower && $0.rect.maxY < upper }) else { continue }
            let candidates = boxes.filter { b in
                b.confidence >= 0.55 && abs(b.rect.midY - label.rect.midY) <= max(5, label.rect.height * 0.45) && b.rect.minX > label.rect.maxX + 60 && number(b.text) != nil
            }
            guard candidates.count == 1, let valueBox = candidates.first, let value = number(valueBox.text), (spec.minimum...spec.maximum).contains(value) else { continue }
            let x0 = label.rect.maxX + 9, x1 = valueBox.rect.minX - 13
            guard x1 - x0 >= 75, x1 - x0 <= 250 else { continue }
            output.append(.init(spec: spec, track: CGRect(x: x0, y: label.rect.midY - 6, width: x1-x0, height: 12), valuePoint: CGPoint(x: valueBox.rect.midX, y: valueBox.rect.midY), value: value, window: window, windowID: windowID, seen: seen))
        }
        return output.count >= (basic == nil ? 8 : 3) ? output : []
    }
}

struct WheelAccumulator {
    private var residual: Double = 0
    private var identity = ""
    private var last: TimeInterval = 0
    mutating func consume(delta: Double, continuous: Bool, control: String, time: TimeInterval) -> Int {
        if control != identity || time - last > 0.25 || residual * delta < 0 { residual = 0 }
        identity = control; last = time
        residual += continuous ? delta / 12 : delta
        let ticks = Int(residual.rounded(.towardZero))
        residual -= Double(ticks)
        return ticks
    }
}
