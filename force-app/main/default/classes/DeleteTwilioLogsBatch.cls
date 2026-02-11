public class DeleteTwilioLogsBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM TwilioSF__Log__c');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('DeleteTwilioLogsBatch completed');
    }
}