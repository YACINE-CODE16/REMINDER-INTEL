import Foundation
import SwiftData
import SwiftUI

/// A node of the user's organisation tree (Études > Finance…). Unlimited depth, one parent.
@Model
final class Space {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sfSymbol: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
    var parent: Space?
    @Relationship(deleteRule: .cascade, inverse: \Space.parent) var children: [Space] = []
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.space) var tasks: [TaskItem] = []
    @Relationship(deleteRule: .cascade, inverse: \Session.space) var sessions: [Session] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        sfSymbol: String,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = .now,
        parent: Space? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sfSymbol = sfSymbol
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.parent = parent
    }

    var color: Color { Color(hexString: colorHex) }

    /// Names from the root down to this space.
    var pathComponents: [String] {
        var components = [name]
        var current = parent
        while let node = current {
            components.insert(node.name, at: 0)
            current = node.parent
        }
        return components
    }

    /// "Études › Finance", as shown in the UI.
    var displayPath: String { pathComponents.joined(separator: " › ") }

    var sortedChildren: [Space] {
        children.filter { !$0.isArchived }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// This space and all its non-archived descendants.
    var subtree: [Space] {
        [self] + sortedChildren.flatMap(\.subtree)
    }

    /// Tasks of this space and of its descendants.
    var subtreeTasks: [TaskItem] {
        subtree.flatMap(\.tasks)
    }

    /// True if this space is `other` or one of its ancestors.
    func contains(_ other: Space) -> Bool {
        var current: Space? = other
        while let node = current {
            if node.id == id { return true }
            current = node.parent
        }
        return false
    }

    /// Path of `descendant` relative to this space ("Finance" from Études), nil for itself.
    func relativePath(of descendant: Space) -> String? {
        guard descendant.id != id else { return nil }
        let own = pathComponents.count
        return descendant.pathComponents.dropFirst(own).joined(separator: " › ")
    }
}

/// Plain copy of a space for the parser, which runs outside SwiftData.
nonisolated struct SpaceRef: Sendable, Equatable, Identifiable {
    var id: UUID
    var path: [String]

    var name: String { path.last ?? "" }
    /// "Études > Finance", the form given to the model.
    var modelPath: String { path.joined(separator: " > ") }
    var displayPath: String { path.joined(separator: " › ") }
}

extension Space {
    var ref: SpaceRef { SpaceRef(id: id, path: pathComponents) }

    /// Every active space, depth-first in display order.
    static func activeTree(in context: ModelContext) -> [Space] {
        let all = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        return roots(of: all).flatMap(\.subtree)
    }

    static func roots(of all: [Space]) -> [Space] {
        all.filter { $0.parent == nil && !$0.isArchived }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }
}

/// The 8 colours and 12 symbols offered when creating a space.
enum SpaceStyle {
    static let colors = ["#5E5CE6", "#FF9F0A", "#34C759", "#0A84FF", "#FF375F", "#BF5AF2", "#30B0C7", "#AC8E68"]
    static let symbols = [
        "book.fill", "briefcase.fill", "calendar", "globe",
        "figure.run", "house.fill", "chart.line.uptrend.xyaxis", "function",
        "text.bubble.fill", "laptopcomputer", "person.2.fill", "doc.text.fill",
    ]
}

extension Color {
    /// "#5E5CE6" or "5E5CE6"; grey when unreadable.
    nonisolated init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(hex: value)
    }
}
