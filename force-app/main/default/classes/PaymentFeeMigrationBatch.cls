/**
 * @description Batch class to migrate existing Payment_Schedule_Item__c records
 * by creating corresponding Payment_Fee__c child records.
 *
 * This migration is necessary when transitioning from storing fee amounts
 * as flat fields on Payment_Schedule_Item__c to storing them as separate
 * Payment_Fee__c child records.
 *
 * Each Payment_Schedule_Item__c will get 3 Payment_Fee__c records:
 * - Banking Fee (from Banking_Fee_Amount__c)
 * - Program Fee (from Program_Fee_Amount__c)
 * - Setup Fee (from Setup_Fee_Amount__c)
 *
 * Note: Savings/Escrow amounts are stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
 *
 * USAGE:
 * Run in Anonymous Apex:
 *   Database.executeBatch(new PaymentFeeMigrationBatch(), 200);
 *
 * Or to run with custom batch size:
 *   Database.executeBatch(new PaymentFeeMigrationBatch(), 100);
 *
 * VALIDATION:
 * After migration, verify counts match:
 *   SELECT COUNT() FROM Payment_Schedule_Item__c
 *   vs
 *   SELECT COUNT() FROM Payment_Fee__c WHERE Type__c IN ('Banking Fee','Program Fee','Setup Fee')
 *   (Fee count should be 3x schedule item count)
 */
public without sharing class PaymentFeeMigrationBatch implements Database.Batchable<sObject>, Database.Stateful {

    // Counters for tracking migration progress
    private Integer totalItemsProcessed = 0;
    private Integer totalFeeRecordsCreated = 0;
    private Integer totalErrors = 0;

    /**
     * @description Start method to define the query locator.
     * Only selects Payment_Schedule_Item__c records that don't already have
     * Payment_Fee__c child records (prevents duplicate migration).
     *
     * @param bc Batchable context
     * @return QueryLocator for schedule items without fee records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Banking_Fee_Amount__c, Program_Fee_Amount__c,
                   Setup_Fee_Amount__c, To_Escrow_Amount__c
            FROM Payment_Schedule_Item__c
            WHERE Id NOT IN (
                SELECT Payment_Schedule_Item__c
                FROM Payment_Fee__c
                WHERE Type__c IN :PaymentFeeService.SCHEDULE_ITEM_FEE_TYPES
            )
            ORDER BY CreatedDate ASC
        ]);
    }

    /**
     * @description Execute method to process each batch of records.
     * Creates 3 Payment_Fee__c records for each Payment_Schedule_Item__c.
     *
     * @param bc Batchable context
     * @param scope List of Payment_Schedule_Item__c records to process
     */
    public void execute(Database.BatchableContext bc, List<Payment_Schedule_Item__c> scope) {
        List<Payment_Fee__c> feeRecords = new List<Payment_Fee__c>();

        for (Payment_Schedule_Item__c psi : scope) {
            feeRecords.addAll(PaymentFeeService.createFeeRecordsForItem(
                psi,
                psi.Banking_Fee_Amount__c,
                psi.Program_Fee_Amount__c,
                psi.Setup_Fee_Amount__c
            ));
        }

        if (!feeRecords.isEmpty()) {
            Database.SaveResult[] results = Database.insert(feeRecords, false);

            // Count successes and failures
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    totalFeeRecordsCreated++;
                } else {
                    totalErrors++;
                    for (Database.Error err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'PaymentFeeMigrationBatch: Error creating fee record - ' + err.getMessage());
                    }
                }
            }
        }

        totalItemsProcessed += scope.size();
        System.debug(LoggingLevel.INFO, 'PaymentFeeMigrationBatch: Processed ' + scope.size() + ' schedule items, created ' + feeRecords.size() + ' fee records');
    }

    /**
     * @description Finish method to log migration summary.
     *
     * @param bc Batchable context
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'PaymentFeeMigrationBatch: Migration Complete');
        System.debug(LoggingLevel.INFO, '========================================');
        System.debug(LoggingLevel.INFO, 'Total Schedule Items Processed: ' + totalItemsProcessed);
        System.debug(LoggingLevel.INFO, 'Total Fee Records Created: ' + totalFeeRecordsCreated);
        System.debug(LoggingLevel.INFO, 'Total Errors: ' + totalErrors);
        System.debug(LoggingLevel.INFO, '========================================');

        // Expected fee records = 3 per schedule item (Banking, Program, Setup)
        Integer expectedFeeRecords = totalItemsProcessed * 3;
        if (totalFeeRecordsCreated == expectedFeeRecords && totalErrors == 0) {
            System.debug(LoggingLevel.INFO, 'Migration completed successfully with no errors.');
        } else {
            System.debug(LoggingLevel.WARN, 'Migration completed with discrepancies. Expected: ' + expectedFeeRecords + ' fee records, Created: ' + totalFeeRecordsCreated);
        }
    }
}