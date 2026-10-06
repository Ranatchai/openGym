import UIKit
import Capacitor

/**
 * The app's root view controller (Main.storyboard). Capacitor 7 registers only the plugins
 * `cap sync` lists from npm packages, so the app's own plugins are registered here.
 */
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(AppearancePlugin())
        bridge?.registerPluginInstance(PrintPlugin())
    }
}
