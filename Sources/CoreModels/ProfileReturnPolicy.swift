import Foundation

public enum ProfileReturnPolicy {
    public static func delay(for profiles: [Profile], automaticallySignIn: Bool) -> TimeInterval? {
        guard !automaticallySignIn else { return nil }
        return profiles.count > 1 ? 300 : nil
    }
}
