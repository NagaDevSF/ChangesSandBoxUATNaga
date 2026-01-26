// Anonymous Apex script to update ALL fields on Account, Contact, and Opportunity for naga007
// Execute using: SFDX: Execute Anonymous Apex with Editor Contents

// ==========================================
// QUERY EXISTING RECORDS
// ==========================================
Account acc = [SELECT Id, Name FROM Account WHERE Name = 'naga007' LIMIT 1];
Contact con = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
Opportunity opp = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id LIMIT 1];

System.debug('Updating records for Account: ' + acc.Id);

// ==========================================
// UPDATE ACCOUNT - ALL FIELDS
// ==========================================

// Basic Info
acc.Name = 'naga007';
acc.Type = 'Customer';
acc.Phone = '555-123-4567';
acc.Website = 'https://naga007.example.com';
acc.Industry = 'Technology';
acc.Description = 'Naga007 Test Account - Full field population for testing purposes';
acc.NumberOfEmployees = 50;
acc.AccountSource = 'Web';

// Billing Address
acc.BillingStreet = '123 Main Street, Suite 100';
acc.BillingCity = 'Los Angeles';
acc.BillingState = 'CA';
acc.BillingPostalCode = '90001';
acc.BillingCountry = 'USA';

// Shipping Address
acc.ShippingStreet = '123 Main Street, Suite 100';
acc.ShippingCity = 'Los Angeles';
acc.ShippingState = 'CA';
acc.ShippingPostalCode = '90001';
acc.ShippingCountry = 'USA';

// Banking Information
acc.Routing__c = '123123123';
acc.Bank_Account__c = '123456';
acc.Bank_Account_Type__c = 'Checking';
acc.Bank_Name__c = 'First National Bank';
acc.Bank_Phone__c = '555-999-8888';
acc.Bank_Street_Address__c = '456 Banking Avenue';
acc.City__c = 'Los Angeles';
acc.State__c = 'California';
acc.Zip_Code__c = '90002';
acc.Payment_Type__c = 'ACH';

// Authorized Account Holder Information
acc.Account_Holder_Name__c = 'Naga';
acc.Account_Holder_Last_Name__c = 'Kumar';
acc.Acct_Street_Address__c = '123 Main Street';
acc.Acct_Phone__c = '555-123-4567';
acc.City1__c = 'Los Angeles';
acc.State1__c = 'California';
acc.Zip_Code1__c = '90001';

// Credit Card Info (if applicable)
acc.Name_on_CC__c = 'Naga Kumar';
acc.CC_Type__c = 'Visa';
acc.CC_Acct_Number__c = '4111111111111111';
acc.CC_Expiration__c = '12/2028';
acc.CVV__c = '123';

// Business Information
acc.EIN_Employer_Identification_Number__c = '99-0070007';
acc.Type_of_Business__c = 'Technologies';
acc.Start_of_Business__c = Date.newInstance(2020, 1, 15);
acc.Monthly_Revenue__c = 50000;
acc.Gross_Profit_Margin__c = 15000;
acc.Net_Profit_or_Loss__c = 10000;
acc.Number_of_Owners__c = 2;

// Personal Info
acc.First_Name__c = 'Naga';
acc.Last_Name__c = 'Kumar';
acc.Email__c = 'naga007@example.com';
acc.Date_of_Birth__c = '1985-06-15';
acc.Phone_2__c = '555-222-3333';
acc.Phone_3__c = '555-444-5555';

// Notes
acc.Quick_Notes__c = 'VIP Customer - Full service account';
acc.File_Notes__c = 'All documentation verified and complete';
acc.Hardship__c = 'No current hardship reported';
acc.Details_Book__c = 'Customer since 2020, excellent payment history';

// Source Information
acc.Source_origin__c = 'Direct Website';
acc.Source_origin_ID__c = 'WEB-2024-001';
acc.Leadtrac_File_ID__c = 'LT-NAGA-007';
acc.EPPS_ID__c = 'EPPS-007';

