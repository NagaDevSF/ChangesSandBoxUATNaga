/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeBatchHelper
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : Helper class for EPPSPaymentFeeBatch
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSPaymentFeeBatchHelper {

	public static Map<Id, List<AddFee2Wrapper>> buildAPICallMap(List<Payment_Schedule_Item__c> psiList) {

		Map<Id, List<AddFee2Wrapper>> returnMap = new Map<Id, List<AddFee2Wrapper>> ();
		Map<String, EPPS_Fee__mdt> feeMap = EPPSHelperMethods.getFeesByLabel();

		for (Payment_Schedule_Item__c psi : psiList) {

			List<AddFee2Wrapper> addWrapperList = new List<AddFee2Wrapper>();

			// loop through child fee/settlement records
			for (Payment_Fee__c pf : psi.Payment_Fees__r) {

				AddFee2Wrapper addWrapper = new AddFee2Wrapper();
				// TODO what if the metadata is missing for a fee type? or fee type not specified, maybe trap null at query
				
				// this fee type details
				EPPS_Fee__mdt feeDetails = feeMap.get(pf.Type__c);

				if (feeDetails.Send_to_EPPS__c) {

					EPPSHelperMethods.Fee_Wrapper fee = new EPPSHelperMethods.Fee_Wrapper();

					fee.CardHolderID = psi.Payment_Plan__r.Opportunity__r.Account.EPPS_Id__c;	
					fee.FeeDate = DateTime.newInstance(psi.Payment_Date__c, Time.newInstance(0, 0, 0, 0));
					fee.FeeAmount = pf.Amount__c;
					fee.FeeType = pf.Type__c;
					fee.Description = feeDetails.Fee_Description__c;
					fee.PaidToName = feeDetails.PaidToName__c;
					fee.ContactName = feeDetails.PaidToContactName__c;
					fee.Description = feeDetails.Fee_Description__c;

					addWrapper.feeWrapper = fee;
					addWrapper.feeSettlementId = pf.Id;
					addWrapperList.add(addWrapper);
				}
			}

			returnMap.put(psi.Id, addWrapperList);
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