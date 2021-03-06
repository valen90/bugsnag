import XCTest
@testable import Vapor
@testable import Bugsnag
import HTTP

class ReporterTests: XCTestCase {
    private var connectionManager: ConnectionManagerMock!
    private var payloadTransformer: PayloadTransformerMock!
    private var reporter: Reporter!

    static let allTests = [
        ("testErrorNotConformingToAbortErrorWillBeReported", testErrorNotConformingToAbortErrorWillBeReported),
        ("testBadRequestAbortErrorWillBeReported", testBadRequestAbortErrorWillBeReported),
        ("testCustomErrorWillBeReported", testCustomErrorWillBeReported),
        ("testErrorNotReportedWhenExplicitlyToldNotTo", testErrorNotReportedWhenExplicitlyToldNotTo),
        ("testErrorReportedWhenExplicitlyToldTo", testErrorReportedWhenExplicitlyToldTo),
        ("testThatThePayloadGetsSubmitted", testThatThePayloadGetsSubmitted),
        ("testThatFiltersComeFromConfig", testThatFiltersComeFromConfig),
        ("testSeverityGetsDefaultValue", testSeverityGetsDefaultValue),
        ("testSeverityGetsGivenValue", testSeverityGetsGivenValue),
        ("testErrorNotReportedWhenEnvironmentNotInNotifyReleaseStages", testErrorNotReportedWhenEnvironmentNotInNotifyReleaseStages),
        ("testErrorReportedWhenEnvironmentInNotifyReleaseStages", testErrorReportedWhenEnvironmentInNotifyReleaseStages),
        ("testErrorNotBeingReportedWhenEmptyReleaseStages", testErrorNotBeingReportedWhenEmptyReleaseStages),
        ("testErrorBeingReportedWhenNilReleaseStages", testErrorBeingReportedWhenNilReleaseStages),
        ("testStackTraceSizeIsComingFromConfig", testStackTraceSizeIsComingFromConfig),
        ("testStackTraceSizeIsComingFromArguments", testStackTraceSizeIsComingFromArguments),
        ("testThatStackTraceSizeGetsValueFromConfigWhenNil", testThatStackTraceSizeGetsValueFromConfigWhenNil),
        ("testThatStackTraceSizeGetsDefaultValueWhenNotInConfig", testThatStackTraceSizeGetsDefaultValueWhenNotInConfig)
    ]

    override func setUp() {
        let drop = try! Droplet(
            arguments: nil,
            workDir: nil,
            environment: .custom("mock-environment"),
            config: nil,
            localization: nil,
            log: nil
        )
        let config = ConfigurationMock()
        self.connectionManager = ConnectionManagerMock(drop: drop, config: config)
        self.payloadTransformer = PayloadTransformerMock(
            environment: drop.environment,
            apiKey: "1337"
        )
        self.reporter = Reporter(
            drop: drop,
            config: config,
            connectionManager: self.connectionManager,
            transformer: self.payloadTransformer
        )
    }

    override func tearDown() {
        self.connectionManager = nil
        self.payloadTransformer = nil
        self.reporter = nil
    }


    // MARK: Automatic reporting.

