trigger BankVerificationFilesTrigger on ContentDocumentLink (after insert) {
    BankVerificationFileHandler.afterInsert(Trigger.new);
}