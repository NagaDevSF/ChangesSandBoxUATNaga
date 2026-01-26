@isTest
private class InboundEmailHandlerTest {

    @testSetup
    static void setup() {
        // Insert a test Lead
        Lead testLead = new Lead(FirstName = 'Test', LastName = 'User', Company = 'Test Co');
        insert testLead;

        // Insert default Automation Settings (Name__c = 'Default')
        Automation_Settings__c settings = new Automation_Settings__c(
            Name__c = 'Default',
            Activate_Automations__c = true
        );
        insert settings;
    }

    @isTest
    static void testHandleInboundEmail_WithAutomationsEnabled() {
        // Ensure automations are ON
        Automation_Settings__c settings = [SELECT Id, Activate_Automations__c FROM Automation_Settings__c WHERE Name__c = 'Default' LIMIT 1];
        settings.Activate_Automations__c = true;
        update settings;

        // Get test Lead
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];

        // Simulate inbound email with Lead Id in subject
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        email.subject = 'Re: Inquiry about product ' + testLead.Id;
        email.fromAddress = 'test@example.com';
        email.toAddresses = new String[] { 'sales@example.com' };
        email.plainTextBody = 'This is a plain text body.';
        email.htmlBody = '<p>This is the HTML version</p>';

        // --- Add Binary Attachment ---
        Messaging.InboundEmail.BinaryAttachment binaryAtt = new Messaging.InboundEmail.BinaryAttachment();
        binaryAtt.fileName = 'testBinary.pdf';
        binaryAtt.body = Blob.valueOf('Binary file content');
        email.binaryAttachments = new Messaging.InboundEmail.BinaryAttachment[] { binaryAtt };

        // --- Add Text Attachment ---
        Messaging.InboundEmail.TextAttachment textAtt = new Messaging.InboundEmail.TextAttachment();
        textAtt.fileName = 'testText.txt';
        textAtt.body = 'This is a text attachment';
        email.textAttachments = new Messaging.InboundEmail.TextAttachment[] { textAtt };

        // Execute test
        Test.startTest();
        InboundEmailHandler handler = new InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();


        // Verify EmailMessage inserted
        List<EmailMessage> messages = [SELECT Id, Subject FROM EmailMessage WHERE Lead__c = :testLead.Id];

        // Verify Attachments created
        List<Attachment> atts = [SELECT Id, Name, ParentId FROM Attachment WHERE ParentId = :messages[0].Id];
    }

    @isTest
    static void testHandleInboundEmail_WithAutomationsDisabled() {
        // Turn automations OFF
        Automation_Settings__c settings = [SELECT Id, Activate_Automations__c FROM Automation_Settings__c WHERE Name__c = 'Default' LIMIT 1];
        settings.Activate_Automations__c = false;
        update settings;

        // Get test Lead
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];

        // Simulate inbound email with Lead Id in subject
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        email.subject = 'Re: Inquiry ' + testLead.Id;
        email.fromAddress = 'test@example.com';
        email.toAddresses = new String[] { 'sales@example.com' };
        email.plainTextBody = 'Body when automation is off';

        Test.startTest();
        InboundEmailHandler handler = new InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();
    }

    @isTest
    static void testHandleInboundEmail_NoLeadInSubject() {
        // Automations ON
        Automation_Settings__c settings = [SELECT Id, Activate_Automations__c FROM Automation_Settings__c WHERE Name__c = 'Default' LIMIT 1];
        settings.Activate_Automations__c = true;
        update settings;

        // Email without Lead Id in subject
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope envelope = new Messaging.InboundEnvelope();
        email.subject = 'No lead id here';
        email.fromAddress = 'nolead@example.com';
        email.plainTextBody = 'Email without Lead ID';

        Test.startTest();
        InboundEmailHandler handler = new InboundEmailHandler();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, envelope);
        Test.stopTest();
    }
}