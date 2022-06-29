//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import Kanvas
import XCTest

class ShaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func testShaderInit() {
        guard let vertexShaderCode = Shader.getSourceCode("base_filter", type: .vertex),
            let fragmentShaderCode = Shader.getSourceCode("base_filter", type: .fragment) else {
                XCTFail("Failed to load shader source code")
                return
        }
        let _ = Shader(vertexShader: vertexShaderCode, fragmentShader: fragmentShaderCode)
    }

}
