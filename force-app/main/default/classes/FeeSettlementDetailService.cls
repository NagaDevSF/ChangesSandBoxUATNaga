/**
 * @description Service class for Fee_Settlement_Detail__c operations.
 *
 * Centralizes the creation and management of Fee Settlement Detail records,
 * specifically for Banking Fee child records on Payment_Schedule_Item__c.
 *
 * @author DCG Development Team
 * @since 2025-01
 */
public class FeeSettlementDetailService {

    /** Type value for Banking Fee records */
    public static final String FEE_TYPE_BANKING = 'Banking Fee';

    /**
     * @description Create Banking Fee child records for Payment Schedule Items.
     *
     * Creates Fee_Settlement_Detail__c records with Type__c = 'Banking Fee' for each
     * Payment_Schedule_Item__c that has a non-null, positive Banking_Fee_Amount__c.
     *
     * @param scheduleItems List of Payment_Schedule_Item__c records (must have Ids assigned)
     * @return List of Fee_Settlement_Detail__c records to be inserted
     */
    public static List<Fee_Settlement_Detail__c> createBankingFeeDetails(
        List<Payment_Schedule_Item__c> scheduleItems
    ) {
        List<Fee_Settlement_Detail__c> feeDetails = new List<Fee_Settlement_Detail__c>();

        if (scheduleItems == null || scheduleItems.isEmpty()) {
            return feeDetails;
        }

        for (Payment_Schedule_Item__c psi : scheduleItems) {
            // Only create if the PSI has an Id and a banking fee amount
            if (psi.Id != null && psi.Banking_Fee_Amount__c != null && psi.Banking_Fee_Amount__c > 0) {
                Fee_Settlement_Detail__c fsd = new Fee_Settlement_Detail__c();
                fsd.Payment_Schedule_Item__c = psi.Id;
                fsd.Type__c = FEE_TYPE_BANKING;
                fsd.Amount__c = psi.Banking_Fee_Amount__c;
                feeDetails.add(fsd);
            }
        }

        return feeDetails;
    }

    /**
     * @description Get Banking Fee amounts from Fee_Settlement_Detail__c child records.
     *
     * Queries Fee_Settlement_Detail__c records with Type__c = 'Banking Fee' for the given
     * Payment_Schedule_Item__c Ids and returns a map of PSI Id to Banking Fee amount.
     *
     * @param scheduleItemIds Set of Payment_Schedule_Item__c Ids to query
     * @return Map of Payment_Schedule_Item__c Id to Banking Fee amount (null if no record found)
     */
    public static Map<Id, Decimal> getBankingFeesByScheduleItemIds(Set<Id> scheduleItemIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();

        if (scheduleItemIds == null || scheduleItemIds.isEmpty()) {
            return result;
        }

        List<Fee_Settlement_Detail__c> feeDetails = [
            SELECT Id, Payment_Schedule_Item__c, Amount__c
            FROM Fee_Settlement_Detail__c
            WHERE Payment_Schedule_Item__c IN :scheduleItemIds
              AND Type__c = :FEE_TYPE_BANKING
        ];

        for (Fee_Settlement_Detail__c fsd : feeDetails) {
            // Only set if not already mapped (first record wins in case of duplicates)
            if (!result.containsKey(fsd.Payment_Schedule_Item__c)) {
                result.put(fsd.Payment_Schedule_Item__c, fsd.Amount__c);
            }
        }

        return result;
    }

    /**
     * @description Update or create Banking Fee child record for a Payment Schedule Item.
     *
     * If a Fee_Settlement_Detail__c with Type__c = 'Banking Fee' exists, updates its Amount__c.
     * If no such record exists and the amount is positive, creates a new one.
     *
     * @param scheduleItemId The Payment_Schedule_Item__c Id
     * @param bankingFeeAmount The banking fee amount to set
     * @return The Fee_Settlement_Detail__c record (may be new or existing), null if amount is null/zero
     */
    public static Fee_Settlement_Detail__c upsertBankingFeeDetail(
        Id scheduleItemId,
        Decimal bankingFeeAmount
    ) {
        if (scheduleItemId == null) {
            return null;
        }

        // Query for existing Banking Fee record
        List<Fee_Settlement_Detail__c> existing = [
            SELECT Id, Amount__c
            FROM Fee_Settlement_Detail__c
            WHERE Payment_Schedule_Item__c = :scheduleItemId
              AND Type__c = :FEE_TYPE_BANKING
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            // Update existing record
            Fee_Settlement_Detail__c fsd = existing[0];
            fsd.Amount__c = bankingFeeAmount;
            return fsd;
        } else if (bankingFeeAmount != null && bankingFeeAmount > 0) {
            // Create new record
            Fee_Settlement_Detail__c fsd = new Fee_Settlement_Detail__c();
            fsd.Payment_Schedule_Item__c = scheduleItemId;
            fsd.Type__c = FEE_TYPE_BANKING;
            fsd.Amount__c = bankingFeeAmount;
            return fsd;
        }

        return null;
    }
}
