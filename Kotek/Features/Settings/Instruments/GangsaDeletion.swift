//
//  GangsaDeletion.swift
//  Kotek
//
//  What deleting a gangsa takes with it, said the same way wherever it can be
//  deleted: the gangsa picker's trash button and Settings → Gangsa.
//

enum GangsaDeletion {
    /// The confirmation's message. Says what is actually removed —
    /// `AppState.deleteInstrument` drops the keys, the photo and the recorded
    /// note clips, here and on the server. The old wording ("its key alignment
    /// and learned voice") predated note clips and the controller.
    static func message(_ name: String?) -> String {
        "\(name ?? "This gangsa") goes from every device, with its key setup, photo and recorded note clips. This cannot be undone."
    }
}
