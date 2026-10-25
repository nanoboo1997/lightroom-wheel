import Foundation
import CoreGraphics

@main struct TestLogic {
    static func main() {
        let e = ControlSpec.all.first { $0.name == "Exposure" }!
        precondition(e.adjusted(0, ticks: 1, fineMode: false) == 0.05)
        precondition(e.adjusted(0, ticks: -1, fineMode: true) == -0.01)
        precondition(e.adjusted(4.99, ticks: 8, fineMode: false) == 5)
        precondition(e.format(-0.05) == "-0.05")
        precondition(Detector.number("−17") == -17)
        precondition(Detector.number("0.00x") == nil)
        let w = CGRect(x: 0, y: 0, width: 1000, height: 900)
        var boxes = [TextBox(text: "Basic", rect: CGRect(x: 940, y: 200, width: 35, height: 12), confidence: 1)]
        for (i,name) in ["Exposure", "Contrast", "Highlights"].enumerated() {
            boxes.append(.init(text: name, rect: CGRect(x: 725, y: 300+i*25, width: 50, height: 12), confidence: 1))
            boxes.append(.init(text: "0", rect: CGRect(x: 960, y: 300+i*25, width: 12, height: 12), confidence: 1))
        }
        let rows = Detector.rows(boxes, window: w, windowID: 1, seen: 0)
        precondition(rows.count == 3)
        precondition(rows[0].track.contains(CGPoint(x: 850, y: 306)))
        precondition(!rows[0].track.contains(CGPoint(x: 850, y: 320)))
        precondition(Detector.rows(Array(boxes.dropFirst()), window: w, windowID: 1, seen: 0).isEmpty)
        var scrolled = [TextBox(text: "Profile:", rect: CGRect(x: 720,y: 180,width: 45,height: 12), confidence: 1), TextBox(text: "Tone", rect: CGRect(x: 720,y: 265,width: 45,height: 12), confidence: 1)]
        for (i,spec) in ControlSpec.all.enumerated() {
            scrolled.append(.init(text: spec.name,rect: CGRect(x: 725,y: 210+i*25+(i>=2 ? 35 : 0)+(i>=8 ? 40 : 0),width: 50,height: 12),confidence: 1))
            scrolled.append(.init(text: "0",rect: CGRect(x: 960,y: 210+i*25+(i>=2 ? 35 : 0)+(i>=8 ? 40 : 0),width: 12,height: 12),confidence: 1))
        }
        precondition(Detector.rows(scrolled,window:w,windowID:1,seen:0).count == 13)
        precondition(Detector.rows(Array(scrolled.dropFirst(2)),window:w,windowID:1,seen:0).isEmpty)
        precondition(Detector.rows(Array(scrolled.prefix(14)),window:w,windowID:1,seen:0).isEmpty)
        scrolled[0] = .init(text:"Presence",rect:CGRect(x:720,y:450,width:45,height:6),confidence:1)
        precondition(Detector.rows(scrolled,window:w,windowID:1,seen:0).count == 13)
        precondition(Detector.rows(scrolled.filter { $0.text != "Vibrance" },window:w,windowID:1,seen:0).isEmpty)
        // Window origin is already included in global OCR boxes. Never add 38pt again.
        let realWindow=CGRect(x:0,y:38,width:1920,height:1116)
        var realBoxes=[TextBox(text:"Basic",rect:CGRect(x:1840,y:340,width:35,height:12),confidence:1)]
        for (name,y) in [("Exposure",548.0),("Contrast",565.5),("Highlights",592.3)] {
            realBoxes.append(.init(text:name,rect:CGRect(x:1625,y:y,width:50,height:12),confidence:1))
            realBoxes.append(.init(text:"0",rect:CGRect(x:1850,y:y,width:20,height:12),confidence:1))
        }
        let realRows=Detector.rows(realBoxes,window:realWindow,windowID:1,seen:0)
        precondition(realRows.first(where:{$0.track.contains(CGPoint(x:1750,y:557.8))})?.spec.name == "Exposure")
        var tooltip=realBoxes
        tooltip.insert(.init(text:"Exposure",rect:CGRect(x:1625,y:100,width:50,height:12),confidence:1),at:0)
        tooltip.insert(.init(text:"0",rect:CGRect(x:1850,y:100,width:20,height:12),confidence:1),at:1)
        precondition(Detector.rows(tooltip,window:realWindow,windowID:1,seen:0).first?.spec.name == "Exposure")
        precondition(Detector.rows(tooltip,window:realWindow,windowID:1,seen:0).first?.track.minY == 548)
        var accumulator = WheelAccumulator()
        precondition(accumulator.consume(delta: 1, continuous: false, control: "Exposure", time: 0) == 1)
        precondition(accumulator.consume(delta: 6, continuous: true, control: "Exposure", time: 0.1) == 0)
        precondition(accumulator.consume(delta: 6, continuous: true, control: "Exposure", time: 0.2) == 1)
        precondition(accumulator.consume(delta: -12, continuous: true, control: "Contrast", time: 0.3) == -1)
        // Accelerated wheels must preserve all detents, including direction changes.
        precondition(accumulator.consume(delta: 35, continuous: false, control: "Exposure", time: 0.4) == 35)
        precondition(accumulator.consume(delta: -27, continuous: false, control: "Exposure", time: 0.5) == -27)
        print("PASS: limits, precision, OCR gating, row hit areas, wheel accumulation")
    }
}
