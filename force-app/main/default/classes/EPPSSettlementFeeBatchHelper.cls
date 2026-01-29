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

				EPPSHelperMethods.Fee_Wrapper fee = new EPPSHelperMethods.Fee_Wrapper();

				fee.CardHolderID = spi.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c;	
				fee.FeeDate = DateTime.newInstance(spi.Payment_Date__c, Time.newInstance(0, 0, 0, 0));
				fee.FeeAmount = sf.Amount__c;
				fee.FeeType = feeDetails.Fee_Type__c;

				fee.Description = feeDetails.Fee_Description__c;

				if (feeDetails.Is_Settlement__c) {

					//TODO make sure this data is there
					fee.AccountNumber = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c;
					fee.RoutingNumber = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Routing__c;
					fee.PaidToName = spi.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;
					fee.PaidToPhone = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Phone__c;
					fee.PaidToStreet = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c;
					//fee.PaidToStreet2 = 'Test'; -- Optional
					fee.PaidToCity = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c;
					fee.PaidToState = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c;
					fee.PaidToZip = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c;
					fee.ContactName = spi.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;
					fee.PaidToCustomerNumber = spi.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c;
				}

				addWrapper.feeWrapper = fee;
				addWrapper.feeSettlementId = sf.Id;
				addWrapperList.add(addWrapper);
			}

			returnMap.put(spi.Id, addWrapperList);
		}
		return returnMap;
	}

	public class AddFee2Wrapper {

		public EPPSHelperMethods.Fee_Wrapper feeWrapper;
		public String feeIdField;
		public String statusField;
		public Id feeSettlementId;
	}
}