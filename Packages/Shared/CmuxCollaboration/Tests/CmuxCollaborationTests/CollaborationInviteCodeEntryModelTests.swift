import CmuxCollaboration
import Testing

struct CollaborationInviteCodeEntryModelTests {
    @Test
    func entryNormalizesCaseFiltersUnsupportedCharactersAndLimitsToFourLetters() {
        let model = CollaborationInviteCodeEntryModel(value: " a-bcdef12io ")

        #expect(model.value == "ABCD")
        #expect(model.isComplete)
        #expect(model.displayCharacters == ["A", "B", "C", "D"])
    }

    @Test
    func incompleteEntryPadsDisplaySlots() {
        let model = CollaborationInviteCodeEntryModel(value: "az")

        #expect(model.value == "AZ")
        #expect(!model.isComplete)
        #expect(model.displayCharacters == ["A", "Z", "", ""])
    }
}
