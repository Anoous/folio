enum QuickSavePhase: Equatable {
    case idle
    case editing
    case saving
    case saved

    var isExpanded: Bool {
        self != .idle
    }
}
