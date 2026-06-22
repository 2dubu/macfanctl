import Testing
@testable import SMCKit

@Suite("SMCKey")
struct SMCKeyTests {
    @Test("Encodes and decodes 4-char ASCII")
    func encodeDecode() {
        let key = SMCKey("F0Ac")
        #expect(key.stringValue == "F0Ac")
    }

    @Test("Fan index helpers produce expected keys")
    func fanHelpers() {
        #expect(SMCKey.fanActual(0).stringValue == "F0Ac")
        #expect(SMCKey.fanMin(1).stringValue == "F1Mn")
        #expect(SMCKey.fanMax(2).stringValue == "F2Mx")
        #expect(SMCKey.fanTarget(3).stringValue == "F3Tg")
    }

    @Test("Mode and unlock keys produce expected FourCC")
    func modeAndUnlockKeys() {
        #expect(SMCKey.fanModeUppercase(0).stringValue == "F0Md")
        #expect(SMCKey.fanModeLowercase(0).stringValue == "F0md")
        #expect(SMCKey.fanTest.stringValue == "Ftst")
    }
}

@Suite("SMCKeyData decoders")
struct SMCValueDecoderTests {
    @Test("fpe2 decodes big-endian 14.2 fixed point")
    func fpe2Decoder() {
        // 0x1F40 = 8000 raw → 8000 / 4 = 2000 RPM
        let data = SMCKeyData(key: SMCKey("F0Ac"), dataType: 0, bytes: [0x1F, 0x40])
        #expect(data.fpe2 == 2000.0)
    }

    @Test("ui8 decodes single byte")
    func ui8Decoder() {
        let data = SMCKeyData(key: SMCKey("FNum"), dataType: 0, bytes: [0x02])
        #expect(data.ui8 == 2)
    }

    @Test("sp78 decodes signed 8.8 fixed point")
    func sp78Decoder() {
        // 0x2580 = 9600 → 9600/256 = 37.5 °C
        let data = SMCKeyData(key: SMCKey("TC0P"), dataType: 0, bytes: [0x25, 0x80])
        #expect(data.sp78 == 37.5)
    }
}
