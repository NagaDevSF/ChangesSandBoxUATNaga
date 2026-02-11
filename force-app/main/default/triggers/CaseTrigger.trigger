trigger CaseTrigger on Case (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ContentDocumentLinkHandler.handleNewCases(Trigger.new);
    }
}