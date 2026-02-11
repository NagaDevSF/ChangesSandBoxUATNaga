trigger EmailMessageTrigger on EmailMessage (after insert) {
    EmailMessageTriggerHandler.handleAfterInsert(Trigger.new);
}