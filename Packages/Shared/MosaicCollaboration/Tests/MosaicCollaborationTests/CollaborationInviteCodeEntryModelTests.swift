import MosaicCollaboration
import Testing

struct CollaborationInviteCodeEntryModelTests {
    @Test
    func entryUsesEightVisibleSlots() {
        #expect(CollaborationInviteCodeEntryModel.codeLength == 8)
        #expect(CollaborationInviteCodeEntryModel().displayCharacters == ["", "", "", "", "", "", "", ""])
    }

    @Test
    func entryNormalizesCaseFiltersUnsupportedCharactersAndLimitsToEightCharacters() {
        let model = CollaborationInviteCodeEntryModel(value: " a-bcdef12io ")

        #expect(model.value == "ABCDEF12")
        #expect(model.isComplete)
        #expect(model.displayCharacters == ["A", "B", "C", "D", "E", "F", "1", "2"])
    }

    @Test
    func incompleteEntryPadsDisplaySlots() {
        let model = CollaborationInviteCodeEntryModel(value: "az09")

        #expect(model.value == "AZ09")
        #expect(!model.isComplete)
        #expect(model.displayCharacters == ["A", "Z", "0", "9", "", "", "", ""])
    }

    @Test
    func exactEightCharacterEntryIsComplete() {
        let model = CollaborationInviteCodeEntryModel(value: "nxplxzah")

        #expect(model.value == "NXPLXZAH")
        #expect(model.isComplete)
        #expect(model.displayCharacters == ["N", "X", "P", "L", "X", "Z", "A", "H"])
    }

    @Test
    func digitsAndAmbiguousLettersAreAcceptedForFullAlphanumericCodes() {
        let model = CollaborationInviteCodeEntryModel(value: "10io9zab")

        #expect(model.value == "10IO9ZAB")
        #expect(model.isComplete)
        #expect(model.displayCharacters == ["1", "0", "I", "O", "9", "Z", "A", "B"])
    }

    @Test
    func overlongPasteTruncatesToVisibleSlots() {
        let model = CollaborationInviteCodeEntryModel(value: "abcdefghijk123")

        #expect(model.value == "ABCDEFGH")
        #expect(model.isComplete)
    }

    @Test
    func unsupportedCharactersDoNotContributeToLength() {
        let model = CollaborationInviteCodeEntryModel(value: "n-x_p l.z a h!")

        #expect(model.value == "NXPLZAH")
        #expect(!model.isComplete)
        #expect(model.displayCharacters == ["N", "X", "P", "L", "Z", "A", "H", ""])
    }

    @Test
    func replaceUpdatesValueCompletenessAndDisplayCharacters() {
        var model = CollaborationInviteCodeEntryModel(value: "abc")

        model.replace(with: "jxc62dzn")

        #expect(model.value == "JXC62DZN")
        #expect(model.isComplete)
        #expect(model.displayCharacters == ["J", "X", "C", "6", "2", "D", "Z", "N"])
    }
}
