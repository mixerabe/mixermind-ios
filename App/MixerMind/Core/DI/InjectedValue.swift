import Foundation

@propertyWrapper
struct InjectedValue<T> {
    private let dependency: T

    var wrappedValue: T { return dependency }

    init() {
        self.dependency = DependencyContainer.shared.resolve()
    }
}
