import ManagedSettings

final class FocusActions: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if #available(iOS 26.5, *) { completionHandler(.openParentalControlsApp) }
        else { completionHandler(.close) }
    }
}
