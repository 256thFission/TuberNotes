import SwiftUI

struct RootView: View {
    let scenario: DevelopmentScenario
#if DEBUG
    @StateObject private var agentSession = AgentInteractionSession()
#endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
#if DEBUG
                AgentRequestBanner(session: agentSession)
#endif
                SpatialCanvasView(
                    conversationLayers: scenario.conversationLayers,
                    penFixture: scenario.penFixture,
                    refinementClient: refinementClient,
                    initialRefinementSelection: scenario.initialRefinementSelection
                )
#if DEBUG
                    .environmentObject(agentSession)
#endif
            }
            .navigationTitle("TuberNotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(scenario.displayName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("scenario-label")
                }
            }
        }
        .onAppear {
            print("TuberNotes scenario=\(scenario.rawValue) layers=\(scenario.conversationLayers.layers.count)")
#if DEBUG
            agentSession.reload()
#endif
        }
    }

    private var refinementClient: any DrawingRefinementClient {
#if DEBUG
        if scenario == .aiRefine {
            return PreviewDrawingRefinementClient()
        }
#endif
        return BackendDrawingRefinementClient()
    }
}
