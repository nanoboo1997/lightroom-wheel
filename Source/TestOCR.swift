import Foundation
import AppKit
import Vision
import CoreText

@main struct TestOCR {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let full = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let scale = CGFloat(full.width) / 1920
        let win = CGRect(x: 0, y: 0, width: CGFloat(full.width)/scale, height: CGFloat(full.height)/scale)
        let crop = CGRect(x: win.width-300, y: 140, width: 300, height: win.height-420)
        let image = full.cropping(to: CGRect(x:crop.minX*scale,y:crop.minY*scale,width:crop.width*scale,height:crop.height*scale))!
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(cgImage: image).perform([request])
        var boxes: [TextBox] = []
        for result in request.results ?? [] {
            guard let text = result.topCandidates(1).first else { continue }
            let r = result.boundingBox
            let rect = CGRect(x: crop.minX+r.minX*crop.width, y:crop.minY+(1-r.maxY)*crop.height,width:r.width*crop.width,height:r.height*crop.height)
            boxes.append(.init(text:text.string,rect:rect,confidence:text.confidence))
            print(text.string, rect, text.confidence)
        }
        let numeric = try NumericOCR.read(image:image,crop:crop,window:win,labels:boxes,debug:true)
        boxes.removeAll { Detector.number($0.text) != nil }
        boxes.append(contentsOf:numeric)
        for b in numeric {print("NUMERIC",b.text,b.rect)}
        let rows = Detector.rows(boxes,window:win,windowID:1,seen:0)
        print("DETECTED",rows.count)
        for row in rows { print(row.spec.name,row.value,row.track,row.valuePoint) }
        if rows.count != 13 { print("FAIL: expected 13 controls"); exit(1) }
        print("PASS: all 13 controls detected from the Classic screenshot fixture")
    }
}
