@isTest
public class EmailMessageTriggerHandlerTest {
    
    @isTest
    static void testHandleAfterInsert_IncomingEmail() {
        // Create test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Test incoming email
        Test.startTest();
        
        EmailMessage incomingEmail = new EmailMessage(
            Subject = 'Test Incoming Email',
            TextBody = 'This is a test email',
            FromAddress = 'sender@example.com',
            ToAddress = 'test@example.com',
            Incoming = true,
            RelatedToId = testAccount.Id
        );
        
        insert incomingEmail;
        
        Test.stopTest();
        
        // Verify the email was created
        EmailMessage insertedEmail = [SELECT Id, Subject, Incoming FROM EmailMessage WHERE Id = :incomingEmail.Id];
        System.assertEquals('Test Incoming Email', insertedEmail.Subject);
        System.assertEquals(true, insertedEmail.Incoming);
    }
    
    @isTest
    static void testHandleAfterInsert_OutgoingEmail() {
        // Create test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Test outgoing email (should not trigger Platform Event)
        Test.startTest();
        
        EmailMessage outgoingEmail = new EmailMessage(
            Subject = 'Test Outgoing Email',
            TextBody = 'This is a test outgoing email',
            FromAddress = 'test@example.com',
            ToAddress = 'recipient@example.com',
            Incoming = false,
            RelatedToId = testAccount.Id
        );
        
        insert outgoingEmail;
        
        Test.stopTest();
        
        // Verify the email was created
        EmailMessage insertedEmail = [SELECT Id, Subject, Incoming FROM EmailMessage WHERE Id = :outgoingEmail.Id];
        System.assertEquals('Test Outgoing Email', insertedEmail.Subject);
        System.assertEquals(false, insertedEmail.Incoming);
    }
}