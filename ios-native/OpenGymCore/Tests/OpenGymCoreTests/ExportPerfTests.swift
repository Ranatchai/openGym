import Foundation
import OpenGymCore
import XCTest

final class ExportPerfTests: XCTestCase {
    func testExercisesDecodeWithinBudget() throws {
        let data = try Data(contentsOf: ExportFiles.exercises)
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let catalogue = try JSONDecoder().decode([Exercise].self, from: data)
            samples.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e6)
            XCTAssertEqual(catalogue.count, 1324)
        }
        let median = samples.sorted()[samples.count / 2]
        print("ExportPerfTests: exercises.json \(data.count) bytes, decode thread CPU ms \(samples.map { String(format: "%.2f", $0) }.joined(separator: " ")), median \(String(format: "%.2f", median))")
        #if !DEBUG
        XCTAssertLessThan(median, 50)
        #endif
    }
}
