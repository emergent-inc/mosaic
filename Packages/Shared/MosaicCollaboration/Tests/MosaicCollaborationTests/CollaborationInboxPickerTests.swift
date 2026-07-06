import MosaicCollaboration
import Testing

@Suite struct CollaborationInboxPickerTests {
    @Test func keepsDistinctInvitesWithTheirBaseTitle() {
        let rows = CollaborationInboxPicker.rows(from: [
            CollaborationInboxPickerInput(session: "s1", baseTitle: "Shared by Alex in Acme", detail: "5 minutes ago"),
            CollaborationInboxPickerInput(session: "s2", baseTitle: "Shared by Bo in Acme", detail: "2 hours ago"),
        ])

        #expect(rows.count == 2)
        #expect(rows[0] == CollaborationInboxPickerRow(session: "s1", title: "Shared by Alex in Acme"))
        #expect(rows[1] == CollaborationInboxPickerRow(session: "s2", title: "Shared by Bo in Acme"))
    }

    @Test func disambiguatesDuplicateOwnerTitlesWithDetail() {
        // The core bug: two invites from the same owner+org share a title and
        // would collapse in an NSPopUpButton. Every session must stay visible.
        let rows = CollaborationInboxPicker.rows(from: [
            CollaborationInboxPickerInput(session: "s1", baseTitle: "Shared by Alex in Acme", detail: "5 minutes ago"),
            CollaborationInboxPickerInput(session: "s2", baseTitle: "Shared by Alex in Acme", detail: "yesterday"),
        ])

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.session)) == ["s1", "s2"])
        #expect(rows[0].title == "Shared by Alex in Acme \u{2014} 5 minutes ago")
        #expect(rows[1].title == "Shared by Alex in Acme \u{2014} yesterday")
        // Titles must be unique so the list is readable.
        #expect(Set(rows.map(\.title)).count == 2)
    }

    @Test func appendsOrdinalWhenBaseTitleAndDetailBothCollide() {
        let rows = CollaborationInboxPicker.rows(from: [
            CollaborationInboxPickerInput(session: "s1", baseTitle: "Shared by Alex in Acme", detail: "just now"),
            CollaborationInboxPickerInput(session: "s2", baseTitle: "Shared by Alex in Acme", detail: "just now"),
            CollaborationInboxPickerInput(session: "s3", baseTitle: "Shared by Alex in Acme", detail: "just now"),
        ])

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.session)) == ["s1", "s2", "s3"])
        #expect(Set(rows.map(\.title)).count == 3)
    }

    @Test func keepsBaseTitleWhenDuplicateHasNoDetail() {
        let rows = CollaborationInboxPicker.rows(from: [
            CollaborationInboxPickerInput(session: "s1", baseTitle: "Shared by Alex in Acme", detail: nil),
            CollaborationInboxPickerInput(session: "s2", baseTitle: "Shared by Alex in Acme", detail: nil),
        ])

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.session)) == ["s1", "s2"])
        // Distinct titles via ordinal even without a detail to append.
        #expect(Set(rows.map(\.title)).count == 2)
    }

    @Test func preservesInputOrder() {
        let rows = CollaborationInboxPicker.rows(from: [
            CollaborationInboxPickerInput(session: "s3", baseTitle: "C"),
            CollaborationInboxPickerInput(session: "s1", baseTitle: "A"),
            CollaborationInboxPickerInput(session: "s2", baseTitle: "B"),
        ])

        #expect(rows.map(\.session) == ["s3", "s1", "s2"])
    }
}
