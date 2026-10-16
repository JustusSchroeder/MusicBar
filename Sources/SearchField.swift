import AppKit
import SwiftUI

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(string: text)
        field.placeholderString = "Search songs"
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchAction(_:))
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func searchAction(_ sender: NSSearchField) {
            let value = sender.stringValue
            text.wrappedValue = value
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            onSubmit()
        }
    }
}