    func testErrorNotConformingToAbortErrorWillBeReported() {
        let exp = expectation(description: "Custom abort error will be reported")

        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(
            error: MyCustomError(),
            request: req,
            severity: .error,
            completion: {
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.0, Status.internalServerError.reasonPhrase)
                XCTAssertNil(self.payloadTransformer.lastPayloadData!.1)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.method, req.method)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.uri.description, req.uri.description)
                XCTAssertNotNil(self.connectionManager.lastPayload)
                exp.fulfill()
            }
        )

        waitForExpectations(timeout: 1)
    }

    func testBadRequestAbortErrorWillBeReported() {
        let exp = expectation(description: "Bad request error will be reported")

        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(
            error: Abort.badRequest,
            request: req,
            severity: .error,
            completion: {
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.0, Abort.badRequest.reason)
                XCTAssertNil(self.payloadTransformer.lastPayloadData!.1)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.method, req.method)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.uri.description, req.uri.description)
                XCTAssertNotNil(self.connectionManager.lastPayload)
                exp.fulfill()
            }
        )

        waitForExpectations(timeout: 1)
    }

    func testCustomErrorWillBeReported() {
        let exp = expectation(description: "Custom error will be reported")

        let req = try! Request(method: .get, uri: "some-random-uri")
        let metadata: Node? = Node([
            "key1": "value1",
            "key2": "value2"
        ])
        let error = MyCustomAbortError(
            reason: "Test message",
            code: 1337,
            status: .badRequest,
            metadata: metadata
        )

        try! reporter.report(
            error: error,
            request: req,
            severity: .error,
            completion: {
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.0, error.reason)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.1, error.metadata)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.method, req.method)
                XCTAssertEqual(self.payloadTransformer.lastPayloadData!.2?.uri.description, req.uri.description)
                XCTAssertNotNil(self.connectionManager.lastPayload)
                exp.fulfill()
            }
        )

        waitForExpectations(timeout: 1)
    }


    // MARK: - Manual reporting.

    func testErrorNotReportedWhenExplicitlyToldNotTo() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        let error = MyCustomAbortError(
            reason: "",
            code: 0,
            status: .accepted,
            metadata: Node(["report": false])
        )

        try! reporter.report(
            error: error,
            request: req,
            severity: .error,
            completion: {
                XCTFail("Error reported when not supposed to.")
            }
        )

        XCTAssertNil(self.payloadTransformer.lastPayloadData)
        XCTAssertNil(self.connectionManager.lastPayload)
    }

    func testErrorReportedWhenExplicitlyToldTo() {
        let exp = expectation(description: "Error will be reported")

        let req = try! Request(method: .get, uri: "some-random-uri")
        let error = MyCustomAbortError(
            reason: "",
            code: 0,
            status: .accepted,
            metadata: Node(["report": true])
        )

        try! reporter.report(
            error: error,
            request: req,
            severity: .error,
            completion: {
                XCTAssertNotNil(self.payloadTransformer.lastPayloadData)
                XCTAssertNotNil(self.connectionManager.lastPayload)
                exp.fulfill()
            }
        )

        waitForExpectations(timeout: 1)
    }


    // MARK: - Filters.

    func testThatFiltersComeFromConfig() {
        let req = try! Request(method: .get, uri: "some-random-uri")

        try! reporter.report(
            error: Abort.badRequest,
            request: req,
            completion: nil
        )
        
        XCTAssertEqual(self.payloadTransformer.lastPayloadData!.5, ["someFilter"])
    }


    // MARK: - Severity.

    func testSeverityGetsDefaultValue() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(error: Abort.badRequest, request: req, completion: nil)
        XCTAssertEqual(self.payloadTransformer.lastPayloadData?.3, Severity.error)
    }

    func testSeverityGetsGivenValue() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(error: Abort.badRequest, request: req, severity: Severity.info, completion: nil)
        XCTAssertEqual(self.payloadTransformer.lastPayloadData?.3, Severity.info)
    }


    // MARK: - Notify release stages.

    func testErrorNotReportedWhenEnvironmentNotInNotifyReleaseStages() {
        let drop = try! Droplet(
            arguments: nil,
            workDir: nil,
            environment: .development, //currentEnvironment = "development"
            config: nil,
            localization: nil,
            log: nil
        )
        let conf = ConfigurationMock() //notifyReleaseStages = ["mock-environment"]
        let repo = Reporter(
            drop: drop,
            config: conf,
            connectionManager: self.connectionManager,
            transformer: self.payloadTransformer
        )
        try! repo.report(error: Abort.badRequest, request: nil)
        XCTAssertNil(self.payloadTransformer.lastPayloadData)
    }

    func testErrorReportedWhenEnvironmentInNotifyReleaseStages() {
        let drop = try! Droplet(
            arguments: nil,
            workDir: nil,
            environment: .custom("mock-environment"), //currentEnvironment = "mock-environment"
            config: nil,
            localization: nil,
            log: nil
        )
        let conf = ConfigurationMock() //notifyReleaseStages = ["mock-environment"]
        let repo = Reporter(
            drop: drop,
            config: conf,
            connectionManager: self.connectionManager,
            transformer: self.payloadTransformer
        )
        try! repo.report(error: Abort.badRequest, request: nil)
        XCTAssertNotNil(self.payloadTransformer.lastPayloadData)
    }

    func testErrorNotBeingReportedWhenEmptyReleaseStages() {
        let drop = try! Droplet(
            arguments: nil,
            workDir: nil,
            environment: .custom("mock-environment"), //currentEnvironment = "mock-environment"
            config: nil,
            localization: nil,
            log: nil
        )
        let conf = ConfigurationMock(releaseStages: []) //notifyReleaseStages = []
        let repo = Reporter(
            drop: drop,
            config: conf,
            connectionManager: self.connectionManager,
            transformer: self.payloadTransformer
        )
        try! repo.report(error: Abort.badRequest, request: nil)
        XCTAssertNil(self.payloadTransformer.lastPayloadData)

    }

    func testErrorBeingReportedWhenNilReleaseStages() {
        let drop = try! Droplet(
            arguments: nil,
            workDir: nil,
            environment: .custom("mock-environment"), //currentEnvironment = "mock-environment"
            config: nil,
            localization: nil,
            log: nil
        )
        let conf = ConfigurationMock(releaseStages: nil) //notifyReleaseStages = nil
        let repo = Reporter(
            drop: drop,
            config: conf,
            connectionManager: self.connectionManager,
            transformer: self.payloadTransformer
        )
        try! repo.report(error: Abort.badRequest, request: nil)
        XCTAssertNotNil(self.payloadTransformer.lastPayloadData)
    }


    // MARK: - Stack trace size.

    func testStackTraceSizeIsComingFromConfig() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(error: Abort.badRequest, request: req, completion: nil)
        XCTAssertEqual(self.payloadTransformer.lastPayloadData?.4, 1337)
    }

    func testStackTraceSizeIsComingFromArguments() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(error: Abort.badRequest, request: req, stackTraceSize: 150, completion: nil)
        XCTAssertEqual(self.payloadTransformer.lastPayloadData?.4, 150)
    }

    func testThatStackTraceSizeGetsValueFromConfigWhenNil() {
        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(error: Abort.badRequest, request: req, stackTraceSize: nil, completion: nil)
        XCTAssertEqual(self.payloadTransformer.lastPayloadData?.4, 1337)
    }

    func testThatStackTraceSizeGetsDefaultValueWhenNotInConfig() {
        let conf: Config = Config([
            "apiKey": "1337",
            "notifyReleaseStages": ["mock-environment"],
            "endpoint": "some-endpoint",
            "filters": []
            ])
        let config = try! Configuration(config: conf)
        XCTAssertEqual(config.stackTraceSize, 100)
    }


    // MARK: - Submission

    func testThatThePayloadGetsSubmitted() {
        let exp = expectation(description: "Submit payload")

        let req = try! Request(method: .get, uri: "some-random-uri")
        try! reporter.report(
            error: Abort.badRequest,
            request: req,
            severity: .error,
            completion: {
                XCTAssertEqual(self.connectionManager.lastPayload, try! JSON(node: ["transformer": "mock"]))
                exp.fulfill()
            }
        )

        waitForExpectations(timeout: 1)
    }
}

// MARK: - Misc.

internal struct MyCustomError: Error {
    let value = 1337
}

internal struct MyCustomAbortError: AbortError {
    let reason: String
    let code: Int
    let status: Status
    let metadata: Node?
}
