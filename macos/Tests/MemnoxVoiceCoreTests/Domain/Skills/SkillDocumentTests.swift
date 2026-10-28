import XCTest

@testable import MemnoxVoiceCore

final class SkillDocumentTests: XCTestCase {
    func testReadsTheFrontMatterApartFromTheBody() {
        let document = SkillMarkdownReader.document("---\nname: gsap-core\ndescription: \"Core tweens\"\n---\n# GSAP\n")
        XCTAssertEqual(document.fields, [SkillField(key: "name", value: "gsap-core"), SkillField(key: "description", value: "Core tweens")])
        XCTAssertEqual(document.blocks, [.heading(level: 1, text: "GSAP")])
    }

    func testSplitsHeadingsParagraphsAndRules() {
        let blocks = SkillMarkdownReader.parse("## When to use\nUse it when\nthe page scrolls.\n\n---\n####### not a heading")
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "When to use"),
            .paragraph("Use it when the page scrolls."),
            .rule,
            .paragraph("####### not a heading"),
        ])
    }

    func testKeepsACodeFenceWholeWithItsLanguage() {
        let blocks = SkillMarkdownReader.parse("```ts\nconst a = 1\n\n# not a heading\n```\nafter")
        XCTAssertEqual(blocks, [.code(language: "ts", text: "const a = 1\n\n# not a heading"), .paragraph("after")])
    }

    func testReadsBulletsNumbersAndNesting() {
        let blocks = SkillMarkdownReader.parse("- one\n  - inner\n    carried on\n1. first\n2) second")
        XCTAssertEqual(blocks, [
            .item(depth: 0, number: nil, text: "one"),
            .item(depth: 1, number: nil, text: "inner carried on"),
            .item(depth: 0, number: 1, text: "first"),
            .item(depth: 0, number: 2, text: "second"),
        ])
    }

    func testReadsQuotesAndTablesWithoutTheirSeparator() {
        let blocks = SkillMarkdownReader.parse("> careful\n> here\n\n| A | B |\n|---|:-:|\n| 1 | 2 |")
        XCTAssertEqual(blocks, [.quote("careful here"), .table([["A", "B"], ["1", "2"]])])
    }

    func testLeavesTextWithoutFrontMatterWhole() {
        XCTAssertEqual(SkillMarkdownReader.document("plain").fields, [])
        XCTAssertEqual(SkillMarkdownReader.parse("plain"), [.paragraph("plain")])
    }
}
