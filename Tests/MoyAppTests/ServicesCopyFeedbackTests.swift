import Foundation
@testable import MoyApp
import MoyKit
import Testing

@Suite("Services copy feedback")
struct ServicesCopyFeedbackTests {
    @Test
    func `success feedback belongs only to the copied item and service`() throws {
        let identifier = try ServiceIdentifier("worker")
        let other = try ServiceIdentifier("other")
        let success = CopyToast(id: UUID(), identifier: identifier, item: "PID", succeeded: true)
        #expect(success.showsSuccess(for: identifier, item: "PID"))
        #expect(!success.showsSuccess(for: identifier, item: "Label"))
        #expect(!success.showsSuccess(for: other, item: "PID"))
        let failure = CopyToast(id: UUID(), identifier: identifier, item: "PID", succeeded: false)
        #expect(!failure.showsSuccess(for: identifier, item: "PID"))
    }

    @Test(arguments: [true, false])
    func `feedback reflects clipboard result and expires after one and a half seconds`(succeeded: Bool) async throws {
        let requests = CopyRequests(succeeded: succeeded)
        let reducer = makeReducer(requests)
        let identifier = try ServiceIdentifier("worker")
        var state = ServicesState()
        let copy = reducer.reduce(
            into: &state,
            action: .copyFeedback(.copyValue("1952", item: "PID", identifier: identifier)),
        )
        #expect(state.copyToast == nil)
        let result = try #require(await copy.executeForTesting())
        let dismiss = reducer.reduce(into: &state, action: result)
        let toast = try #require(state.copyToast)
        #expect(toast.item == "PID")
        #expect(toast.identifier == identifier)
        #expect(toast.succeeded == succeeded)
        #expect(await requests.values == ["1952"])
        let expiration = try #require(await dismiss.executeForTesting())
        #expect(await requests.duration == .milliseconds(1500))
        _ = reducer.reduce(into: &state, action: expiration)
        #expect(state.copyToast == nil)
    }

    @Test
    func `new copies replace feedback and stale results cannot dismiss it`() async throws {
        let requests = CopyRequests(succeeded: true)
        let reducer = makeReducer(requests)
        let identifier = try ServiceIdentifier("worker")
        var state = ServicesState()
        let first = reducer.reduce(
            into: &state,
            action: .copyFeedback(.copyValue("42", item: "PID", identifier: identifier)),
        )
        let firstResult = try #require(await first.executeForTesting())
        let firstTimer = reducer.reduce(into: &state, action: firstResult)
        let oldID = try #require(state.copyToast?.id)

        let second = reducer.reduce(
            into: &state,
            action: .copyFeedback(.copyValue("43", item: "PID", identifier: identifier)),
        )
        #expect(state.copyToast == nil)
        _ = reducer.reduce(into: &state, action: firstResult)
        #expect(state.copyToast == nil)
        let secondResult = try #require(await second.executeForTesting())
        _ = reducer.reduce(into: &state, action: secondResult)
        #expect(state.copyToast?.id != oldID)
        let newest = state.copyToast
        let staleExpiration = try #require(await firstTimer.executeForTesting())
        _ = reducer.reduce(into: &state, action: staleExpiration)
        #expect(state.copyToast == newest)
    }

    @Test
    func `changing services or closing the detail clears pending feedback`() async throws {
        let reducer = makeReducer(CopyRequests(succeeded: true))
        let identifier = try ServiceIdentifier("worker")
        var state = ServicesState()
        state.selectedIdentifier = identifier
        let pending = reducer.reduce(
            into: &state,
            action: .copyFeedback(.copyValue("42", item: "PID", identifier: identifier)),
        )
        _ = reducer.reduce(into: &state, action: .selectService(nil))
        let result = try #require(await pending.executeForTesting())
        _ = reducer.reduce(into: &state, action: result)
        #expect(state.copyToast == nil)

        let next = reducer.reduce(into: &state, action: .copyFeedback(.copyValue("/tmp/log", item: "StandardOutPath",
                                                                                 identifier: identifier)))
        let nextResult = try #require(await next.executeForTesting())
        _ = reducer.reduce(into: &state, action: nextResult)
        #expect(state.copyToast != nil)
        _ = reducer.reduce(into: &state, action: .copyFeedback(.clearCopyFeedback))
        #expect(state.copyToast == nil)
        #expect(state.copyRequestID == nil)
    }

    private func makeReducer(_ requests: CopyRequests) -> ServicesReducer {
        ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(),
            clipboardClient: ClipboardClient(copy: { await requests.copy($0) }),
            sleepForCopyToast: { await requests.recordDelay($0) },
        ))
    }
}

private actor CopyRequests {
    let succeeded: Bool
    var values: [String] = []
    var duration: Duration?

    init(succeeded: Bool) {
        self.succeeded = succeeded
    }

    func copy(_ value: String) -> Bool {
        values.append(value)
        return succeeded
    }

    func recordDelay(_ duration: Duration) {
        self.duration = duration
    }
}
