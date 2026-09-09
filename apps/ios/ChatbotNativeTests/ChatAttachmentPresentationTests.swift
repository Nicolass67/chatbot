import XCTest
@testable import ChatbotNative

final class ChatAttachmentPresentationTests: XCTestCase {
    private func att(
        id: String = "a1",
        filename: String?,
        mime: String?,
        size: Int? = 2_400_000,
        type: String? = nil
    ) -> MessageAttachmentDTO {
        MessageAttachmentDTO(
            id: id,
            filename: filename,
            mimeType: mime,
            sizeBytes: size,
            type: type
        )
    }

    func testDetectsImagesByMimeTypeAndExtension() {
        XCTAssertTrue(ChatAttachmentPresentation.isImage(att(filename: "a.jpg", mime: "image/jpeg")))
        XCTAssertTrue(ChatAttachmentPresentation.isImage(att(filename: "b.heic", mime: nil, type: "image")))
        XCTAssertTrue(ChatAttachmentPresentation.isImage(att(filename: "c.PNG", mime: nil)))
        XCTAssertFalse(ChatAttachmentPresentation.isImage(att(filename: "doc.pdf", mime: "application/pdf")))
        XCTAssertFalse(ChatAttachmentPresentation.isImage(att(filename: "notes.txt", mime: "text/plain")))
    }

    func testNeverShowsRawURLOrPath() {
        let url = att(filename: "https://files.example/secret.png", mime: "image/png")
        XCTAssertEqual(ChatAttachmentPresentation.displayFilename(url), "secret.png")
        XCTAssertFalse(ChatAttachmentPresentation.displayFilename(url).contains("://"))

        let schemeOnly = att(filename: "https://example.com", mime: "application/pdf")
        XCTAssertEqual(ChatAttachmentPresentation.displayFilename(schemeOnly), "Document")

        let unix = att(filename: "/var/mobile/Containers/photo.jpg", mime: "image/jpeg")
        XCTAssertEqual(ChatAttachmentPresentation.displayFilename(unix), "photo.jpg")
        XCTAssertFalse(ChatAttachmentPresentation.displayFilename(unix).hasPrefix("/"))

        let win = att(filename: "D:\\secrets\\file.pdf", mime: "application/pdf")
        XCTAssertFalse(ChatAttachmentPresentation.displayFilename(win).contains("\\"))
        XCTAssertFalse(ChatAttachmentPresentation.displayFilename(win).contains("D:"))
    }

    func testEmptyFilenameFallsBackWithoutPath() {
        let image = att(filename: nil, mime: "image/png")
        XCTAssertEqual(ChatAttachmentPresentation.displayFilename(image), "Image")
        let doc = att(filename: "   ", mime: "application/pdf")
        XCTAssertEqual(ChatAttachmentPresentation.displayFilename(doc), "Document")
    }

    func testPdfSubtitleIsCompact() {
        let pdf = att(filename: "analyse.pdf", mime: "application/pdf", size: 2_400_000)
        XCTAssertEqual(ChatAttachmentPresentation.typeLabel(pdf), "PDF")
        let sub = ChatAttachmentPresentation.subtitle(pdf)
        XCTAssertTrue(sub.hasPrefix("PDF · "))
        XCTAssertFalse(sub.contains("http"))
        XCTAssertFalse(sub.contains("/"))
    }

    func testHidesPlaceholderAndExtractionFromBubble() {
        XCTAssertNil(
            ChatAttachmentPresentation.visibleUserText("📎 Pièce jointe", hasAttachments: true)
        )
        XCTAssertEqual(
            ChatAttachmentPresentation.visibleUserText("📎 Pièce jointe", hasAttachments: false),
            "📎 Pièce jointe"
        )
        XCTAssertNil(
            ChatAttachmentPresentation.visibleUserText(
                "Analyse cette pièce jointe.",
                hasAttachments: true
            )
        )
        let mixed = """
        Voici le fichier

        --- Documents joints (extraction locale) ---
        /var/mobile/file.pdf
        """
        XCTAssertEqual(
            ChatAttachmentPresentation.visibleUserText(mixed, hasAttachments: true),
            "Voici le fichier"
        )
        XCTAssertEqual(
            ChatAttachmentPresentation.visibleUserText("Analyse ce document", hasAttachments: true),
            "Analyse ce document"
        )
        XCTAssertNil(ChatAttachmentPresentation.visibleUserText("   ", hasAttachments: true))
    }

    func testTextOnlyMessageUnchanged() {
        XCTAssertEqual(
            ChatAttachmentPresentation.visibleUserText("Bonjour", hasAttachments: false),
            "Bonjour"
        )
    }

