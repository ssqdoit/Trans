import SwiftUI

/// Navigation state is kept separate from the feature/application state so a
/// tab click does not publish a change through every AppModel subscriber.
final class NavigationStore: ObservableObject {
    @Published var selectedSection: AppSection = .translate
}
