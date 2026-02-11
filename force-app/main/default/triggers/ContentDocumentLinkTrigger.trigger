trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert, after delete) {
    // Handle file sync (existing)
    ContentDocumentLinkHandler.handleDocumentChanges(Trigger.new, Trigger.old);

    // Handle ContentNote sync to related records (new)
    ContentNoteLinkHandler.handleNoteChanges(Trigger.new, Trigger.old);
}