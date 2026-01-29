public class EPPSClientPaymentBatchHelper {

	public static final String PSI_STATUS_SENT_TO_EPPS = 'Sent to EPPS';
	public static final String PSI_STATUS_FAILED_TO_EPPS = 'Failed to EPPS';

	public static Date getDateAfterBusinessDays(Integer businessDaysAhead) {
        BusinessHours bh = [
            SELECT Id 
            FROM BusinessHours 
            WHERE Name = 'Banking Hours'
            LIMIT 1
        ];

        Datetime start = System.now();
        Datetime result = BusinessHours.add(bh.Id, start, businessDaysAhead * 24 * 60 * 60 * 1000);

        return result.date();
    }

	    /**
     * Get Active Bank Info for each Account in the set.
     * Returns a Map<AccountId, Account_Bank_Information__c>
     */
    public static Map<Id, Account_Bank_Information__c> getActiveBankInfoByAccountIds(Set<Id> accountIds) {

        Map<Id, Account_Bank_Information__c> results = new Map<Id, Account_Bank_Information__c>();

        if (accountIds == null || accountIds.isEmpty()) {
            return results;
        }

        List<Account_Bank_Information__c> bankInfoList = [
            SELECT Id, Account__c, Activate__c,
                   Bank_Account_Number__c,
				   Bank_Account_Type__c,
				   Bank_Name__c,
				   Bank_Phone__c,
				   Bank_Street_Address__c,
				   City__c,
				   Payment_Type__c,
				   Routing__c,
				   State__c,
				   Zip_Code__c,
				   Account__r.EPPS_ID__c
            FROM Account_Bank_Information__c
            WHERE Account__c IN :accountIds
              AND Activate__c = TRUE
			  AND Payment_Type__c = 'ACH'
			  AND Account__r.EPPS_ID__c != null
        ];

        // If multiple bank info rows exist → store only 1 per account
        for (Account_Bank_Information__c abi : bankInfoList) {
            if (!results.containsKey(abi.Account__c)) {
                results.put(abi.Account__c, abi);
            }
        }

        return results;
    }
}