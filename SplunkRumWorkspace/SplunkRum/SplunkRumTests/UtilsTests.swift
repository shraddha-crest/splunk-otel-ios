//
/*
Copyright 2021 Splunk Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import Foundation
import XCTest
@testable import SplunkRum
import StdoutExporter
import OpenTelemetrySdk

class UtilsTests: XCTestCase {

    func testSessionId() throws {
        let s1 = generateNewSessionId()
        let s2 = generateNewSessionId()
        XCTAssertNotEqual(s1, s2)
        XCTAssertEqual(s1.count, 32)
        for char in s1 {
            XCTAssertTrue(("0"..."9").contains(char) || ("a"..."f").contains(char))
        }
    }

    func testLengthLimitingExporter() throws {
        try initializeTestEnvironment()
        // This test is shaped kinda funny since we can't construct SpanData() directly
        let span = buildTracer().spanBuilder(spanName: "limitTest").startSpan()
        var longString = "0123456789abcdef"
        var i = 0
        while i < 9 {
            longString += longString
            i += 1
        }
        XCTAssertTrue(longString.count > 4096)
        span.setAttribute(key: "longString", value: longString)
        span.setAttribute(key: "normalString", value: "normal")
        span.setAttribute(key: "normalInt", value: 7)
        span.end()
        XCTAssertEqual(1, localSpans.count)
        let rawSpans = localSpans
        XCTAssertTrue(rawSpans[0].attributes["longString"]?.description.count ?? 0 > 4096)
        localSpans.removeAll()
        let le = LimitingExporter(proxy: TestSpanExporter(), rejectionFilter: nil) // rewrites into localSpans; yes, this is weird
        _ = le.export(spans: rawSpans)
        XCTAssertEqual(1, localSpans.count)
        XCTAssertTrue(localSpans[0].attributes["longString"]?.description.count ?? 4097 <= 4096)
        XCTAssertEqual("normal", localSpans[0].attributes["normalString"]?.description ?? nil)
        XCTAssertEqual("7", localSpans[0].attributes["normalInt"]?.description ?? nil)
    }

    func testRateLimitingExporter() throws {
        try initializeTestEnvironment()
        // This test is shaped kinda funny since we can't construct SpanData() directly
        var i = 0
        while i < 102 {
            let s = buildTracer().spanBuilder(spanName: "limitTest").startSpan()
            s.setAttribute(key: "component", value: "test")
            s.end()
            i += 1
        }
        XCTAssertEqual(102, localSpans.count)
        var rawSpans = localSpans
        localSpans.removeAll()
        let le = LimitingExporter(proxy: TestSpanExporter(), rejectionFilter: nil) // rewrites into localSpans; yes, this is weird
        _ = le.export(spans: rawSpans)
        XCTAssertEqual(100, localSpans.count)
        localSpans.removeAll()

        // send one more, should still be dropped unless this test took over 30 seconds to run
        let s = buildTracer().spanBuilder(spanName: "limitTest").startSpan()
        s.setAttribute(key: "component", value: "test")
        s.end()
        XCTAssertEqual(1, localSpans.count)
        rawSpans = localSpans
        localSpans.removeAll()
        _ = le.export(spans: rawSpans)
        XCTAssertEqual(0, localSpans.count)

        // reset the exporter by changing "now"
        le.possiblyResetRateLimits(Date().addingTimeInterval(TimeInterval(LimitingExporter.SPAN_RATE_LIMIT_PERIOD+1)))
        // send one more, should not be dropped
        let s2 = buildTracer().spanBuilder(spanName: "limitTest").startSpan()
        s2.setAttribute(key: "component", value: "test")
        s2.end()
        XCTAssertEqual(1, localSpans.count)
        rawSpans = localSpans
        localSpans.removeAll()
        _ = le.export(spans: rawSpans)
        XCTAssertEqual(1, localSpans.count)
    }

    func testRejectingLimitingExporter() throws {
        try initializeTestEnvironment()
        // This test is shaped kinda funny since we can't construct SpanData() directly
        buildTracer().spanBuilder(spanName: "rejectTest").startSpan().end()
        buildTracer().spanBuilder(spanName: "regularTest").startSpan().end()
        XCTAssertEqual(2, localSpans.count)
        let rawSpans = localSpans
        localSpans.removeAll()

        // rewrites into localSpans; yes, this is weird
        let le = LimitingExporter(proxy: TestSpanExporter()) { spanData in
            return spanData.name == "rejectTest"
        }
        _ = le.export(spans: rawSpans)
        XCTAssertEqual(1, localSpans.count)
        XCTAssertEqual(localSpans[0].name, "regularTest")

    }

    func testSetGlobalAttributes() throws {
        try initializeTestEnvironment()
        SplunkRum.setGlobalAttributes( ["additionalKey": "additionalValue"] )
        buildTracer().spanBuilder(spanName: "attrsTest").startSpan().end()
        XCTAssertEqual(1, localSpans.count)
        XCTAssertEqual("additionalValue", localSpans[0].attributes["additionalKey"]?.description ?? nil)
        localSpans.removeAll()

        SplunkRum.setGlobalAttributes( ["additionalKey": "changedValue"] )
        buildTracer().spanBuilder(spanName: "attrsTest").startSpan().end()
        XCTAssertEqual(1, localSpans.count)
        XCTAssertEqual("changedValue", localSpans[0].attributes["additionalKey"]?.description ?? nil)
        localSpans.removeAll()

        SplunkRum.removeGlobalAttribute("additionalKey")
        buildTracer().spanBuilder(spanName: "attrsTest").startSpan().end()
        XCTAssertEqual(1, localSpans.count)
        XCTAssertEqual(nil, localSpans[0].attributes["additionalKey"]?.description ?? nil)
        localSpans.removeAll()

    }

}
