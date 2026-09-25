import Foundation
import MapKit
import Testing
@testable import Agdayo

struct UtilityTests {
    @Test func formattedCurrencyProducesNonEmptyString() {
        #expect(!(100.0).formattedCurrency(code: "PHP").isEmpty)
    }

    @Test func optionalFormattedCurrencyPassesThroughNil() {
        let value: Double? = nil
        #expect(value.formattedCurrency(code: "PHP") == nil)
    }

    @Test func optionalFormattedCurrencyFormatsWrappedValue() {
        let value: Double? = 100
        #expect(value.formattedCurrency(code: "PHP") == Double(100).formattedCurrency(code: "PHP"))
    }

    @Test func transportTypeSFSymbolMappingCoversKnownCases() {
        #expect(MKDirectionsTransportType.walking.sfSymbolName == "figure.walk")
        #expect(MKDirectionsTransportType.transit.sfSymbolName == "bus")
        #expect(MKDirectionsTransportType.cycling.sfSymbolName == "bicycle")
        #expect(MKDirectionsTransportType.automobile.sfSymbolName == "car.fill")
    }

    @Test func mapStyleOptionLabelsAreNonEmptyForEveryCase() {
        for option in MapStyleOption.allCases {
            #expect(!option.label.isEmpty)
        }
    }

    @Test func activityIconLibraryAllIconsMatchesFlattenedCategories() {
        let flattened = ActivityIconLibrary.categories.flatMap { $0.icons }
        #expect(ActivityIconLibrary.allIcons == flattened)
        #expect(!ActivityIconLibrary.allIcons.isEmpty)
    }
}
