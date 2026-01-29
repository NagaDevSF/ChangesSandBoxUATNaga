/**
 * @description Batch Apex to delete all TwilioSF__Log__c records
 * Execute: Database.executeBatch(new DeleteTwilioLogsBatch(), 2000);
 */
public class DeleteTwilioLogsBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer totalDeleted = 0;
    private Integer totalErrors = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM TwilioSF__Log__c');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Database.DeleteResult> results = Database.delete(scope, false);
        for (Database.DeleteResult dr : results) {
            if (dr.isSuccess()) {
                totalDeleted++;
            } else {
                totalErrors++;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('DeleteTwilioLogsBatch completed. Deleted: ' + totalDeleted + ', Errors: ' + totalErrors);
    }
}