import Observation

@Observable
public final class ProviderPickerViewModel {
    public private(set) var providers: [Provider] = []
    public var errorMessage: String?

    private let repository: InvoiceRepositoryProtocol

    public init(repository: InvoiceRepositoryProtocol) {
        self.repository = repository
    }

    public func load() async {
        do {
            providers = try await repository.providers()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @discardableResult
    public func createProvider(name: String) async -> Provider? {
        do {
            let provider = try await repository.createProvider(name: name)
            providers.append(provider)
            return provider
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}
