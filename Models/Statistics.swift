import Foundation

struct DayStatistics: Identifiable {
    let id: String // dayKey
    let dayKey: String
    let count: Int
    
    init(dayKey: String, count: Int) {
        self.id = dayKey
        self.dayKey = dayKey
        self.count = count
    }
}