update acc;
System.debug('Account updated successfully: ' + acc.Id);

// ==========================================
// UPDATE CONTACT - ALL FIELDS
// ==========================================

// Name Fields
con.Salutation = 'Mr.';
con.FirstName = 'Naga';
con.MiddleName = 'K';
con.LastName = 'Kumar';
con.Suffix = 'Jr.';

// Contact Info
con.Email = 'naga007@example.com';
con.Phone = '555-123-4567';
con.MobilePhone = '555-987-6543';
con.HomePhone = '555-111-2222';
con.Fax = '555-333-4444';

// Professional Info
con.Title = 'Chief Executive Officer';
con.Department = 'Executive';
con.Birthdate = Date.newInstance(1985, 6, 15);

// Mailing Address
con.MailingStreet = '123 Main Street, Suite 100';
con.MailingCity = 'Los Angeles';
con.MailingState = 'CA';
con.MailingPostalCode = '90001';
con.MailingCountry = 'USA';

// Additional Phones
con.Phone_2__c = '555-222-3333';
con.Phone_3__c = '555-444-5555';
con.Name_2__c = 'Naga Kumar (Alternate)';
con.Owner_s_SSN__c = '123456789';

// Address and Notes from Pipedrive
con.Address_From_Pipe_drive__c = '123 Main Street, Los Angeles, CA 90001';
con.Phone_Book_Pipedrive__c = 'Primary: 555-123-4567, Mobile: 555-987-6543';
con.Email_book_Pipedrive__c = 'naga007@example.com, naga.kumar@business.com';

// Marketing Fields
con.gclid__c = 'CjwKCAtest123';
con.Leadtrac_File_ID__c = 'LT-NAGA-007';
con.Type__c = 'Contact';

// SMS Fields
con.SMS_Status__c = 'Sent';
con.SMS_Message_Name__c = 'Welcome Message';
con.SMS_Message__c = 'Welcome to our service!';

update con;
System.debug('Contact updated successfully: ' + con.Id);

// ==========================================
// UPDATE OPPORTUNITY - ALL FIELDS
// ==========================================

// Basic Info
opp.Name = 'naga007 - Debt Settlement Program';
opp.Description = 'Comprehensive debt settlement program for Naga Kumar. Full service package with payment plan.';
opp.StageName = 'Qualification';
opp.Type = 'New Business';
opp.CloseDate = Date.today().addDays(45);
opp.Amount = 75000;
opp.Probability = 50;
opp.NextStep = 'Document Review and Contract Signing';
opp.LeadSource = 'Web';
opp.ForecastCategoryName = 'Pipeline';

// Contact Info on Opportunity
opp.Contact_Name__c = 'Naga Kumar';
opp.First_Name__c = 'Naga';
opp.Middle_name__c = 'K';
opp.Last_name__c = 'Kumar';
opp.Email__c = 'naga007@example.com';
opp.Phone__c = '555-123-4567';
opp.Mobile__c = '555-987-6543';
opp.Phone_2__c = '555-222-3333';
opp.Phone_3__c = '555-444-5555';

// Debt Information
opp.Estimated_Total_Debt__c = 75000;
opp.Estimated_Current_Payment__c = 2500;
opp.Est_weekly_payment__c = 625;
opp.Desired_Weekly_Payment__c = 500;
opp.Quiz_Quote__c = 45000;
opp.Number_of_Weeks__c = 96;
opp.First_Draft_Date__c = Date.today().addDays(14);

// Payment & Program Settings
opp.Payment_Frequency__c = 'Weekly';
opp.Est_Settlement__c = '43%';
opp.Program_Fee__c = '25%';
opp.Banking_Fee__c = 9.95;
opp.No_Fee_Program__c = false;
opp.Retainer_Fee_Term__c = '6';
opp.Setup_Fee_Term__c = '10';

// Debt Types
opp.Personal_Consumer_Debt__c = 'Personal Consumer Debt';
opp.Personal_Consumer_Debt2__c = true;
opp.Medical_Debt__c = false;
opp.Tax_Debt__c = false;
opp.Funding__c = false;

