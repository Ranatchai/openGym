import Foundation
import Testing
import OpenGymCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["OPENGYM_LARGE_STATE"] != nil))
struct PerfTests {
    @Test func largeStateRoundTrip() throws {
        let path = ProcessInfo.processInfo.environment["OPENGYM_LARGE_STATE"]!
        let input = Corpus.bytes(URL(fileURLWithPath: path))
        let clock = ContinuousClock()
        var totals: [Duration] = []
        for run in 0..<7 {
            let start = clock.now
            let value = try JSONParser.parse(input)
            let parsed = clock.now
            let output = JSONSerializer.serialize(value)
            let end = clock.now
            #expect(output == input, "\(firstDifference(output, input))")
            if run >= 2 { totals.append(end - start) }
            print("PerfTests: run \(run) bytes \(input.count) parse \(ms(parsed - start)) ms serialize \(ms(end - parsed)) ms total \(ms(end - start)) ms\(run < 2 ? " (warmup)" : "")")
        }
        let sorted = totals.sorted()
        print("PerfTests: median total \(ms(sorted[sorted.count / 2])) ms over \(sorted.count) runs, min \(ms(sorted.first!)) max \(ms(sorted.last!))")
    }

    private func ms(_ d: Duration) -> String {
        let (seconds, attoseconds) = d.components
        let value = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        return String(format: "%.1f", value)
    }
}
