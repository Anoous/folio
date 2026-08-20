enum QuickSavePhase: Equatable {
    case idle
    case editing
    case saving
    case succeeded(DemoCaptureSuccess)
    case failed(DemoCaptureFailure)

    var isExpanded: Bool {
        self != .idle
    }
}
