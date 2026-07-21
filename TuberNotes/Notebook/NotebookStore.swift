import Combine
import Foundation
import PDFKit
import UIKit

enum PDFNotebookImportError: LocalizedError {
    case empty
    case unreadable

    var errorDescription: String? {
        switch self {
        case .empty:
            "The selected PDF does not contain any pages."
        case .unreadable:
            "The selected PDF could not be read."
        }
    }
}

/// Local, file-backed store for notebooks. One JSON file per notebook in
/// `Documents/Notebooks/<uuid>.json`. Mirrors the on-disk conventions used by
/// `PenFixtureStore`, but lives in the product (non-DEBUG) surface.
@MainActor
final class NotebookStore: ObservableObject {
    static let shared = NotebookStore()

    @Published private(set) var notebooks: [Notebook] = []

    private let directoryName = "Notebooks"

    init() {
        reload()
#if TEXTBOOK_CITATION_DEMO
        bootstrapTextbookCitationDemoIfNeeded()
#endif
    }

    private var directory: URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func knowledgeCorpusURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).knowledge.json")
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        notebooks = urls
            .filter {
                $0.pathExtension == "json"
                    && !$0.lastPathComponent.hasSuffix(".knowledge.json")
            }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? Self.decoder.decode(Notebook.self, from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func notebook(id: UUID) -> Notebook? {
        if let inMemory = notebooks.first(where: { $0.id == id }) { return inMemory }
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? Self.decoder.decode(Notebook.self, from: data)
    }

    /// Returns the persisted corpus for one explicitly selected imported textbook.
    /// `nil` means that notebook has no imported corpus sidecar; malformed data is returned
    /// so the Knowledge resolver can reject it rather than silently using a fixture.
    func knowledgeCorpusData(forImportedTextbook id: UUID) throws -> Data? {
        let corpusURL = knowledgeCorpusURL(for: id)
        guard FileManager.default.fileExists(atPath: corpusURL.path) else { return nil }
        return try Data(contentsOf: corpusURL)
    }

    @discardableResult
    func createNotebook(title: String, cover: NotebookCover, template: PageTemplate = .linedMedium) -> Notebook {
        let notebook = Notebook(title: title, cover: cover, pages: [NotebookPage(template: template)])
        save(notebook)
        return notebook
    }

    func save(_ notebook: Notebook) {
        var copy = notebook
        copy.updatedAt = Date()

        if let data = try? Self.encoder.encode(copy) {
            try? data.write(to: url(for: copy.id), options: .atomic)
        }

        if let idx = notebooks.firstIndex(where: { $0.id == copy.id }) {
            notebooks[idx] = copy
        } else {
            notebooks.insert(copy, at: 0)
        }
        notebooks.sort { $0.updatedAt > $1.updatedAt }
    }

    func rename(_ notebook: Notebook, to title: String) {
        var copy = notebook
        copy.title = title
        save(copy)
    }

    @discardableResult
    func importSPUD(from sourceURL: URL) throws -> Notebook {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        let archived = try TuberNoteArchiveCodec.decode(data).notebook
        let imported = Notebook(
            id: UUID(),
            title: archived.title,
            cover: archived.cover,
            pages: archived.pages,
            agenticLayers: archived.agenticLayers,
            createdAt: archived.createdAt,
            updatedAt: Date(),
            settings: archived.settings
        )
        save(imported)
        return imported
    }

    @discardableResult
    func importPDF(from sourceURL: URL) throws -> Notebook {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: sourceURL), !document.isLocked else {
            throw PDFNotebookImportError.unreadable
        }
        guard document.pageCount > 0 else {
            throw PDFNotebookImportError.empty
        }

        let sourceTitle = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notebookID = UUID()
        let notebookTitle = sourceTitle.isEmpty ? "Imported PDF" : sourceTitle
        let pixelSize = CGSize(
            width: NotebookPageLayout.size.width * 2,
            height: NotebookPageLayout.size.height * 2
        )
        var pageTexts: [String?] = []
        let pages = try (0 ..< document.pageCount).map { pageIndex in
            guard let pdfPage = document.page(at: pageIndex),
                  let imageData = Self.rasterizedPageData(pdfPage, pixelSize: pixelSize) else {
                throw PDFNotebookImportError.unreadable
            }
            pageTexts.append(pdfPage.string)
            return NotebookPage(
                template: .plain,
                images: [PlacedImage(
                    imageData: imageData,
                    rect: CGRect(x: 0, y: 0, width: 1, height: 1)
                )]
            )
        }

        let notebook = Notebook(
            id: notebookID,
            title: notebookTitle,
            cover: .slate,
            pages: pages,
            settings: NotebookSettings(showsPageLock: true)
        )
        let corpus = OfflineKnowledgeCorpus.pages(
            documentID: notebookID,
            documentTitle: notebookTitle,
            pageTexts: pageTexts
        )
        let corpusData = try JSONEncoder().encode(corpus)
        try corpusData.write(to: knowledgeCorpusURL(for: notebookID), options: .atomic)
        save(notebook)
        return notebook
    }

    private static func rasterizedPageData(_ page: PDFPage, pixelSize: CGSize) -> Data? {
        let thumbnail = page.thumbnail(of: pixelSize, for: .mediaBox)
        guard thumbnail.size.width > 0, thumbnail.size.height > 0 else { return nil }

        let scale = min(
            pixelSize.width / thumbnail.size.width,
            pixelSize.height / thumbnail.size.height
        )
        let fittedSize = CGSize(
            width: thumbnail.size.width * scale,
            height: thumbnail.size.height * scale
        )
        let fittedRect = CGRect(
            x: (pixelSize.width - fittedSize.width) / 2,
            y: (pixelSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            thumbnail.draw(in: fittedRect)
        }.pngData()
    }

#if TEXTBOOK_CITATION_DEMO
    private var textbookCitationDemoMarkerURL: URL {
        directory.appendingPathComponent(".textbook-citation-demo-v3")
    }

    /// A demo build owns a deterministic two-notebook library. It seeds once so
    /// rehearsal edits survive relaunches; only the explicit Settings reset
    /// reconstructs the state after that.
    private func bootstrapTextbookCitationDemoIfNeeded() {
        guard !FileManager.default.fileExists(atPath: textbookCitationDemoMarkerURL.path) else {
            return
        }

        do {
            try resetTextbookCitationDemo()
        } catch {
            NSLog("Textbook citation demo seed failed: %@", error.localizedDescription)
            reload()
        }
    }

    @discardableResult
    func resetTextbookCitationDemo() throws -> Notebook {
        guard let textbookURL = Bundle.main.url(
            forResource: "OpenStax Organic Chemistry Ch 11 Demo",
            withExtension: "pdf"
        ) else {
            throw PDFNotebookImportError.unreadable
        }
        guard let worksheetImageData = Self.textbookCitationWorksheetImageData() else {
            throw PDFNotebookImportError.unreadable
        }

        let storedFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for storedFile in storedFiles where
            storedFile.pathExtension == "json"
                || storedFile.lastPathComponent.hasPrefix(".textbook-citation-demo-v")
        {
            try FileManager.default.removeItem(at: storedFile)
        }
        notebooks.removeAll()

        _ = try importPDF(from: textbookURL)
        let worksheet = Notebook(
            title: "SN1 Mechanism Worksheet",
            cover: .indigo,
            pages: [NotebookPage(
                template: .plain,
                images: [PlacedImage(
                    imageData: worksheetImageData,
                    rect: CGRect(x: 0, y: 0, width: 1, height: 1)
                )]
            )]
        )
        save(worksheet)
        try Data("v3\n".utf8).write(to: textbookCitationDemoMarkerURL, options: .atomic)
        return worksheet
    }

    private static func textbookCitationWorksheetImageData() -> Data? {
        let size = CGSize(width: NotebookPageLayout.size.width * 2, height: NotebookPageLayout.size.height * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.99, green: 0.98, blue: 0.93, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let ink = UIColor(red: 0.08, green: 0.18, blue: 0.42, alpha: 1)
            let red = UIColor(red: 0.72, green: 0.12, blue: 0.12, alpha: 1)
            let marker = UIFont(name: "MarkerFelt-Wide", size: 54) ?? .systemFont(ofSize: 54)
            let smallMarker = UIFont(name: "MarkerFelt-Thin", size: 43) ?? .systemFont(ofSize: 43)
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: marker, .foregroundColor: ink]
            let bodyAttributes: [NSAttributedString.Key: Any] = [.font: smallMarker, .foregroundColor: ink]
            let errorAttributes: [NSAttributedString.Key: Any] = [.font: marker, .foregroundColor: red]

            NSString(string: "Substitution mechanism check").draw(
                at: CGPoint(x: 105, y: 115),
                withAttributes: titleAttributes
            )
            NSString(string: "(S)-2-bromobutane  +  OH⁻").draw(
                at: CGPoint(x: 115, y: 285),
                withAttributes: bodyAttributes
            )
            NSString(string: "SN1").draw(at: CGPoint(x: 660, y: 390), withAttributes: errorAttributes)
            NSString(string: "CH₃—C⁺H—CH₂CH₃").draw(
                at: CGPoint(x: 260, y: 515),
                withAttributes: bodyAttributes
            )
            NSString(string: "OH attacks from the same side").draw(
                at: CGPoint(x: 170, y: 680),
                withAttributes: bodyAttributes
            )
            NSString(string: "→ retained (S)-2-butanol").draw(
                at: CGPoint(x: 235, y: 825),
                withAttributes: errorAttributes
            )
            NSString(string: "Should this SN1 reaction give retention, inversion,\nor a racemic mixture? Explain why.").draw(
                with: CGRect(x: 145, y: 1080, width: size.width - 290, height: 180),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: bodyAttributes,
                context: nil
            )
        }
        return image.pngData()
    }
#endif

    func delete(_ notebook: Notebook) {
        try? FileManager.default.removeItem(at: url(for: notebook.id))
        try? FileManager.default.removeItem(at: knowledgeCorpusURL(for: notebook.id))
        notebooks.removeAll { $0.id == notebook.id }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
