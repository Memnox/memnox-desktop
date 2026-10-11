/// Which part of the side panel is in view: everything, or one section alone so a long history cannot bury it.
enum SideFilter: CaseIterable, Hashable {
    case all
    case needsYou
    case working
    case history

    var title: String {
        switch self {
        case .all: "All"
        case .needsYou: "Needs you"
        case .working: "Working"
        case .history: "History"
        }
    }

    /// Whether a section shows under this filter, so All keeps every section and the rest keep only their own.
    func shows(_ section: SideFilter) -> Bool { self == .all || self == section }
}
