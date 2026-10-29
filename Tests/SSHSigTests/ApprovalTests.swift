import SSHSig
import XCTest

/// `attention-sign approve` signs only a statement whose first line names a Board
/// approval, and `sign` refuses one. Each refusal has an admitted twin.
final class ApprovalTests: XCTestCase {
  func testAStatementIsAnApprovalOnlyWhenItsFirstLineIsExactlyABoardHeader() {
    XCTAssertEqual(Approval(statement: "board/approve/v1\neffect: 0a\n"), .effect)
    XCTAssertEqual(Approval(statement: "board/write/v1\npath: /effects/a\n"), .write)
    XCTAssertNil(Approval(statement: "board/approve/v2\neffect: 0a\n"))
    XCTAssertNil(Approval(statement: " board/approve/v1\n"))
    XCTAssertNil(Approval(statement: "attention/order/v1\nexpires: 2027-01-16\n"))
  }

  func testTheTwoApprovalsAndAnOrderHaveTheirOwnHeadings() {
    XCTAssertEqual(Approval.effect.title, "Approve a pending effect")
    XCTAssertEqual(Approval.write.title, "Approve your own protected write")
    XCTAssertNotEqual(approvalNamespace, orderNamespace)
  }

  func testAPendingEffectIsSignedInTheApprovalNamespaceAndAnOwnerWriteInItsOwn() {
    XCTAssertEqual(Approval.effect.namespace, "board/approve/v1")
    XCTAssertEqual(Approval.write.namespace, "board/write/v1")
  }
}
