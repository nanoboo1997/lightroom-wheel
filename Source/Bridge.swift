import Foundation

struct BridgeState {
    let photo: String
    let module: String
    let count: Int
    let values: [String: Double]
}
struct BridgeReply {let before:Double;let after:Double;let photo:String}
enum BridgeError: LocalizedError {
    case unavailable, message(String), timeout
    var errorDescription:String? {
        switch self {
        case .unavailable:return "ยังไม่พบปลั๊กอิน Lightroom Wheel Free Bridge ที่กำลังทำงาน"
        case .message(let text):return text
        case .timeout:return "ปลั๊กอินไม่ตอบกลับ จึงหยุดส่งคำสั่ง"
        }
    }
}
final class LightroomBridge {
    let folder:URL
    init(){folder=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Lightroom Wheel.lrplugin/bridge")}
    func state() throws -> BridgeState {
        let url=folder.appendingPathComponent("state.txt")
        guard let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),let modified=attrs[.modificationDate] as? Date,Date().timeIntervalSince(modified)<3,
            let text=try? String(contentsOf:url,encoding:.utf8) else {throw BridgeError.unavailable}
        let p=text.components(separatedBy:"|")
        guard p.count>=3,let count=Int(p[2]) else {throw BridgeError.unavailable}
        var values:[String:Double]=[:]
        for pair in p.dropFirst(3){let kv=pair.components(separatedBy:"=");if kv.count==2,let n=Double(kv[1]){values[kv[0]]=n}}
        return .init(photo:p[0],module:p[1],count:count,values:values)
    }
    func command(_ parameter:String,amount:Double,absolute:Bool=false,photo:String) async throws -> BridgeReply {
        guard ControlSpec.all.contains(where:{$0.name==parameter}),amount.isFinite,abs(amount)<=200 else {throw BridgeError.message("คำสั่งตัวปรับไม่ถูกต้อง")}
        let current=try state()
        guard current.module=="develop",current.count==1,current.photo==photo else {throw BridgeError.message("เลือกภาพเดียวใน Develop และอย่าเปลี่ยนภาพระหว่างปรับ")}
        let seq=UUID().uuidString
        let value=String(format:"%.6f",locale:Locale(identifier:"en_US_POSIX"),amount)
        try "\(seq)|\(absolute ? "set" : "adjust")|\(parameter)|\(value)|\(photo)".write(to:folder.appendingPathComponent("command.txt"),atomically:true,encoding:.utf8)
        for _ in 0..<200 {
            try await Task.sleep(nanoseconds:10_000_000)
            guard let text=try? String(contentsOf:folder.appendingPathComponent("reply.txt"),encoding:.utf8) else {continue}
            let p=text.components(separatedBy:"|")
            guard p.first==seq else {continue}
            if p.count>=3,p[1]=="error"{throw BridgeError.message(p[2])}
            if p.count==6,p[1]=="ok",let before=Double(p[3]),let after=Double(p[4]),p[5]==photo{return .init(before:before,after:after,photo:p[5])}
            throw BridgeError.message("คำตอบปลั๊กอินไม่ถูกต้อง")
        }
        throw BridgeError.timeout
    }
}
