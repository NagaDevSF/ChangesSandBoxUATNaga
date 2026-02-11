trigger LeadBlacklistTrigger on Lead (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        LeadBlacklistHandler.handleAfterInsert(Trigger.new);
    }
}