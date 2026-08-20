import AppKit

enum TransBrand {
    static let icon: NSImage = {
        guard let url = Bundle.module.url(forResource: "TransIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSApplication.shared.applicationIconImage
        }
        image.isTemplate = false
        image.accessibilityDescription = "Trans"
        return image
    }()
}
