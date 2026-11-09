import Foundation

@main struct EnrollmentStreamChecks {
    static func main() throws {
        let json = "{\"event\":\"frame\",\"hint\":\"visage détecté\",\"jpeg\":\"" + String(repeating: "a", count: 80_000) + "\"}\n{\"event\":\"done\"}\n"
        let bytes = Data(json.utf8)
        for chunk in [1, 7, 1024, 4096, 65536, bytes.count] {
            let stream = EnrollmentStream()
            var events = [[String: Any]]()
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + chunk, bytes.count)
                events += stream.consume(bytes.subdata(in: offset..<end))
                offset = end
            }
            precondition(events.count == 2, "Lost events with chunk size \(chunk)")
            precondition(events[0]["hint"] as? String == "visage détecté", "Split UTF-8 was corrupted")
            precondition(events[1]["event"] as? String == "done", "Final event was lost")
        }
        let stream = EnrollmentStream()
        precondition(stream.consume(Data("invalid\n{\"event\":\"done\"}\n".utf8)).count == 1)
        print("OK — large video events, split UTF-8, multiple events and final done event")
    }
}
