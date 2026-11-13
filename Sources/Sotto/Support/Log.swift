import os

enum Log {
    static let subsystem = "com.furkan.sotto"
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Per-step timing, visible in Instruments under Points of Interest.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
