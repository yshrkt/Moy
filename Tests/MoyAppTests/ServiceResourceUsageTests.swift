import AppKit
@testable import MoyApp
import MoyMetrics
import Testing

struct ServiceResourceUsageTests {
    @Test
    func `CPU and memory use localized numbers and preserve 100 percent plus values`() {
        let locale = Locale(identifier: "en_US")
        #expect(ServiceResourceUsagePresentation.cpu(.value(250.25), unavailable: false, locale: locale) == "250.2%")
        #expect(ServiceResourceUsagePresentation.cpu(.value(0), unavailable: false, locale: locale) == "0.0%")
        #expect(ServiceResourceUsagePresentation.memory(.value(128 * 1024 * 1024), unavailable: false, locale: locale)
            == "128 MB")
        let german = Locale(identifier: "de_DE")
        #expect(ServiceResourceUsagePresentation.cpu(.value(12.3), unavailable: false, locale: german)
            .contains("12,3"))
    }

    @Test
    func `memory includes installed capacity without inventing an unavailable denominator`() {
        let locale = Locale(identifier: "en_US")
        let usage = MetricValue<UInt64>.value(128 * 1024 * 1024)
        #expect(ServiceResourceUsagePresentation.memory(
            usage, totalMemory: 32 * 1024 * 1024 * 1024, unavailable: false, locale: locale,
        ) == "128 MB / 32 GB")
        #expect(ServiceResourceUsagePresentation.memory(
            usage, totalMemory: 0, unavailable: false, locale: locale,
        ) == "128 MB")
        #expect(ServiceResourceUsagePresentation.memory(
            .failed(.counterOverflow), totalMemory: 32 * 1024 * 1024 * 1024, unavailable: false, locale: locale,
        ) == "—")
    }

    @Test
    func `waiting and unavailable values are distinct`() {
        let locale = Locale(identifier: "en_US")
        #expect(ServiceResourceUsagePresentation.cpu(.waiting, unavailable: false, locale: locale)
            == L10n.Services.Metrics.measuring)
        #expect(ServiceResourceUsagePresentation.memory(nil, unavailable: false, locale: locale)
            == L10n.Services.Metrics.measuring)
        let failure = MetricValue<Double>.failed(.counterOverflow)
        #expect(ServiceResourceUsagePresentation.cpu(failure, unavailable: false, locale: locale) == "—")
        #expect(ServiceResourceUsagePresentation.memory(.value(1024), unavailable: true, locale: locale) == "—")
        #expect(ServiceResourceUsagePresentation.isUnavailable(failure, unavailable: false))
        #expect(!ServiceResourceUsagePresentation.isUnavailable(MetricValue<Double>.waiting, unavailable: false))
    }

    @Test
    func `metrics labels and help have Japanese and English translations`() throws {
        for language in ["ja", "en"] {
            let path = try #require(MoyResources.bundle.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for suffix in ["cpu", "memory", "measuring", "unavailable", "cpuHelp", "memoryHelp",
                           "memoryUsage", "historyRange"]
            {
                let key = "services.metrics.\(suffix)"
                #expect(bundle.localizedString(forKey: key, value: nil, table: "Localizable") != key)
            }
        }
    }
}
