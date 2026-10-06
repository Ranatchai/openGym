import Foundation
import Capacitor
import UIKit

/**
 * Keeps the native chrome in the app's theme rather than the phone's (Aura Matrix, src/aura.css).
 * The status bar and the keyboard otherwise follow the system appearance: a phone in dark mode
 * drew white status-bar text over the pale Aura desk, where it could not be read.
 *
 * `mode` is the theme setting itself. 'system' hands both back to the phone — forcing a style
 * there would also pin the web view's prefers-color-scheme, and the app's System theme could
 * then never follow the phone again.
 *
 * Usage from JS (lib/mobile.js setNativeAppearance); registered in MainViewController:
 *   import { registerPlugin } from '@capacitor/core';
 *   await registerPlugin('Appearance').set({ mode: 'light' });
 */
@objc(AppearancePlugin)
public class AppearancePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AppearancePlugin"
    public let jsName = "Appearance"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise)
    ]

    @objc func set(_ call: CAPPluginCall) {
        let mode = call.getString("mode") ?? "system"
        let bridge = self.bridge
        DispatchQueue.main.async {
            switch mode {
            case "dark":
                bridge?.statusBarStyle = .lightContent
                bridge?.viewController?.view.window?.overrideUserInterfaceStyle = .dark
            case "light":
                bridge?.statusBarStyle = .darkContent
                bridge?.viewController?.view.window?.overrideUserInterfaceStyle = .light
            default:
                bridge?.statusBarStyle = .default
                bridge?.viewController?.view.window?.overrideUserInterfaceStyle = .unspecified
            }
            call.resolve()
        }
    }
}
