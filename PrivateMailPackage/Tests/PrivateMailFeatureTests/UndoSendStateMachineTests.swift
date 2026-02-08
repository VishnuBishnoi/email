import Testing
@testable import PrivateMailFeature

@Suite("UndoSendStateMachine")
struct UndoSendStateMachineTests {

    @Test("start queues message before countdown")
    func startQueues() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 5)

        #expect(machine.phase == .undoWindow(secondsRemaining: 5))
        #expect(machine.sendState == .queued)
        #expect(machine.isDraft == false)
    }

    @Test("undo during window returns to draft")
    func undoReturnsDraft() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 5)
        machine.undo()

        #expect(machine.phase == .draft)
        #expect(machine.sendState == .none)
        #expect(machine.isDraft == true)
    }

    @Test("background pauses countdown until foreground")
    func pauseResume() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 5)

        machine.background()
        machine.tick(seconds: 5)
        #expect(machine.phase == .undoWindow(secondsRemaining: 5))

        machine.foreground()
        machine.tick(seconds: 5)
        #expect(machine.phase == .queuedForSMTP)
    }

    @Test("terminate during undo window stores as draft")
    func terminateAsDraft() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 10)
        machine.terminate()

        #expect(machine.phase == .draft)
        #expect(machine.sendState == .none)
        #expect(machine.isDraft)
    }

    @Test("delay zero bypasses undo and queues for smtp immediately")
    func zeroDelay() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 0)

        #expect(machine.phase == .queuedForSMTP)
        #expect(machine.sendState == .queued)
        #expect(machine.isDraft == false)
    }

    @Test("offline during undo keeps timer running and expires to queued")
    func offlineDuringUndo() {
        var machine = UndoSendStateMachine()
        machine.start(delaySeconds: 3)
        machine.networkBecameOffline()
        machine.tick(seconds: 3)

        #expect(machine.phase == .queuedForSMTP)
    }
}
