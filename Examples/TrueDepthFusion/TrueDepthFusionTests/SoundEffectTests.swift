// SoundEffectTests.swift

import Testing
import StandardCyborgCapture

@Suite("SoundEffect")
struct SoundEffectTests {

    @Test("Init with missing resource does not crash")
    func initMissingResource() {
        // SoundEffect gracefully handles missing bundle resources.
        // Sound ID stays 0 and play() is a no-op.
        let effect = SoundEffect(named: "nonexistent", type: "wav")
        // If we reach here the init did not crash or throw.
        effect.play()  // must be safe to call even with sound ID 0
    }

    @Test("Init with empty name does not crash")
    func initEmptyName() {
        let effect = SoundEffect(named: "", type: "")
        effect.play()
    }
}
