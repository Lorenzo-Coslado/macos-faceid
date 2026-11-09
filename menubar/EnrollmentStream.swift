import Foundation

/// Pipe reads can split a JPEG/JSON event anywhere, including inside UTF-8.
final class EnrollmentStream {
    private var pending = Data()
    private let lock = NSLock()

    func consume(_ data: Data) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        pending.append(data)
        var events = [[String: Any]]()
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending.prefix(upTo: newline)
            if let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
                events.append(event)
            }
            pending.removeSubrange(...newline)
        }
        if pending.count > 2_000_000 { pending.removeAll() }
        return events
    }
}
