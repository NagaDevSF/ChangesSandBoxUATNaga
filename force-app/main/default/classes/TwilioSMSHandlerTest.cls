@IsTest
private class TwilioSMSHandlerTest {

    @TestSetup
    static void setupData() {
        // Create a lead that can be matched
        Lead l1 = new Lead(FirstName = 'Test', LastName = 'Lead', Company = 'TestCo', Phone = '123-456-7890', MobilePhone = '987-654-3210', DoNotCall = false);
        insert l1;

        // Create a lead that won't match
        Lead l2 = new Lead(FirstName = 'NoMatch', LastName = 'Lead', Company = 'TestCo', Phone = '111-222-3333', MobilePhone = '444-555-6666', DoNotCall = false);
        insert l2;

        // Setup automation settings
        Automation_Settings__c settings = Automation_Settings__c.getInstance();
        if (settings == null) {
            settings = new Automation_Settings__c(Name__c = 'Default');
        }
        settings.Name__c = 'Default';
        settings.Activate_Automations__c = true;
        upsert settings;
    }

    @IsTest
    static void testAutomationDisabled() {
        // Disable automation
        Automation_Settings__c settings = Automation_Settings__c.getInstance();
        settings.Activate_Automations__c = false;
        update settings;

        // Mock a REST request
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/TwilioSMS/';
        RestContext.request = req;
        RestContext.response = res;

        TwilioSMSHandler.receiveInboundSMS();
    }

    @IsTest
    static void testBlankBody() {
        Automation_Settings__c.getInstance().Activate_Automations__c = true;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/TwilioSMS/';
        req.params.put('From', '1234567890');
        req.params.put('Body', '');
        RestContext.request = req;
        RestContext.response = res;

        TwilioSMSHandler.receiveInboundSMS();
    }

    @IsTest
    static void testStopCommandUpdatesLead() {
        Automation_Settings__c.getInstance().Activate_Automations__c = true;

        // Pick lead created in setup
        Lead testLead = [SELECT Id, DoNotCall, Phone FROM Lead WHERE FirstName='Test' LIMIT 1];

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/TwilioSMS/';
        req.params.put('From', '123-456-7890'); // Matches the first lead
        req.params.put('Body', 'STOP');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        TwilioSMSHandler.receiveInboundSMS();
        Test.stopTest();

        // Verify lead is updated
        testLead = [SELECT DoNotCall FROM Lead WHERE Id = :testLead.Id];
    }

    @IsTest
    static void testNonStopCommandUpdatesLead() {
        Automation_Settings__c.getInstance().Activate_Automations__c = true;

        // Pick lead created in setup
        Lead testLead = [SELECT Id, DoNotCall, Phone FROM Lead WHERE FirstName='Test' LIMIT 1];

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/TwilioSMS/';
        req.params.put('From', '123-456-7890'); // Matches the first lead
        req.params.put('Body', 'Hello');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        TwilioSMSHandler.receiveInboundSMS();
        Test.stopTest();

        // Verify lead is updated but DoNotCall remains false
        testLead = [SELECT DoNotCall FROM Lead WHERE Id = :testLead.Id];
    }

    @IsTest
    static void testShortPhoneNumberDoesNotUpdateLead() {
        Automation_Settings__c.getInstance().Activate_Automations__c = true;

        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.httpMethod = 'POST';
        req.requestUri = '/services/apexrest/TwilioSMS/';
        req.params.put('From', '123'); // Too short
        req.params.put('Body', 'STOP');
        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        TwilioSMSHandler.receiveInboundSMS();
        Test.stopTest();
    }
}