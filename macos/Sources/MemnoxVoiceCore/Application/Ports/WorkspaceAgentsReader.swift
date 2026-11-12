import Foundation

/// The workspace's agents for the person signed in: the jobs, the work they answer for and the handoffs that wait on
/// them. The workspace decides who sees what; this only carries what it says, and an answer to a handoff is unsigned.
public protocol WorkspaceAgentsReader: AnyObject, Sendable {
    func agentProfiles(in workspace: String, token: String) async throws -> [CloudProfileView]
    func myAgentWork(in workspace: String, token: String) async throws -> CloudMyWork
    func answerHandoff(_ handoff: String, in workspace: String, accept: Bool, token: String) async throws
    /// Which issue each of these sessions concerns, as the workspace matched it.
    func workCorrelations(in workspace: String, sessions: [String], token: String) async throws -> [WorkCorrelation]
}
