import Foundation
import Swinject

final class DependencyContainer {
    static let shared = DependencyContainer()
    let container = Container()

    private init() {
        registerDependencies()
    }

    private func registerDependencies() {
        container.register(MixRepository.self) { _ in
            MixRepository()
        }.inObjectScope(.container)

        container.register(TagRepository.self) { _ in
            TagRepository()
        }.inObjectScope(.container)

        container.register(SavedViewRepository.self) { _ in
            SavedViewRepository()
        }.inObjectScope(.container)
    }

    func resolve<T>() -> T {
        guard let resolved = container.resolve(T.self) else {
            fatalError("Failed to resolve \(String(describing: T.self))")
        }
        return resolved
    }
}

func resolve<T>() -> T {
    DependencyContainer.shared.resolve()
}
