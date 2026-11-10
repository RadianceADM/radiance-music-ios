import XCTest
@testable import RadianceKit

/** Report a Problem: what goes, and what each answer means (Android's ReportTest; radianceph#43, #63). */
final class ReportTests: XCTestCase {
    private let what = Report.What(version: "0.1.0 (1)", system: "iOS 27.0.1, iPhone13,2", install: "00000000-0000-4000-8000-000000000000",
                                   log: "23:56:43.311 radiance-play: hello\n")

    func testEmailAddressesAreTakenOut() {
        let s = Report.scrub("signed in as maria.cruz@example.com, then ana+music@mail.co.uk failed")
        XCTAssertFalse(s.contains("@"))
        XCTAssertEqual(s, "signed in as (email), then (email) failed")
    }

    func testOnlyTheNewestWholeLinesGo() {
        let text = "one\ntwo\nthree\nfour\n"
        XCTAssertEqual(Report.newest(text, 100), text)
        XCTAssertEqual(Report.newest(text, 9), "four\n")
        // counted in UTF-8 bytes, as the admin counts: 3 a letter here
        XCTAssertEqual(Report.newest("一二三\n四五六\n", 12), "四五六\n")
        XCTAssertLessThanOrEqual(Report.newest(String(repeating: "あ", count: 100_000), Report.mostLog).utf8.count, Report.mostLog)
    }

    func testTheBodyIsWhatTheAdminTakes() {
        let empty = what.body("   ")
        XCTAssertNil(empty["note"])
        for k in ["platform", "version", "system", "log", "install"] { XCTAssertNotNil(empty[k], k) }
        XCTAssertEqual(empty["platform"]?.string, "ios")
        XCTAssertEqual(what.body(String(repeating: "a", count: 3000))["note"]?.string?.count, Report.mostNote)
        // the admin needs a log and a short system
        var bare = what
        bare.log = " \n"
        bare.system = String(repeating: "x", count: 600)
        XCTAssertEqual(bare.body("")["log"]?.string, Report.noLog)
        XCTAssertEqual(bare.body("")["system"]?.string?.count, Report.mostSystem)
        XCTAssertTrue(what.shown().contains("Install: iPhone / iPad"))
    }

    func testTheAnswersCodeOrWhyNot() throws {
        XCTAssertEqual(try Report.answer(201, Data(#"{"id": 7, "code": "RM-0007"}"#.utf8), retryAfter: nil), "RM-0007")
        XCTAssertEqual(try Report.answer(201, Data(#"{"id": 12}"#.utf8), retryAfter: nil), "RM-0012")
        XCTAssertThrowsError(try Report.answer(503, Data("{}".utf8), retryAfter: nil)) { e in
            XCTAssertTrue((e as? Plain)?.words.contains("isn't taking these right now") == true)
        }
        XCTAssertThrowsError(try Report.answer(422, Data(#"{"message": "The platform field is invalid."}"#.utf8), retryAfter: nil)) { e in
            XCTAssertEqual((e as? Plain)?.words, "The platform field is invalid.")
        }
        XCTAssertThrowsError(try Report.answer(429, Data(), retryAfter: "180")) { e in
            XCTAssertEqual((e as? Plain)?.words, "Too many tries just now. Try again in 3 minutes.")
        }
        XCTAssertThrowsError(try Report.answer(500, Data(), retryAfter: nil)) { e in
            XCTAssertTrue((e as? Plain)?.words.contains("isn't answering") == true)
        }
    }

    func testTheInstallIdIsMadeOnce() {
        let d = UserDefaults(suiteName: "report-test-\(UUID().uuidString)")!
        let a = Report.installId(d)
        XCTAssertEqual(a.count, 36)
        XCTAssertEqual(Report.installId(d), a)
    }
}