    func testSplitsImagesAndDocuments() {
        let items = [
            att(id: "1", filename: "a.jpg", mime: "image/jpeg"),
            att(id: "2", filename: "b.pdf", mime: "application/pdf"),
            att(id: "3", filename: "c.png", mime: "image/png"),
            att(id: "4", filename: "d.docx", mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
        ]
        let images = items.filter { ChatAttachmentPresentation.isImage($0) }
        let docs = items.filter { !ChatAttachmentPresentation.isImage($0) }
        XCTAssertEqual(images.map(\.id), ["1", "3"])
        XCTAssertEqual(docs.map(\.id), ["2", "4"])
        XCTAssertEqual(ChatAttachmentPresentation.typeLabel(docs[0]), "PDF")
        XCTAssertEqual(ChatAttachmentPresentation.typeLabel(docs[1]), "DOC")
    }
}

final class ChatAttachmentMetricsTests: XCTestCase {
    func testSingleImageIsLargerSquare() {
        XCTAssertEqual(ChatAttachmentMetrics.thumbSide(imageCount: 1), 112)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 1), 1)
        XCTAssertEqual(ChatAttachmentMetrics.gridWidth(imageCount: 1), 112)
        XCTAssertLessThan(ChatAttachmentMetrics.gridWidth(imageCount: 1), 320)
    }

    func testTwoToFourImagesStayCompact() {
        XCTAssertEqual(ChatAttachmentMetrics.thumbSide(imageCount: 2), 88)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 2), 2)
        XCTAssertEqual(ChatAttachmentMetrics.thumbSide(imageCount: 3), 72)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 3), 3)
        XCTAssertEqual(ChatAttachmentMetrics.thumbSide(imageCount: 4), 72)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 4), 2)
        XCTAssertLessThan(ChatAttachmentMetrics.gridWidth(imageCount: 4), 200)
    }

    func testManyImagesUseCompactGridWithoutFullBleed() {
        XCTAssertEqual(ChatAttachmentMetrics.thumbSide(imageCount: 5), 58)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 5), 3)
        XCTAssertEqual(ChatAttachmentMetrics.columns(imageCount: 9), 3)
        XCTAssertLessThan(ChatAttachmentMetrics.gridWidth(imageCount: 8), 200)
        XCTAssertEqual(
            ChatAttachmentMetrics.gridWidth(imageCount: 12),
            ChatAttachmentMetrics.gridWidth(imageCount: 9)
        )
        XCTAssertLessThan(ChatAttachmentMetrics.maxPixelSize(imageCount: 1), 512)
    }

    func testDocumentChipIsCapped() {
        XCTAssertLessThan(ChatAttachmentMetrics.documentMaxWidth, 280)
        XCTAssertEqual(ChatAttachmentMetrics.spacing, 4)
    }
}

@MainActor
final class LocalChatAttachmentPersistenceTests: XCTestCase {
    func testPersistsAttachmentsOnLocalMessage() {
        let store = LocalChatStore.shared
        let conv = store.createConversation(title: "Nouvelle conversation", scope: .general)
        let stored = LocalStoredAttachment(
            id: "local-img-1",
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 12_000,
            type: "image",
            localRelativePath: "abc-photo.jpg"
        )
        let msg = store.appendMessage(
            conversationId: conv.id,
            role: .user,
            content: "Voici les images",
            attachments: [stored]
        )
        XCTAssertNotNil(msg)
        let loaded = store.messages(for: conv.id)
        XCTAssertEqual(loaded.first?.attachments?.count, 1)
        XCTAssertEqual(loaded.first?.attachments?.first?.filename, "photo.jpg")
        let dto = loaded.first!.asMessageDTO()
        XCTAssertEqual(dto.attachments?.first?.id, "local-img-1")
        XCTAssertTrue(ChatAttachmentPresentation.isImage(dto.attachments!.first!))
        store.deleteConversation(id: conv.id)
    }

    func testEmptyCaptionUsesFilenameForTitle() {
        let store = LocalChatStore.shared
        let conv = store.createConversation(title: "Nouvelle conversation", scope: .general)
        _ = store.appendMessage(
            conversationId: conv.id,
            role: .user,
            content: "",
            attachments: [
                LocalStoredAttachment(
                    id: "local-doc-1",
                    filename: "document.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 1000,
                    type: "document",
                    localRelativePath: "x-document.pdf"
                )
            ]
        )
        let reloaded = store.conversations.first { $0.id == conv.id }
        XCTAssertEqual(reloaded?.title, "document.pdf")
        store.deleteConversation(id: conv.id)
    }
}
