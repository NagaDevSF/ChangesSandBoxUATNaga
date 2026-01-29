public class EPPSManageFees  
{


	//////////////////   Update Settlement Section

	//  Accepts a Settlement Plan Item and updates all line item detail records for 
	//  that line item.
	@AuraEnabled
	public static List<EPPSHelperMethods.EPPSResponse> updateSettlementLineItemFees(ID theItemId)
	{
		List<Settlement_Fee__c> theDetailItems = new List<Settlement_Fee__c>();

		theDetailItems = getFeeSettlementDetailRecords(theItemId, theDetailItems);
		List<EPPSHelperMethods.EPPSResponse> theResponses = new List<EPPSHelperMethods.EPPSResponse>();
		for (Settlement_Fee__c theDetailItem : theDetailItems)
		{
			EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
			wrapper = convertSettlementFeeItemToFeeWrapper(theDetailItem);
			wrapper.FeeID = theDetailItem.Fee_Id__c;
			wrapper.FeeAmount = theDetailItem.Amount__c;
			
			EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, theDetailItem.Id);	
					
			theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
			theResponses.add(theResponse);
		}

		update theDetailItems;
		return theResponses;
	}

	//  Accepts a detail Item Id and updates a singular fee.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse updateSettlementDetailFee(ID theDetailItemId)
	{
		Settlement_Fee__c theDetailItem = new Settlement_Fee__c(); 
		theDetailItem = getSettlementPlanDetailRecord(theDetailItemId, theDetailItem);

		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertSettlementFeeItemToFeeWrapper(theDetailItem);
		wrapper.FeeID = theDetailItem.Fee_Id__c;
		wrapper.FeeAmount = theDetailItem.Amount__c;
		
		EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, theDetailItemId);	
					
		theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
							
		return theResponse;
	}


	//  Accepts a settlement plan item ID and a string value for the fee type to be updated.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse updateSettlementDetailFeeByType(ID theItemId, string theType)
	{
		Settlement_Fee__c theSettlementDetail = new Settlement_Fee__c();

		theSettlementDetail = getFeeSettlementDetailRecordByType(theItemId, theSettlementDetail, theType);
		
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertSettlementFeeItemToFeeWrapper(theSettlementDetail);
		wrapper.FeeID = theSettlementDetail.Fee_Id__c;
		wrapper.FeeAmount = theSettlementDetail.Amount__c;
			
		EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, theSettlementDetail.Id);	
					
		theSettlementDetail.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';	
							
		return theResponse;
	}


	//////////////////   Update Payment Section


	//  Accepts a Payment Plan Item and updates all line item detail records for 
	//  that line item.
	@AuraEnabled
	public static List<EPPSHelperMethods.EPPSResponse> updatePaymentLineItemFees(ID theItemId)
	{
		List<Payment_Fee__c> theDetailItems = new List<Payment_Fee__c>();		

		theDetailItems = getFeePaymentDetailRecords(theItemId, theDetailItems);
		List<EPPSHelperMethods.EPPSResponse> theResponses = new List<EPPSHelperMethods.EPPSResponse>();
		for (Payment_Fee__c theDetailItem : theDetailItems)
		{
			EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
			wrapper = convertPaymentItemToFeeWrapper(theDetailItem);
			wrapper.FeeID = theDetailItem.Fee_Id__c;
			wrapper.FeeAmount = theDetailItem.Amount__c;
			
			EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, theDetailItem.Id);	
					
			theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
			theResponses.add(theResponse);
		}

		update theDetailItems;
		return theResponses;
	}


	//  Accepts a Payment detail Item Id and updates a singular fee.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse updatePaymentDetailFee(ID theDetailItemId)
	{
		Payment_Fee__c theDetailItem = new Payment_Fee__c(); 
		theDetailItem = getPaymentDetailRecord(theDetailItemId, theDetailItem);

		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertPaymentItemToFeeWrapper(theDetailItem);
		wrapper.FeeID = theDetailItem.Fee_Id__c;
		wrapper.FeeAmount = theDetailItem.Amount__c;
		
		EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, theDetailItemId);	
					
		theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
							
		return theResponse;
	}


	//  Accepts a Payment plan item ID and a string value for the fee type to be updated.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse updatePaymentDetailFeeByType(ID theItemId, string theType)
	{
		Payment_Fee__c thePaymentDetail = new Payment_Fee__c();		

		thePaymentDetail = getFeePaymentDetailRecordByType(theItemId, thePaymentDetail, theType);
		
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertPaymentItemToFeeWrapper(thePaymentDetail);
		wrapper.FeeID = thePaymentDetail.Fee_Id__c;
		wrapper.FeeAmount = thePaymentDetail.Amount__c;
			
		EPPSHelperMethods.EPPSResponse theResponse = updateFee(wrapper, thePaymentDetail.Id);	
					
		thePaymentDetail.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';	
							
		return theResponse;
	}


    public static EPPSHelperMethods.EPPSResponse updateFee(EPPSHelperMethods.Fee_Wrapper wrapper, Id recordId) 
	{        
		EPPSHelperMethods.EPPSResponse response = EPPSIntegrationMethodsEnhanced.updateFee2(wrapper);
		try
		{			
			if (response.success) 
			{
				IntegrationLogUtil.createLog(
				IntegrationLogUtil.logBuilder()
				.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
				.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
				.record(recordId)
				.method('updateFee')
				.request(response.SOAPRequestBody)
				.response(response.SOAPResponseBody)
				.httpCode(response.HTTPResponseCode)
				.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
				.build());
				IntegrationLogUtil.flush();
				return response;
			}
			else
			{
				IntegrationLogUtil.createLog(
				IntegrationLogUtil.logBuilder()
				.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
				.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
				.record(recordId)
				.method('updateFee')
				.request(response.SOAPRequestBody)
				.response(response.SOAPResponseBody)
				.httpCode(response.HTTPResponseCode)
				.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
				.build());
				IntegrationLogUtil.flush();
				return response;
			}
		}
		catch (Exception e)
		{
			IntegrationLogUtil.createLog(
			IntegrationLogUtil.logBuilder()
			.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
			.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
			.record(recordId)
			.method('updateFee')
			.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
			.status(IntegrationLogUtil.LogStatus.Failure)
			.build());
			IntegrationLogUtil.flush();
			return response;
		}
    }


	//////////////////   Void Settlement Section

	@AuraEnabled
	public static List<EPPSHelperMethods.EPPSResponse> voidSettlementLineItemFees(ID theItemId)
	{
		List<Settlement_Fee__c> theSettlementDetails = new List<Settlement_Fee__c>();

		theSettlementDetails = getFeeSettlementDetailRecords(theItemId, theSettlementDetails);

		List<EPPSHelperMethods.EPPSResponse> theResponses = new List<EPPSHelperMethods.EPPSResponse>();
		for (Settlement_Fee__c theSettlementDetail : theSettlementDetails)
		{
			EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
			wrapper = convertSettlementFeeItemToFeeWrapper(theSettlementDetail);
			wrapper.FeeID = theSettlementDetail.Fee_Id__c;
			
			EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, theSettlementDetail.Id);			
			theResponses.add(theResponse);
		}

		return theResponses;
	}

	//  Accepts a detail Item Id and updates a singular fee.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse voidSettlementDetailFee(ID theDetailItemId)
	{
		Settlement_Fee__c theDetailItem = new Settlement_Fee__c(); 
		theDetailItem = getSettlementPlanDetailRecord(theDetailItemId, theDetailItem);

		List<EPPSHelperMethods.EPPSResponse> theResponses = new List<EPPSHelperMethods.EPPSResponse>();

		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertSettlementFeeItemToFeeWrapper(theDetailItem);
		wrapper.FeeID = theDetailItem.Fee_Id__c;
		
		EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, theDetailItem.Id);			
		return theResponse;

	}


	//  Accepts a settlement plan item ID and a string value for the fee type to be updated.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse voidSettlementDetailFeeByType(ID theItemId, string theType)
	{
		Settlement_Fee__c theSettlementDetail = new Settlement_Fee__c();

		theSettlementDetail = getFeeSettlementDetailRecordByType(theItemId, theSettlementDetail, theType);
		
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertSettlementFeeItemToFeeWrapper(theSettlementDetail);
		wrapper.FeeID = theSettlementDetail.Fee_Id__c;
			
		EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, theSettlementDetail.Id);					
		return theResponse;
	}


	//////////////////   Void Payment Section

	//  Accepts a Payment Plan Item and updates all line item detail records for 
	//  that line item.
	@AuraEnabled
	public static List<EPPSHelperMethods.EPPSResponse> voidPaymentFees(ID theItemId)
	{
		List<Payment_Fee__c> theDetailItems = new List<Payment_Fee__c>();		

		theDetailItems = getFeePaymentDetailRecords(theItemId, theDetailItems);
		List<EPPSHelperMethods.EPPSResponse> theResponses = new List<EPPSHelperMethods.EPPSResponse>();
		for (Payment_Fee__c theDetailItem : theDetailItems)
		{
			EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
			wrapper = convertPaymentItemToFeeWrapper(theDetailItem);
			wrapper.FeeID = theDetailItem.Fee_Id__c;
			wrapper.FeeAmount = theDetailItem.Amount__c;
			
			EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, theDetailItem.Id);	
					
			theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
			theResponses.add(theResponse);
		}

		update theDetailItems;
		return theResponses;
	}


	//  Accepts a Payment detail Item Id and updates a singular fee.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse voidPaymentFee(ID theDetailItemId)
	{
		Payment_Fee__c theDetailItem = new Payment_Fee__c(); 
		theDetailItem = getPaymentDetailRecord(theDetailItemId, theDetailItem);

		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertPaymentItemToFeeWrapper(theDetailItem);
		wrapper.FeeID = theDetailItem.Fee_Id__c;
		wrapper.FeeAmount = theDetailItem.Amount__c;
		
		EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, theDetailItemId);	
					
		theDetailItem.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';
							
		return theResponse;
	}


	//  Accepts a Payment plan item ID and a string value for the fee type to be updated.
	@AuraEnabled
	public static EPPSHelperMethods.EPPSResponse voidPaymentFeeByType(ID theItemId, string theType)
	{
		Payment_Fee__c thePaymentDetail = new Payment_Fee__c();		

		thePaymentDetail = getFeePaymentDetailRecordByType(theItemId, thePaymentDetail, theType);
		
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
		wrapper = convertPaymentItemToFeeWrapper(thePaymentDetail);
		wrapper.FeeID = thePaymentDetail.Fee_Id__c;
		wrapper.FeeAmount = thePaymentDetail.Amount__c;
			
		EPPSHelperMethods.EPPSResponse theResponse = voidFee(wrapper, thePaymentDetail.Id);	
					
		thePaymentDetail.Status_Code__c = theResponse.Success ? 'Sent to EPPS' : 'Failed to EPPS';	
							
		return theResponse;
	}


    public static EPPSHelperMethods.EPPSResponse voidFee(EPPSHelperMethods.Fee_Wrapper wrapper, Id RecordId) 
	{
		EPPSHelperMethods.EPPSResponse response = EPPSIntegrationMethodsEnhanced.voidFee(wrapper);
		try
		{			
			if (response.success) 
			{
				IntegrationLogUtil.createLog(
				IntegrationLogUtil.logBuilder()
				.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
				.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
				.method('voidFee')
				.record(recordId)
				.request(response.SOAPRequestBody)
				.response(response.SOAPResponseBody)
				.httpCode(response.HTTPResponseCode)
				.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
				.build());
				IntegrationLogUtil.flush();
				return response;
			}
			else
			{
				IntegrationLogUtil.createLog(
				IntegrationLogUtil.logBuilder()
				.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
				.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
				.method('voidFee')
				.record(recordId)
				.request(response.SOAPRequestBody)
				.response(response.SOAPResponseBody)
				.httpCode(response.HTTPResponseCode)
				.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
				.build());
				IntegrationLogUtil.flush();
				return response;
			}
		}
		catch (Exception e)
		{
			IntegrationLogUtil.createLog(
			IntegrationLogUtil.logBuilder()
			.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
			.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
			.method('voidFee')
			.record(recordId)
			.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
			.status(IntegrationLogUtil.LogStatus.Failure)
			.build());
			IntegrationLogUtil.flush();
			return response;
		}
    }

	public static EPPSHelperMethods.Fee_Wrapper convertSettlementFeeItemToFeeWrapper(Settlement_Fee__c theItem)
	{
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();
								
		wrapper.AccountNumber =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c;
		wrapper.CardHolderID =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c;
		wrapper.ContactName =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;
		wrapper.PaidToCity =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c;
		wrapper.PaidToCustomerNumber =	theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c;
		wrapper.PaidToName =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;
		wrapper.PaidToState =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c;
		wrapper.PaidToStreet =			theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c;
		wrapper.PaidToZip =				theItem.Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c;		

		return wrapper;
	}

	public static EPPSHelperMethods.Fee_Wrapper convertPaymentItemToFeeWrapper(Payment_Fee__c theItem)
	{
		EPPSHelperMethods.Fee_Wrapper wrapper = new EPPSHelperMethods.Fee_Wrapper();

		wrapper.CardHolderID =			theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c;	
		wrapper.PaidToCustomerNumber =	theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c;
		wrapper.AccountNumber =			theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c;
		wrapper.PaidToStreet =			theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Street_Address__c;
		wrapper.PaidToCity =			theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.City__c;
		wrapper.PaidToState =			theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.State__c;
		wrapper.PaidToZip =				theItem.Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Zip_Code__c;

		//wrapper.ContactName =			theItem.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;
		//wrapper.PaidToName =			theItem.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name;

		return wrapper;
	}


	//  Returns all Settlement_Fee__c records related to a Settlement Plan Item
	//  theReocrdID = the Settlement Pan Item Record to get child records for.
	public static List<Settlement_Fee__c> getFeeSettlementDetailRecords(ID theRecordID, List<Settlement_Fee__c> theDetailRecords)
	{
		theDetailRecords = [SELECT Id, Amount__c,
							 Fee_Id__c, Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c,		
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c
							FROM Settlement_Fee__c
							WHERE Settlement_Plan_Item__c =: theRecordID];

		return theDetailRecords;
	}

	public static Settlement_Fee__c getFeeSettlementDetailRecordByType(ID theRecordID, Settlement_Fee__c theDetailRecord, string theType)
	{
		theDetailRecord = [SELECT Id,
							Amount__c,
							Fee_Id__c,
							Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c,		
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c
							FROM Settlement_Fee__c
							WHERE Settlement_Plan_Item__c =: theRecordID AND Type__C =: theType];

		return theDetailRecord;
	}

	public static Settlement_Fee__c getSettlementPlanDetailRecord(ID theRecordId, Settlement_Fee__c theDetailRecord)
	{
		theDetailRecord = [SELECT Id,
							Amount__c,
							Fee_Id__c,
							Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c,		
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c,
							Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c
							FROM Settlement_Fee__c
							WHERE Id =: theRecordID];

		return theDetailRecord;
	}

	//  Returns all Fee_Payment_Detail__c records related to a Settlement Plan Item
	//  theReocrdID = the Settlement Pan Item Record to get child records for.
	public static List<Payment_Fee__c> getFeePaymentDetailRecords(ID theRecordID, List<Payment_Fee__c> theDetailRecords)
	{
		theDetailRecords = [SELECT Id,
							Amount__c,
							Fee_Id__c,
							Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.AccountId,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Routing__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account_Type__c 
							FROM Payment_Fee__c
							WHERE Payment_Schedule_Item__c =: theRecordID];

		return theDetailRecords;
	}



	public static Payment_Fee__c getFeePaymentDetailRecordByType(ID theRecordID, Payment_Fee__c theDetailRecord, string theType)
	{
		theDetailRecord = [SELECT Id,
							Amount__c,
							Fee_Id__c,
							Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.AccountId,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Routing__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account_Type__c 
							FROM Payment_Fee__c
							WHERE Payment_Schedule_Item__c =: theRecordID AND Type__C =: theType];

		return theDetailRecord;
	}


	public static Payment_Fee__c getPaymentDetailRecord(ID theRecordId, Payment_Fee__c theDetailRecord)
	{
		theDetailRecord = [SELECT Id,
							Amount__c,
							Fee_Id__c,
							Name,
							Status_Code__c,
							Transaction_Id__c,
							Type__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.AccountId,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Routing__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c,
							Payment_Schedule_Item__r.Payment_Plan__r.Opportunity__r.Account.Bank_Account_Type__c 
							FROM Payment_Fee__c
							WHERE Id =: theRecordID];

		return theDetailRecord;
	}
}