public class LeadAssignmentBatch implements Database.Batchable<sObject> {

    public Database.QueryLocator start(Database.BatchableContext BC) {
        // Calculate the effective 48-hour window excluding weekends
        DateTime effective48HourWindow = LeadAssignmentHelper.calculateEffective48HourWindow(DateTime.now());

        // Query leads that meet the criteria for reassignment
        String query = 'SELECT Id, OwnerId, Updated_date_ref__c ' +
                       'FROM Lead ' +
                       'WHERE Status = \'New\' ' +
                       'AND Sales_Office_Ref__c = \'Debtifi\' ' +
                       'AND Updated_date_ref__c < :effective48HourWindow';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext BC, List<Lead> scope) {
        // Reassign the leads using the helper method
        LeadAssignmentHelper.reassignLeads(scope);
    }

    public void finish(Database.BatchableContext BC) {
        // Optional: Add any post-processing logic here (e.g., logging, notifications)
    }
}