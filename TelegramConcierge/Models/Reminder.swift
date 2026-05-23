import Foundation

// MARK: - Recurrence Type

enum RecurrenceType: Codable, Equatable {
    case daily
    case weekly
    case monthly
    case custom(minutes: Int)
    /// Specific days of the week. Days use ISO 8601 numbering: 1=Monday … 7=Sunday.
    case daysOfWeek(days: Set<Int>)

    // Human-readable description
    var description: String {
        switch self {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .custom(let minutes):
            if minutes >= 60 && minutes % 60 == 0 {
                let hours = minutes / 60
                return "every \(hours) hour\(hours > 1 ? "s" : "")"
            } else {
                return "every \(minutes) minute\(minutes > 1 ? "s" : "")"
            }
        case .daysOfWeek(let days):
            let sorted = days.sorted()
            if sorted == [1,2,3,4,5] { return "weekdays" }
            if sorted == [6,7] { return "weekends" }
            let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return "every " + sorted.map { names[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Calculate the next trigger date based on recurrence type
    func nextTriggerDate(from date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .custom(let minutes):
            return calendar.date(byAdding: .minute, value: minutes, to: date) ?? date
        case .daysOfWeek(let isoDays):
            // Convert ISO days (1=Mon..7=Sun) to Apple weekday (1=Sun..7=Sat)
            let appleDays = Set(isoDays.map { ($0 % 7) + 1 })
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                let weekday = calendar.component(.weekday, from: candidate)
                if appleDays.contains(weekday) {
                    return candidate
                }
            }
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
    }

    /// Snap an initial trigger date to a valid occurrence for this recurrence.
    /// For `.daysOfWeek`, advances to the nearest selected weekday on or after
    /// `date` (preserving the time of day); other cases return `date` unchanged.
    func alignedInitialTriggerDate(from date: Date) -> Date {
        guard case .daysOfWeek(let isoDays) = self else { return date }
        let calendar = Calendar.current
        let appleDays = Set(isoDays.map { ($0 % 7) + 1 })
        for offset in 0...6 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if appleDays.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }
        return date
    }
}

// MARK: - Reminder Model

struct Reminder: Codable, Identifiable {
    let id: UUID
    var triggerDate: Date
    let prompt: String          // Detailed instructions for future Gemini
    let createdAt: Date
    var triggered: Bool
    let recurrence: RecurrenceType?
    
    init(triggerDate: Date, prompt: String, recurrence: RecurrenceType? = nil) {
        self.id = UUID()
        self.triggerDate = triggerDate
        self.prompt = prompt
        self.createdAt = Date()
        self.triggered = false
        self.recurrence = recurrence
    }
}
