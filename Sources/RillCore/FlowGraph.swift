import Foundation

/// Where power comes from and where it goes, for the Sankey-style flow view:
/// sources on the left, consumers on the right, one link per path.
public struct FlowGraph: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case adapter, battery, mac }

    public struct Node: Equatable, Sendable {
        public var role: Role
        public var watts: Double
    }

    public struct Link: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var watts: Double
    }

    public var sources: [Node]
    public var sinks: [Node]
    public var links: [Link]

    /// Below this a path counts as idle.
    public static let threshold = 0.3

    public init(sources: [Node], sinks: [Node], links: [Link]) {
        self.sources = sources
        self.sinks = sinks
        self.links = links
    }

    public init(_ s: PowerSnapshot) {
        let system = max(0, s.systemWatts)
        let charge = max(0, s.batteryWatts)
        let discharge = max(0, -s.batteryWatts)
        if s.externalConnected {
            if discharge > Self.threshold {
                // The adapter can't keep up; the battery tops up the Mac.
                let fromAdapter = max(0, system - discharge)
                self.init(sources: [Node(role: .adapter, watts: s.inputWatts), Node(role: .battery, watts: discharge)],
                          sinks: [Node(role: .mac, watts: system)],
                          links: [Link(from: 0, to: 0, watts: fromAdapter), Link(from: 1, to: 0, watts: discharge)])
            } else {
                // Battery on top, Mac below, as in macOS's own battery views.
                // An idle battery (full, or held) carries no flow, so it
                // leaves the graph; a tile for it would steal height from the
                // ribbon and shrink the charger tile with it (2026-11-05).
                let adapter = [Node(role: .adapter, watts: s.inputWatts)]
                if charge > Self.threshold {
                    self.init(sources: adapter,
                              sinks: [Node(role: .battery, watts: charge), Node(role: .mac, watts: system)],
                              links: [Link(from: 0, to: 0, watts: charge), Link(from: 0, to: 1, watts: system)])
                } else {
                    self.init(sources: adapter, sinks: [Node(role: .mac, watts: system)],
                              links: [Link(from: 0, to: 0, watts: system)])
                }
            }
        } else {
            self.init(sources: [Node(role: .battery, watts: discharge)],
                      sinks: [Node(role: .mac, watts: system)],
                      links: [Link(from: 0, to: 0, watts: system)])
        }
    }
}
