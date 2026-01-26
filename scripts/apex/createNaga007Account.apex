// Anonymous Apex script to create Account 'naga007' with Contact and Opportunity
// Execute using: SFDX: Execute Anonymous Apex with Editor Contents

// ==========================================
// 1. CREATE ACCOUNT - naga007
// ==========================================
Account acc = new Account();
acc.Name = 'naga007';

// Banking Information
acc.Routing__c = '123123123';
acc.Bank_Account__c = '123456';
acc.Bank_Account_Type__c = 'Checking'; // Common types: Checking, Savings

// Billing Address
acc.BillingStreet = '123 Main Street';
acc.BillingCity = 'Los Angeles';
acc.BillingState = 'CA';
acc.BillingPostalCode = '90001';
acc.BillingCountry = 'USA';

// Phone
acc.Phone = '555-123-4567';

insert acc;
System.debug('Account created: ' + acc.Id + ' - Name: ' + acc.Name);

// ==========================================
// 2. CREATE CONTACT linked to Account
// ==========================================
Contact con = new Contact();
con.FirstName = 'Naga';
con.LastName = '007';
con.AccountId = acc.Id;
con.Email = 'naga007@example.com';
con.Phone = '555-123-4567';
con.MailingStreet = '123 Main Street';
con.MailingCity = 'Los Angeles';
con.MailingState = 'CA';
con.MailingPostalCode = '90001';
con.MailingCountry = 'USA';

insert con;
System.debug('Contact created: ' + con.Id + ' - Name: ' + con.FirstName + ' ' + con.LastName);

// ==========================================
// 3. CREATE OPPORTUNITY linked to Account
// ==========================================
Opportunity opp = new Opportunity();
opp.Name = 'naga007 - Debt Settlement';
opp.AccountId = acc.Id;
opp.ContactId = con.Id;
opp.StageName = 'Prospecting';
opp.CloseDate = Date.today().addDays(30);

// If you need to add banking info directly on Opportunity (if fields exist)
// opp.Routing_Number__c = '123123123';
// opp.Bank_Account_Number__c = '123456';

insert opp;
System.debug('Opportunity created: ' + opp.Id + ' - Name: ' + opp.Name);

// ==========================================
// OUTPUT SUMMARY
// ==========================================
System.debug('===========================================');
System.debug('CREATION SUMMARY:');
System.debug('Account ID: ' + acc.Id);
System.debug('Account Name: ' + acc.Name);
System.debug('Routing Number: ' + acc.Routing__c);
System.debug('Bank Account Number: ' + acc.Bank_Account__c);
System.debug('Bank Account Type: ' + acc.Bank_Account_Type__c);
System.debug('Billing Address: ' + acc.BillingStreet + ', ' + acc.BillingCity + ', ' + acc.BillingState + ' ' + acc.BillingPostalCode);
System.debug('Contact ID: ' + con.Id);
System.debug('Contact Name: ' + con.FirstName + ' ' + con.LastName);
System.debug('Opportunity ID: ' + opp.Id);
System.debug('Opportunity Name: ' + opp.Name);
System.debug('===========================================');
