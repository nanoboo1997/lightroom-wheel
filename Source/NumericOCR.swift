import Foundation
import AppKit
import Vision
import CoreText

enum NumericOCR {
    // Supply language context to Vision: isolated one-character numbers are otherwise omitted.
    static func read(image: CGImage, crop: CGRect, window: CGRect, labels: [TextBox], debug: Bool = false) throws -> [TextBox] {
        let sx = CGFloat(image.width)/crop.width, sy = CGFloat(image.height)/crop.height
        var patches: [(CGImage, CGRect, TextBox)] = []
        for label in labels where ControlSpec.all.contains(where: { $0.name == label.text }) {
            let local = CGRect(x: crop.width-90, y:label.rect.midY-crop.minY-9, width:65,height:18)
            let pixel = CGRect(x:local.minX*sx,y:local.minY*sy,width:local.width*sx,height:local.height*sy).integral
            guard let patch = image.cropping(to:pixel), let ctx = CGContext(data:nil,width:patch.width,height:patch.height,bitsPerComponent:8,bytesPerRow:patch.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue), let bytes=ctx.data else { continue }
            ctx.draw(patch,in:CGRect(x:0,y:0,width:patch.width,height:patch.height))
            let p=bytes.assumingMemoryBound(to:UInt8.self)
            var loX=patch.width, loY=patch.height, hiX = -1, hiY = -1
            for y in 0..<patch.height { for x in 0..<patch.width {
                let i=(y*patch.width+x)*4
                if min(p[i],min(p[i+1],p[i+2])) > 125 {
                    loX=min(loX,x);loY=min(loY,y);hiX=max(hiX,x);hiY=max(hiY,y)
                }
            }}
            guard hiX>=loX, hiY>=loY, hiX-loX>=3, hiY-loY>=8 else { continue }
            let gw=hiX-loX+5, gh=hiY-loY+5
            guard let normalized=CGContext(data:nil,width:gw,height:gh,bitsPerComponent:8,bytesPerRow:gw*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue),let target=normalized.data?.assumingMemoryBound(to:UInt8.self) else {continue}
            for y in 0..<gh {for x in 0..<gw {
                let ox=x+loX-2,oy=y+loY-2
                var shade:UInt8=71
                if ox>=0 && oy>=0 && ox<patch.width && oy<patch.height {
                    let si=(oy*patch.width+ox)*4
                    let brightness=Int(min(p[si],min(p[si+1],p[si+2])))
                    shade=UInt8(max(71,min(255,(brightness-85)*4)))
                }
                let ti=(y*gw+x)*4;target[ti]=shade;target[ti+1]=shade;target[ti+2]=shade;target[ti+3]=255
            }}
            guard let trimmed=normalized.makeImage() else {continue}
            let global=CGRect(x:crop.minX+(pixel.minX+CGFloat(loX-2))/sx,y:label.rect.midY-5,width:CGFloat(gw)/sx,height:10)
            patches.append((trimmed,global,label))
        }
        if debug {print("PATCH COUNT", patches.count, patches.map{$0.2.text})}
        guard !patches.isEmpty else { return [] }
        let rowHeight=90, canvasWidth=520, canvasHeight=patches.count*rowHeight
        let canvas=CGContext(data:nil,width:canvasWidth,height:canvasHeight,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        canvas.setFillColor(CGColor(gray:0.28,alpha:1));canvas.fill(CGRect(x:0,y:0,width:canvasWidth,height:canvasHeight))
        for (i,patch) in patches.enumerated() {
            let base=CGFloat(canvasHeight-(i+1)*rowHeight)
            canvas.textPosition=CGPoint(x:15,y:base+25)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"Value",attributes:[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.white])),canvas)
            let h=CGFloat(45), w=CGFloat(patch.0.width)*h/CGFloat(patch.0.height)
            canvas.draw(patch.0,in:CGRect(x:122,y:base+20,width:w,height:h))
        }
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=false;request.recognitionLanguages=["en-US"]
        if debug, let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:"/private/tmp/lrw-numeric-sheet.png") as CFURL,"public.png" as CFString,1,nil) { CGImageDestinationAddImage(dest,canvas.makeImage()!,nil);CGImageDestinationFinalize(dest) }
        try VNImageRequestHandler(cgImage:canvas.makeImage()!).perform([request])
        var output:[TextBox]=[]
        for result in request.results ?? [] {
            guard let candidate=result.topCandidates(1).first else {continue}
            if debug {print("CONTEXT OCR",candidate.string,result.boundingBox)}
            let raw=candidate.string.replacingOccurrences(of:"Value",with:"").trimmingCharacters(in:.whitespaces)
            guard Detector.number(raw) != nil else {continue}
            let row=Int((1-result.boundingBox.midY)*CGFloat(canvasHeight)/CGFloat(rowHeight))
            guard patches.indices.contains(row) else {continue}
            let patch=patches[row]
            output.append(.init(text:raw,rect:patch.1,confidence:candidate.confidence))
        }
        return output
    }
}
