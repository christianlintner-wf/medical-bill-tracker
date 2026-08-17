import SwiftUI
import RechnungenKit

struct ProviderPickerView: View {
    @Bindable var viewModel: ProviderPickerViewModel
    @Binding var selectedProviderID: UUID?

    @State private var newProviderName = ""

    var body: some View {
        Form {
            Section("Vorhandene Ärzte") {
                ForEach(viewModel.providers) { provider in
                    Button {
                        selectedProviderID = provider.id
                    } label: {
                        HStack {
                            Text(provider.name)
                            if selectedProviderID == provider.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section("Neuen Arzt anlegen") {
                TextField("Name", text: $newProviderName)
                Button("Anlegen") {
                    Task {
                        if let provider = await viewModel.createProvider(name: newProviderName) {
                            selectedProviderID = provider.id
                            newProviderName = ""
                        }
                    }
                }
                .disabled(newProviderName.isEmpty)
            }
        }
        .task { await viewModel.load() }
    }
}
