import XCTest
@testable import FDLTool

final class PythonBridgeTests: XCTestCase {

    func testAnyCodableEncodeDecode() throws {
        // Test encoding and decoding of AnyCodable with various types
        let values: [String: AnyCodable] = [
            "string": AnyCodable("hello"),
            "int": AnyCodable(42),
            "double": AnyCodable(3.14),
            "bool": AnyCodable(true),
            "array": AnyCodable([1, 2, 3]),
            "dict": AnyCodable(["key": "value"]),
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(values)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["string"]?.stringValue, "hello")
        XCTAssertEqual(decoded["int"]?.intValue, 42)
        XCTAssertEqual(decoded["bool"]?.boolValue, true)
    }

    func testJSONRPCRequestEncoding() throws {
        let request = JSONRPCRequest(
            id: 1,
            method: "fdl.validate",
            params: ["path": AnyCodable("/test/file.fdl.json")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["id"] as? Int, 1)
        XCTAssertEqual(json?["method"] as? String, "fdl.validate")
    }

    func testJSONRPCResponseDecoding() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"valid":true,"errors":[],"warnings":[]}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        XCTAssertEqual(response.id, 1)
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.dictValue?["valid"] as? Bool, true)
    }

    func testJSONRPCErrorDecoding() throws {
        let json = """
        {"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        XCTAssertEqual(response.id, 2)
        XCTAssertNil(response.result)
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertEqual(response.error?.message, "Method not found")
    }
}
