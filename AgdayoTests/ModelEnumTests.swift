import Foundation
import Testing
@testable import Agdayo

struct ModelEnumTests {
    @Test func transportModeDisplayNamesAndIconsAreNonEmptyForEveryCase() {
        for mode in TransportMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.iconName.isEmpty)
        }
    }

    @Test func accommodationTypeDisplayNamesAreNonEmptyForEveryCase() {
        for type in AccommodationType.allCases {
            #expect(!type.displayName.isEmpty)
        }
    }

    @Test func tripThemeDisplayNameIsCapitalizedRawValue() {
        for theme in TripTheme.allCases {
            #expect(theme.displayName == theme.rawValue.capitalized)
        }
    }

    @Test func vacationTypeDisplayNameIsCapitalizedRawValue() {
        for type in VacationType.allCases {
            #expect(type.displayName == type.rawValue.capitalized)
        }
    }
}
