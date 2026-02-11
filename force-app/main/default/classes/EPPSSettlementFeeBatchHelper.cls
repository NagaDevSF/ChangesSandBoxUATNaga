/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSSettlementFeeBatchHelper
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : Helper Class to support EPPSSettlementFeeBatch
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSSettlementFeeBatchHelper {

	public static Map<Id, List<AddFee2Wrapper>> buildAPICallMap(List<Settlement_Plan_Item__c> spiList) {

		Map<Id, List<AddFee2Wrapper>> returnMap = new Map<Id, List<AddFee2Wrapper>> ();
		Map<String, EPPS_Fee__mdt> feeMap = EPPSHelperMethods.getFeesByLabel();

		for (Settlement_Plan_Item__c spi : spiList) {

			List<AddFee2Wrapper> addWrapperList = new List<AddFee2Wrapper>();

			// loop through child fee/settlement records
			for (Settlement_Fee__c sf : spi.Settlement_Fees__r) {

				AddFee2Wrapper addWrapper = new AddFee2Wrapper();
				// TODO what if the metadata is missing for a fee type? or fee type not specified, maybe trap null at query
				
				// this fee type details
				EPPS_Fee__mdt feeDetails = feeMap.get(sf.Type__c);

				if (feeDetails.Send_to_EPPS__c) { 

					EPPSHelperMethods.Fee_Wrapper fee = new EPPSHelperMethods.Fee_Wrapper();

					fee.CardHolderID = spi.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c;	
					fee.FeeDate = DateTime.newInstance(spi.Payment_Date__c, Time.newInstance(0, 0, 0, 0));
					fee.FeeAmount = sf.Amount__c;
					fee.FeeType = sf.Type__c;

					if (!feeDetails.Is_Settlement__c) {
						fee.PaidToName = feeDetails.PaidToName__c;
						fee.ContactName = feeDetails.PaidToContactName__c;
						fee.Description = feeDetails.Fee_Description__c;
					}

					if (feeDetails.Is_Settlement__c) {

						//TODO make sure this data is there
						fee.AccountNumber = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c;
						fee.RoutingNumber = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Routing__c;
						fee.PaidToName = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Name__c;
						fee.PaidToPhone = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.Phone;
						fee.PaidToStreet = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.BillingStreet;
						//fee.PaidToStreet2 = 'Test'; -- Optional
						fee.PaidToCity = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.BillingCity;
						fee.PaidToState = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.BillingState;
						fee.PaidToZip = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.BillingPostalCode;
						fee.ContactName = spi.Settlement_Plan__r.CreditorOpportunity__r.CreditorAccount__r.Name;
						//fee.PaidToCustomerNumber =
						fee.Description = buildACHReference(spi.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account,
												spi.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Memo__c);
					}

					addWrapper.feeWrapper = fee;
					addWrapper.feeSettlementId = sf.Id;
					addWrapperList.add(addWrapper);
				}
			}

			returnMap.put(spi.Id, addWrapperList);
		}
		return returnMap;
	}

	/**
     * @param acct  Account record containing holder name + EIN
     * @param memo  Memo string from ANY source (other object, computed, etc.)
     */
    public static String buildACHReference(Account acct, String memo) {
        
		if (acct == null) {
            return null;
        }

        String accountHolderName = buildAccountHolderName(acct);
        String einLast4 = getLast4EIN(acct.EIN_Employer_Identification_Number__c);

        String reference = 'ACH-' + accountHolderName + '-**' + einLast4;

        // Only append memo section if memo string is provided
        if (String.isNotBlank(memo)) {
            reference += '-(' + memo.trim() + ')';
        }

        return reference;
    }

    private static String buildAccountHolderName(Account acct) {
        String first = acct.Account_Holder_Name__c;
        String last  = acct.Account_Holder_Last_Name__c;

        if (String.isBlank(first) && String.isBlank(last)) {
            return 'UNKNOWN';
        }
        if (String.isBlank(first)) {
            return last.trim();
        }
        if (String.isBlank(last)) {
            return first.trim();
        }

        return first.trim() + ' ' + last.trim();
    }

    private static String getLast4EIN(String ein) {
        if (String.isBlank(ein)) {
            return 'XXXX';
        }

        String digitsOnly = ein.replaceAll('[^0-9]', '');

        if (digitsOnly.length() < 4) {
            return 'XXXX';
        }

        return digitsOnly.substring(digitsOnly.length() - 4);
    }

	public class AddFee2Wrapper {

		public EPPSHelperMethods.Fee_Wrapper feeWrapper;
		public String feeIdField;
		public String statusField;
		public Id feeSettlementId;
	}
}