// Business Info (if applicable)
opp.Business_Type__c = 'LLC';
opp.Business_DBA_Name__c = 'N/A';
opp.Tier__c = 'Tier 1';

// Status Fields
opp.Doc_Submission_Status__c = 'Pending';
opp.Pre_Deal_Status__c = 'NEW LEAD';
opp.Client_Status__c = 'Approved Send Contract';
opp.Client_Status_BO__c = 'No Fee Program';
opp.Progress__c = '1';
opp.Docs_received__c = false;
opp.Nurturing__c = false;
opp.Lost__c = false;

// Marketing & Tracking
opp.Main_Source__c = 'Website';
opp.Campaign_Brand__c = 'Debt Consultants Group';
opp.utm_source__c = 'google';
opp.utm_medium__c = 'cpc';
opp.utm_campaign__c = 'debt_settlement_2024';
opp.utm_content__c = 'landing_page_a';
opp.utm_term__c = 'debt relief';
opp.gclid__c = 'CjwKCAtest123';
opp.Time_Zone__c = 'PST';

// Integration Fields
opp.Leadtrac_File_ID__c = 'LT-NAGA-007';
opp.EPPS_ID__c = 'EPPS-007';
opp.Integration_Assignement__c = 'ZAP Everyday';
opp.Lead_Created_Date_Tiem__c = Datetime.now();

// Notes
opp.Quick_Notes__c = 'Priority client - expedite processing. All documents submitted and verified.';

// SMS Flags
opp.SMS_Sent_Contract_Signed__c = false;
opp.Send_SMS_Enrolled__c = true;
opp.Contract_SIgned_to_Cases__c = false;

// Budget/Discovery Flags
opp.Budget_Confirmed__c = true;
opp.Discovery_Completed__c = true;
opp.ROI_Analysis_Completed__c = false;

update opp;
System.debug('Opportunity updated successfully: ' + opp.Id);

// ==========================================
// OUTPUT SUMMARY
// ==========================================
System.debug('===========================================');
System.debug('UPDATE SUMMARY - ALL FIELDS POPULATED:');
System.debug('===========================================');
System.debug('ACCOUNT: ' + acc.Id);
System.debug('  - Name: ' + acc.Name);
System.debug('  - Routing: ' + acc.Routing__c);
System.debug('  - Bank Account: ' + acc.Bank_Account__c);
System.debug('  - Bank Type: ' + acc.Bank_Account_Type__c);
System.debug('  - Account Holder: ' + acc.Account_Holder_Name__c + ' ' + acc.Account_Holder_Last_Name__c);
System.debug('  - Billing: ' + acc.BillingStreet + ', ' + acc.BillingCity + ', ' + acc.BillingState + ' ' + acc.BillingPostalCode);
System.debug('  - Phone: ' + acc.Phone);
System.debug('  - Email: ' + acc.Email__c);
System.debug('===========================================');
System.debug('CONTACT: ' + con.Id);
System.debug('  - Name: ' + con.Salutation + ' ' + con.FirstName + ' ' + con.MiddleName + ' ' + con.LastName + ' ' + con.Suffix);
System.debug('  - Email: ' + con.Email);
System.debug('  - Phone: ' + con.Phone);
System.debug('  - Mobile: ' + con.MobilePhone);
System.debug('  - Title: ' + con.Title);
System.debug('===========================================');
System.debug('OPPORTUNITY: ' + opp.Id);
System.debug('  - Name: ' + opp.Name);
System.debug('  - Stage: ' + opp.StageName);
System.debug('  - Total Debt: $' + opp.Estimated_Total_Debt__c);
System.debug('  - Weekly Payment: $' + opp.Est_weekly_payment__c);
System.debug('  - Payment Frequency: ' + opp.Payment_Frequency__c);
System.debug('  - Close Date: ' + opp.CloseDate);
System.debug('===========================================');
