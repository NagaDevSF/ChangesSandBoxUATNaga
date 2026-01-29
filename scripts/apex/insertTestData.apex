// Insert Test Data Script - Creates 2 Account/Contact/Opportunity records
// NOTE: Does NOT update any EPPS fields

// ============================================
// RECORD SET 1: John Smith - DCG MOD Program
// ============================================
Account acc1 = new Account(
    Name = 'Smith Family Trust'
);
insert acc1;
System.debug('Created Account 1: ' + acc1.Id);

Contact con1 = new Contact(
    FirstName = 'John',
    LastName = 'Smith',
    AccountId = acc1.Id,
    Email = 'john.smith@testmail.com',
    Phone = '555-123-4567'
);
insert con1;
System.debug('Created Contact 1: ' + con1.Id);

Opportunity opp1 = new Opportunity(
    Name = 'Smith - Debt Settlement',
    AccountId = acc1.Id,
    StageName = 'Prospecting',
    CloseDate = Date.today().addDays(30),
    Estimated_Total_Debt__c = 45000,
    Estimated_Current_Payment__c = 1200,
    Program_Type__c = 'DCG MOD',
    Number_of_Weeks__c = 156,
    First_Draft_Date__c = Date.today().addDays(14),
    Est_Settlement__c = '43%',
    Setup_Fee_Term__c = '10',
    No_Fee_Program__c = false
);
insert opp1;
System.debug('Created Opportunity 1: ' + opp1.Id);

// ============================================
// RECORD SET 2: Sarah Johnson - DCG DEBT Program
// ============================================
Account acc2 = new Account(
    Name = 'Johnson Household'
);
insert acc2;
System.debug('Created Account 2: ' + acc2.Id);

Contact con2 = new Contact(
    FirstName = 'Sarah',
    LastName = 'Johnson',
    AccountId = acc2.Id,
    Email = 'sarah.johnson@testmail.com',
    Phone = '555-987-6543'
);
insert con2;
System.debug('Created Contact 2: ' + con2.Id);

Opportunity opp2 = new Opportunity(
    Name = 'Johnson - Debt Settlement',
    AccountId = acc2.Id,
    StageName = 'Qualification',
    CloseDate = Date.today().addDays(45),
    Estimated_Total_Debt__c = 72000,
    Estimated_Current_Payment__c = 2100,
    Program_Type__c = 'DCG DEBT',
    Number_of_Weeks__c = 208,
    First_Draft_Date__c = Date.today().addDays(7),
    Est_Settlement__c = '60%',
    Setup_Fee_Term__c = '8',
    No_Fee_Program__c = false
);
insert opp2;
System.debug('Created Opportunity 2: ' + opp2.Id);

// ============================================
// SUMMARY OUTPUT
// ============================================
System.debug('========== TEST DATA CREATED SUCCESSFULLY ==========');
System.debug('Record Set 1:');
System.debug('  Account: ' + acc1.Name + ' (Id: ' + acc1.Id + ')');
System.debug('  Contact: ' + con1.FirstName + ' ' + con1.LastName + ' (Id: ' + con1.Id + ')');
System.debug('  Opportunity: ' + opp1.Name + ' (Id: ' + opp1.Id + ')');
System.debug('');
System.debug('Record Set 2:');
System.debug('  Account: ' + acc2.Name + ' (Id: ' + acc2.Id + ')');
System.debug('  Contact: ' + con2.FirstName + ' ' + con2.LastName + ' (Id: ' + con2.Id + ')');
System.debug('  Opportunity: ' + opp2.Name + ' (Id: ' + opp2.Id + ')');
System.debug('====================================================');
