@isTest(SeeAllData=true)
public class BankVerificationFilesTriggerTest {

    @isTest
    public static void testFiletoAccount() {
        
        Account oAccount = new Account(Name = 'Test Account');
        insert oAccount;
        
        bankconnect__Bank_Verification__c oBankVerification = new bankconnect__Bank_Verification__c(
            bankconnect__Account__c = oAccount.Id,
            bankconnect__Email__c = 'test@test.com',
            bankconnect__First_Name__c = 'Marisol',
            bankconnect__Last_Name__c = 'Testcase',
            bankconnect__Plaid_Products__c = 'Assets' 
        );
        insert oBankVerification;
        
        ContentVersion oContentVersion = new ContentVersion(
            Title = 'Asset_Report',
            PathOnClient = '/Asset_Report.pdf',
            VersionData = Blob.valueOf('dummy content'),
            FirstPublishLocationId = oBankVerification.Id
        );

        Test.startTest();
        insert oContentVersion;  
        Test.stopTest();

    }
}