// ABOUTME: Short relative age for a note's last edit: now, 12m, 3h, 2d, then the calendar date.
// ABOUTME: Compact enough to sit on the title's baseline.

import Foundation

enum Age {
    static func short(_ date: Date, relativeTo now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86400): return "\(Int(seconds / 86400))d"
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }
}
