import AppKit

/// The bits Apple never made public: putting a background app's bar on the
/// Touch Bar and an icon in the Control Strip. Pock, MTMR and BetterTouchTool
/// rely on the same calls. Everything is looked up at runtime, so a future
/// macOS that drops them makes the app inert instead of crashing it.
enum SystemTouchBar {
    private typealias SetPresence = @convention(c) (NSString, Bool) -> Void
    private typealias SetCloseBox = @convention(c) (Bool) -> Void

    private static let dfr = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let dfr, let sym = dlsym(dfr, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// Adds `item` to the Control Strip, next to brightness and volume.
    static func addToControlStrip(_ item: NSTouchBarItem) {
        let add = NSSelectorFromString("addSystemTrayItem:")
        if (NSTouchBarItem.self as AnyObject).responds(to: add) {
            _ = (NSTouchBarItem.self as AnyObject).perform(add, with: item)
        }
        symbol("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)?(
            item.identifier.rawValue as NSString, true)
    }

    static func removeFromControlStrip(_ item: NSTouchBarItem) {
        symbol("DFRElementSetControlStripPresenceForIdentifier", as: SetPresence.self)?(
            item.identifier.rawValue as NSString, false)
        let remove = NSSelectorFromString("removeSystemTrayItem:")
        if (NSTouchBarItem.self as AnyObject).responds(to: remove) {
            _ = (NSTouchBarItem.self as AnyObject).perform(remove, with: item)
        }
    }

    /// Shows `bar` over whatever app is frontmost. `fullWidth` hides the
    /// Control Strip (brightness, volume) so the bar gets the whole strip.
    static func present(_ bar: NSTouchBar, trayIdentifier: NSTouchBarItem.Identifier, fullWidth: Bool = false) {
        symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: SetCloseBox.self)?(true)
        if fullWidth, presentWithPlacement(bar, placement: 1, trayIdentifier: trayIdentifier) { return }
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard (NSTouchBar.self as AnyObject).responds(to: sel) else { return }
        _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar, with: trayIdentifier.rawValue as NSString)
    }

    /// The placement variant takes a plain integer, which `perform` can't
    /// pass, so call its implementation directly.
    private static func presentWithPlacement(_ bar: NSTouchBar, placement: Int64,
                                             trayIdentifier: NSTouchBarItem.Identifier) -> Bool {
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString) -> Void
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, sel) else { return false }
        let present = unsafeBitCast(method_getImplementation(method), to: Present.self)
        present(NSTouchBar.self, sel, bar, placement, trayIdentifier.rawValue as NSString)
        return true
    }

    /// Puts the bar away; it stays one tap away via the Control Strip icon.
    static func minimize(_ bar: NSTouchBar) {
        let sel = NSSelectorFromString("minimizeSystemModalTouchBar:")
        if (NSTouchBar.self as AnyObject).responds(to: sel) {
            _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar)
        } else {
            dismiss(bar)
        }
    }

    static func dismiss(_ bar: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if (NSTouchBar.self as AnyObject).responds(to: sel) {
            _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar)
        }
    }

    static var isSupported: Bool {
        (NSTouchBar.self as AnyObject).responds(
            to: NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"))
    }
}
