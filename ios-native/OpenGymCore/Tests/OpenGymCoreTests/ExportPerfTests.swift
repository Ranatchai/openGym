import Foundation
import OpenGymCore
import XCTest

final class ExportPerfTests: XCTestCase {
    func testExercisesDecodeWithinBudget() throws {
        let data = try Data(contentsOf: ExportFiles.exercises)
        var samples: [Duration] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            let catalogue = try JSONDecoder().decode([Exercise].self, from: data)
            samples.append(ContinuousClock.now - start)
            XCTAssertEqual(catalogue.count, 1324)
        }
        let ms = samples.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1e3 }
        print("ExportPerfTests: exercises.json \(data.count) bytes, decode ms \(ms.map { String(format: "%.2f", $0) }.joined(separator: " "))")
        #if !DEBUG
        XCTAssertLessThan(ms.max()!, 50)
        #endif
    }
}
