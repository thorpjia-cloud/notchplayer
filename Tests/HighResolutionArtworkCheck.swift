import AppKit
import SQLite3

final class DelayedArtwork: URLProtocol {
    static var red = Data(), blue = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let old = request.url!.path.contains("red")
        DispatchQueue.global().asyncAfter(deadline: .now() + (old ? 0.20 : 0.02)) {
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/png"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: old ? Self.red : Self.blue)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
@main enum Check {
    @MainActor static func main() async throws {
        func image(_ color: NSColor, _ size: Int) -> Data {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let context=NSGraphicsContext(bitmapImageRep:rep)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;color.setFill();NSBezierPath(rect:CGRect(x:0,y:0,width:size,height:size)).fill();NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using:.png,properties:[:])!
        }
        let red=image(.red,100),blue=image(.blue,100)
        DelayedArtwork.red=image(.red,600);DelayedArtwork.blue=image(.blue,600)
        precondition(HighResolutionArtwork.sameArtwork(red,DelayedArtwork.red))
        precondition(!HighResolutionArtwork.sameArtwork(red,DelayedArtwork.blue))
        let dbURL=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
        defer {try? FileManager.default.removeItem(at:dbURL)}
        var db: OpaquePointer?;sqlite3_open(dbURL.path,&db)
        sqlite3_exec(db,"CREATE TABLE dbTrack(jsonStr TEXT);",nil,nil,nil)
        for title in ["red","blue","redAgain"] {
            let v:[String:Any]=["name":title,"id":title,"duration":100000,"artists":[["name":"artist"]],"album":["name":"album","picUrl":"https://p4.music.126.net/"+title+".png"]]
            let json=String(data:try JSONSerialization.data(withJSONObject:v),encoding:.utf8)!
            var stmt:OpaquePointer?;sqlite3_prepare_v2(db,"INSERT INTO dbTrack VALUES (?)",-1,&stmt,nil)
            _=json.withCString{sqlite3_bind_text(stmt,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))};sqlite3_step(stmt);sqlite3_finalize(stmt)
        }
        sqlite3_close(db)
        func track(_ title:String)->ArtworkState.Track { ArtworkState.Track(["title":title,"artist":"artist","album":"album","bundleIdentifier":"com.netease.163music"])! }
        precondition(HighResolutionArtwork.sources(track:track("red"),duration:100,database:dbURL).count==1)
        precondition(HighResolutionArtwork.sources(track:track("red"),duration:120,database:dbURL).isEmpty)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[DelayedArtwork.self]
        let resolver=HighResolutionArtwork(database:dbURL,session:URLSession(configuration:config));var accepted:[String]=[]
        resolver.resolve(track:track("red"),reference:red,duration:100){_ in accepted.append("red")}
        try await Task.sleep(nanoseconds:80000000)
        resolver.resolve(track:track("blue"),reference:blue,duration:100){_ in accepted.append("blue")}
        try await Task.sleep(nanoseconds:450000000)
        precondition(accepted==["blue"],"An older request cannot replace the new track")
        let handoffResolver=HighResolutionArtwork(database:dbURL,session:URLSession(configuration:config))
        let service=MediaService(highResolutionArtwork:handoffResolver)
        func payload(_ title: String) -> [String: Any] {
            ["title":title,"artist":"artist","album":"album","bundleIdentifier":"com.netease.163music",
             "playing":false,"durationMicros":100000000,"artworkData":red.base64EncodedString()]
        }
        service.apply(payload("red"))
        try await Task.sleep(nanoseconds:80000000)
        service.apply(payload("redAgain"))
        try await Task.sleep(nanoseconds:450000000)
        precondition(service.title=="redAgain" && (service.artwork?.representations.map { $0.pixelsWide }.max() ?? 0)>=312,
                     "Same-thumbnail album handoff must restart the pending high-resolution request")
        service.stop()
        print("PASS same-album same-thumbnail MediaService handoff")
        print("PASS exact metadata, duration rejection, image identity, 600px size and cancelled old request")
    }
}
