import Foundation

enum DevelopmentScenario: String {
    case blankCanvas = "blank-canvas"
    case fakePin = "fake-pin"
    case multiPin = "multi-pin"
    case aiRefine = "ai-refine"

    static var current: Self {
#if DEBUG
        let process = ProcessInfo.processInfo
        if let value = process.environment["TUBER_SCENARIO"], let scenario = Self(rawValue: value) {
            return scenario
        }
        if let index = process.arguments.firstIndex(of: "--scenario"),
           process.arguments.indices.contains(index + 1),
           let scenario = Self(rawValue: process.arguments[index + 1]) {
            return scenario
        }
#endif
        return .blankCanvas
    }

    var displayName: String { rawValue }

    var conversationLayers: NoteConversationLayers {
        let noteID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let tutorLayerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let researchLayerID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let draftLayerID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

        switch self {
        case .blankCanvas, .aiRefine:
            return NoteConversationLayers(
                noteID: noteID,
                layers: [
                    ConversationLayer(
                        id: tutorLayerID,
                        name: "Tutor",
                        symbolName: "sparkles",
                        conversations: []
                    )
                ]
            )
        case .fakePin:
            return NoteConversationLayers(
                noteID: noteID,
                layers: [
                    ConversationLayer(
                        id: tutorLayerID,
                        name: "Tutor",
                        symbolName: "sparkles",
                        conversations: [
                            Pin(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, pagePosition: CGPoint(x: 0.62, y: 0.34), title: "Key idea", detail: "This conversation belongs to the Tutor layer.")
                        ]
                    )
                ]
            )
        case .multiPin:
            return NoteConversationLayers(
                noteID: noteID,
                layers: [
                    ConversationLayer(
                        id: tutorLayerID,
                        name: "Tutor",
                        symbolName: "sparkles",
                        conversations: [
                            Pin(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, pagePosition: CGPoint(x: 0.24, y: 0.22), title: "Start here", detail: "The first known spatial target."),
                            Pin(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, pagePosition: CGPoint(x: 0.69, y: 0.49), title: "Check this", detail: "The second known spatial target.")
                        ]
                    ),
                    ConversationLayer(
                        id: researchLayerID,
                        name: "Research",
                        symbolName: "books.vertical.fill",
                        conversations: [
                            Pin(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, pagePosition: CGPoint(x: 0.40, y: 0.76), title: "Related source", detail: "This conversation is isolated on the Research layer.")
                        ]
                    ),
                    ConversationLayer(
                        id: draftLayerID,
                        name: "Draft",
                        symbolName: "bubble.left.and.bubble.right.fill",
                        conversations: []
                    )
                ]
            )
        }
    }

    var penFixture: PenFixture? {
#if DEBUG
        if self == .aiRefine { return .aiRefinementSample }
        return PenFixtureStore.loadRequestedFixture()
#else
        return nil
#endif
    }

    var initialRefinementSelection: CGRect? {
        guard self == .aiRefine else { return nil }
        return CGRect(x: 0.20, y: 0.28, width: 0.50, height: 0.34)
    }
}

#if DEBUG
private extension PenFixture {
    static let aiRefinementSample = PenFixture(
        name: "ai-refinement-sample",
        description: "Deterministic rough sketch for AI refinement verification",
        events: [
            .init(x: 0.28, y: 0.40, time: 0.00, phase: .began, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.40, y: 0.31, time: 0.05, phase: .moved, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.53, y: 0.41, time: 0.10, phase: .moved, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.40, y: 0.51, time: 0.15, phase: .moved, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.28, y: 0.40, time: 0.20, phase: .ended, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.40, y: 0.51, time: 0.00, phase: .began, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.40, y: 0.61, time: 0.08, phase: .ended, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.34, y: 0.61, time: 0.00, phase: .began, pressure: 1, altitude: nil, azimuth: nil),
            .init(x: 0.46, y: 0.61, time: 0.08, phase: .ended, pressure: 1, altitude: nil, azimuth: nil)
        ],
        requestID: nil,
        recordedAt: nil
    )
}
#endif
