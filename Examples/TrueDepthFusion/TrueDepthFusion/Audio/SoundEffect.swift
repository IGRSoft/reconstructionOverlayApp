//
//  SoundEffect.swift

#if os(iOS)

import AudioToolbox
import Foundation

final class SoundEffect {
    private var _soundID: SystemSoundID = 0

    init(named name: String, type: String) {
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: type) else { return }
        AudioServicesCreateSystemSoundID(url as CFURL, &_soundID)
    }

    deinit {
        if _soundID != 0 {
            AudioServicesDisposeSystemSoundID(_soundID)
        }
    }

    func play() {
        AudioServicesPlaySystemSound(_soundID)
    }
}

#endif
