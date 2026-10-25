import Foundation
import AppKit
import CoreText

@main struct TestNumeric {
    static func main() throws {
        let values=["0","-12","-0.05","35","-23","17","-50","100","-8","9","-6","22","-100"]
        let width=600,height=520
        let canvas=CGContext(data:nil,width:width*2,height:height*2,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        canvas.scaleBy(x:2,y:2);canvas.setFillColor(CGColor(gray:0.3,alpha:1));canvas.fill(CGRect(x:0,y:0,width:width,height:height))
        var labels:[TextBox]=[]
        for (i,spec) in ControlSpec.all.enumerated() {
            let y=CGFloat(70+i*28)
            labels.append(.init(text:spec.name,rect:CGRect(x:310,y:y,width:60,height:13),confidence:1))
            let text=NSAttributedString(string:values[i],attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor(white:0.75,alpha:1)])
            let line=CTLineCreateWithAttributedString(text)
            let bounds=CTLineGetBoundsWithOptions(line,[])
            canvas.textPosition=CGPoint(x:548-bounds.width,y:CGFloat(height)-y-12)
            CTLineDraw(line,canvas)
        }
        let frame=CGRect(x:0,y:0,width:width,height:height)
        let found=try NumericOCR.read(image:canvas.makeImage()!,crop:frame,window:frame,labels:labels)
        var failures=0
        for (i,label) in labels.enumerated() {
            let match=found.first{abs($0.rect.midY-label.rect.midY)<2}
            if let match,Detector.number(match.text)==Double(values[i]) {print("PASS",label.text,match.text)}
            else {print("FAIL",label.text,"expected",values[i],"got",match?.text ?? "missing");failures+=1}
        }
        print("Numeric fixture:",found.count,"read;",failures,"failures")
        let shiftedFrame=frame.offsetBy(dx:300,dy:230)
        let shiftedLabels=labels.map{TextBox(text:$0.text,rect:$0.rect.offsetBy(dx:300,dy:230),confidence:$0.confidence)}
        let shifted=try NumericOCR.read(image:canvas.makeImage()!,crop:shiftedFrame,window:shiftedFrame,labels:shiftedLabels)
        if shifted.count != 13 {failures+=1;print("FAIL: shifted window missing controls")}
        for original in found {
            guard let translated=shifted.first(where:{abs($0.rect.midY-original.rect.midY-230)<1}) else {failures+=1;continue}
            if abs(translated.rect.minX-original.rect.minX-300)>0.1 || translated.text != original.text {failures+=1;print("FAIL: global-coordinate translation")}
        }
        print("Shifted-window coordinate test:",failures==0 ? "PASS" : "FAIL")
        if failures>0 {exit(1)}
    }
}
