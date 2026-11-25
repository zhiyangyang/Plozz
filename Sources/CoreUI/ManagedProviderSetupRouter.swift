import CoreModels
import Observation
import SwiftUI

@MainActor
@Observable
public final class ManagedProviderSetupRouter {
    public var addressAccount: Account?
    public var reauthenticationAccount: Account?
    public init() {}
}

extension EnvironmentValues {
    @Entry public var managedProviderSetupRouter: ManagedProviderSetupRouter?
}
