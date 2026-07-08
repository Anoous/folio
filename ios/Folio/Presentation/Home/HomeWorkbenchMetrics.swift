import Foundation

struct HomeWorkbenchMetrics: Equatable {
    let processingCount: Int
    let continueReadingCount: Int
    let askableCount: Int

    init(processingCount: Int, continueReadingCount: Int, askableCount: Int) {
        self.processingCount = max(processingCount, 0)
        self.continueReadingCount = max(continueReadingCount, 0)
        self.askableCount = max(askableCount, 0)
    }
}
