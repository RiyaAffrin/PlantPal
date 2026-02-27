import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 12)

                Text("PlantPal")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.86, green: 0.97, blue: 0.84))
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Text("Tell us about your plant and we'll take care of the rest.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Spacer()

                Image(systemName: "leaf.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(Color(red: 0.35, green: 0.62, blue: 0.32))
                    .padding(.vertical, 24)

                Spacer()

                NavigationLink("Start setup", destination: Scenario1FlowView(selectedTab: .constant(1)))
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.72, green: 0.95, blue: 0.63))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("You can customize later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }
}

#Preview {
    HomeView()
}
