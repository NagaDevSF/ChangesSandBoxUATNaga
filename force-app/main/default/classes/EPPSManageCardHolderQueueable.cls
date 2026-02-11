/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSManageCardHolderQueueable
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class is manages the add/update Cardholder to EPPS API call
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSManageCardHolderQueueable implements Queueable, Database.AllowsCallouts {

	@TestVisible
	private static Boolean FORCE_EXCEPTION_IN_EXECUTE = false;

    List<EPPSHelperMethods.Cardholder_Wrapper> WrapperList;
    
    public EPPSManageCardHolderQueueable(List<EPPSHelperMethods.Cardholder_Wrapper> theWrapperList) {
        WrapperList = theWrapperList;
    }
    
    public void execute(QueueableContext context) {
        
        if (WrapperList != null && WrapperList.isEmpty() == false) {
            List<Account> acctUpdates = new List<Account>();
            
            for (EPPSHelperMethods.Cardholder_Wrapper theWrapper : WrapperList) {
                
                try {

					if (FORCE_EXCEPTION_IN_EXECUTE) {
						throw new CalloutException('Forced batch exception for test');
					}

                    EPPSHelperMethods.EPPSResponse theResponse;
                    
                    switch on theWrapper.Operation {
                        when EPPS_ADD_CARDHOLDER {
                        	theResponse = EPPSIntegrationMethodsEnhanced.addCardholder(theWrapper);    
                        }
                        when EPPS_UPDATE_CARDHOLDER {
                       		 theResponse = EPPSIntegrationMethodsEnhanced.updateCardholder(theWrapper);     
						}
                    }   
                    
                    if (theResponse.Success) {
                        acctUpdates.add(new Account(Id = theWrapper.RecordID, EPPS_Integration_Status__c = EPPSHelperMethods.EPPS_INT_STATUS_SUCCESS,
                                                    Last_EPPS_Integration__c = DateTime.now(), EPPS_ID__c = theWrapper.CardHolderID));    
                    } else {
                        acctUpdates.add(new Account(Id = theWrapper.RecordID, EPPS_Integration_Status__c = EPPSHelperMethods.EPPS_INT_STATUS_FAILED,
                                                    Last_EPPS_Integration__c = DateTime.now()));  
                    }
                    
                    IntegrationLogUtil.createLog(
                        IntegrationLogUtil.logBuilder()
                        .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        .objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
                        .record(theWrapper.RecordID)
                        .method(String.valueOf(theWrapper.Operation))
                        .request(theResponse.SOAPRequestBody)
                        .response(theResponse.SOAPResponseBody)
                        .httpCode(theResponse.HTTPResponseCode)
                        .exceptionMsg(theResponse.LastError)
                        .status(theResponse.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure) 
                        .build()
                    );
                } catch(Exception e) {
                    IntegrationLogUtil.createLog(
                        IntegrationLogUtil.logBuilder()
                        .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        .objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
                        .record(theWrapper.RecordID)
                        .method(String.valueOf(theWrapper.Operation))
                        .exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
                        .status(IntegrationLogUtil.LogStatus.Failure) 
                        .build()
                    );
                    
                    acctUpdates.add(new Account(Id = theWrapper.RecordID, EPPS_Integration_Status__c = EPPSHelperMethods.EPPS_INT_STATUS_FAILED,
                                                Last_EPPS_Integration__c = DateTime.now()));  
                }
            }
            
            IntegrationLogUtil.flush();
            // TODO trap exceptions here?
            Database.update(acctUpdates);
        }
    }
}