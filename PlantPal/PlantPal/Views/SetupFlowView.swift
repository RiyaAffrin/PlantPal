import SwiftUI

struct SetupFlowView: View {
    @State private var plantName = ""
    @State private var plantType = ""
    @State private var location = ""
    @State private var wantsExplanations = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Plant") {
                    TextField("Plant name", text: $plantName)
                    TextField("Plant type", text: $plantType)
                    TextField("Location (e.g. bright window)", text: $location)
                }

                Section("AI Support") {
                    Toggle("Show explanations", isOn: $wantsExplanations)
                }

                Section("Preview") {
                    CalendarPreviewView()
                }
            }
            .navigationTitle("PlantPal Setup")
            .toolbar {
                Button("Generate Plan") {
                    // Placeholder for schedule generation.
                }
            }
        }
    }
}

#Preview {
    SetupFlowView()
}
