import Testing
import MosaicTerminalCore

@Suite struct SurfaceConfigTemplateFontSizeTests {
    @Test func convertsRuntimeFontSizeToBasePoints() {
        let basePoints = MosaicSurfaceConfigTemplate.baseFontSize(fromRuntimePoints: 24, percent: 200)

        #expect(abs(basePoints - 12) < 0.001)
    }

    @Test func convertsBaseFontSizeToRuntimePoints() {
        let runtimePoints = MosaicSurfaceConfigTemplate.runtimeFontSize(fromBasePoints: 12, percent: 200)

        #expect(abs(runtimePoints - 24) < 0.001)
    }

    @Test func inheritedRuntimeFontSizeRoundTripsWithoutCompounding() {
        let basePoints = MosaicSurfaceConfigTemplate.baseFontSize(fromRuntimePoints: 24, percent: 200)
        let runtimePoints = MosaicSurfaceConfigTemplate.runtimeFontSize(fromBasePoints: basePoints, percent: 200)

        #expect(abs(runtimePoints - 24) < 0.001)
    }
}
