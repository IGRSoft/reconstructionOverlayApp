//
//  InitialViewController.swift

import Foundation
import UIKit

/*
 Storyboard segue map
 ──────────────────────────────────────────────
 Main.storyboard root
   └─ InitialViewController
       └─ Scan tap → branch on UserDefaults["dump_raw_frames_to_bply"]
           ├─ false → ScanningViewController       (default scanning)
           └─ true  → BPLYScanningViewController   (raw-frame capture)
 ──────────────────────────────────────────────
*/

/// The welcome screen presented at app launch.
///
/// `InitialViewController` is the root view controller in `Main.storyboard`. It shows a
/// brief welcome message and provides a single "Scan" button that transitions the user
/// into the scanning flow.
///
/// ## Segue routing
///
/// The scan button branches on the `UserDefaults` key `"dump_raw_frames_to_bply"`:
///
/// | Default value | `false` |
/// | Segue (false) | `"ScanningViewController"` — normal real-time 3D reconstruction |
/// | Segue (true)  | `"BPLYScanningViewController"` — raw-frame capture for debugging |
///
/// ## Enabling raw-frame mode
///
/// Raw-frame mode records individual depth + color frames to BPLY files instead of
/// performing live reconstruction. It is intended for offline debugging and dataset
/// capture, not production use.
///
/// To enable it during development, set the flag in a scheme's launch argument or
/// programmatically before the view appears:
///
/// ```swift
/// // In Xcode scheme: add launch argument "-dump_raw_frames_to_bply YES"
/// // Or programmatically:
/// UserDefaults.standard.set(true, forKey: "dump_raw_frames_to_bply")
/// ```
///
/// Reset to the default by removing the key or setting it to `false`.
class InitialViewController: UIViewController {

    /// Injected by RootView representable; forwarded to scanning VCs via prepare(for:sender:)
    var scanStore: ScanStore?

    @IBOutlet weak var introLabel: UILabel!
    
    override func viewDidLoad() {
        introLabel.text = "Welcome to Overlay Vision on  " + UIDevice.current.localizedModel
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            view.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        }
    }
    
    @IBAction private func scan(_ sender: UIButton?) {
        let scanToBPLY = UserDefaults.standard.bool(forKey: "dump_raw_frames_to_bply", defaultValue: false)
        let segueIdentifier = scanToBPLY ? "BPLYScanningViewController" : "ScanningViewController"
        performSegue(withIdentifier: segueIdentifier, sender: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? ScanningViewController {
            vc.scanStore = scanStore
        } else if let vc = segue.destination as? BPLYScanningViewController {
            vc.scanStore = scanStore
        } else if let nav = segue.destination as? UINavigationController,
                  let vc = nav.viewControllers.first as? ScansViewController {
            vc.scanStore = scanStore
        } else if let vc = segue.destination as? ScansViewController {
            vc.scanStore = scanStore
        }
    }
}

extension UserDefaults {
    
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        if let defaultNumber = object(forKey: key) as? NSNumber {
            return defaultNumber.boolValue
        } else {
            return defaultValue
        }
    }
    
}
