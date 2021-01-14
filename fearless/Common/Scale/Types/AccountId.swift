import Foundation
import FearlessUtils

struct AccountId: ScaleCodable {
    let value: Data

    init(value: Data) {
        self.value = value
    }

    init(scaleDecoder: ScaleDecoding) throws {
        value = try scaleDecoder.readAndConfirm(count: 32)
    }

    func encode(scaleEncoder: ScaleEncoding) throws {
        scaleEncoder.appendRaw(data: value)
    }
}
