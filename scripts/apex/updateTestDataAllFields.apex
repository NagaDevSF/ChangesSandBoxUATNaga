// Update Test Data Script - Updates ALL writable fields on Account, Contact, Opportunity
// NOTE: Does NOT update any EPPS fields as requested
// NOTE: Skips formula fields (not writable)

// Get the records we created
Account acc1 = [SELECT Id FROM Account WHERE Name = 'Smith Family Trust' LIMIT 1];
Account acc2 = [SELECT Id FROM Account WHERE Name = 'Johnson Household' LIMIT 1];
Contact con1 = [SELECT Id FROM Contact WHERE Email = 'john.smith@testmail.com' LIMIT 1];
Contact con2 = [SELECT Id FROM Contact WHERE Email = 'sarah.johnson@testmail.com' LIMIT 1];
Opportunity opp1 = [SELECT Id FROM Opportunity WHERE Name = 'Smith - Debt Settlement' LIMIT 1];
Opportunity opp2 = [SELECT Id FROM Opportunity WHERE Name = 'Johnson - Debt Settlement' LIMIT 1];

// ============================================
// UPDATE ACCOUNT 1: Smith Family Trust
// ============================================
acc1.Name = 'Smith Family Trust';
acc1.Type = 'Customer';
acc1.BillingStreet = '123 Main Street';
acc1.BillingCity = 'Austin';
acc1.BillingState = 'TX';
acc1.BillingPostalCode = '78701';
acc1.BillingCountry = 'USA';
acc1.BillingLatitude = 30.2672;
acc1.BillingLongitude = -97.7431;
acc1.ShippingStreet = '123 Main Street';
acc1.ShippingCity = 'Austin';
acc1.ShippingState = 'TX';
acc1.ShippingPostalCode = '78701';
acc1.ShippingCountry = 'USA';
acc1.ShippingLatitude = 30.2672;
acc1.ShippingLongitude = -97.7431;
acc1.Phone = '512-555-1234';
acc1.Website = 'https://smithfamilytrust.example.com';
acc1.Industry = 'Other';
acc1.NumberOfEmployees = 2;
acc1.Description = 'Smith Family Trust - Debt Settlement Client';
acc1.EIN_Employer_Identification_Number__c = '99-8877661';
acc1.Type_of_Business__c = 'Financial Services';
acc1.Quick_Notes__c = 'Client enrolled in DCG MOD program. Good communication.';
acc1.UCC_Exposure__c = 'None';
acc1.File_Notes__c = 'Initial consultation completed. All documents received.';
acc1.Number_of_Owners__c = 1;
acc1.Start_of_Business__c = Date.newInstance(2015, 3, 15);
acc1.Monthly_Revenue__c = 8500;
acc1.Gross_Profit_Margin__c = 3200;
acc1.Net_Profit_or_Loss__c = 1800;
acc1.Hardship__c = 'Job loss during pandemic, reduced income.';
acc1.Source_origin__c = 'Web';
acc1.Source_origin_ID__c = 'WEB-2024-001';
acc1.Bank_Name__c = 'Chase Bank';
acc1.Bank_Account_Type__c = 'Checking';
acc1.Routing__c = '021000021';
acc1.Bank_Account__c = '123456789012';
acc1.Bank_Street_Address__c = '100 Bank Plaza';
acc1.State__c = 'Texas';
acc1.City__c = 'Austin';
acc1.Zip_Code__c = '78701';
acc1.Bank_Phone__c = '800-555-2424';
acc1.Account_Holder_Name__c = 'John';
acc1.Account_Holder_Last_Name__c = 'Smith';
acc1.Acct_Street_Address__c = '123 Main Street';
acc1.Acct_Phone__c = '512-555-1234';
acc1.City1__c = 'Austin';
acc1.Zip_Code1__c = '78701';
acc1.State1__c = 'Texas';
acc1.Phone_2__c = '512-555-5678';
acc1.Phone_3__c = '512-555-9012';
acc1.Email__c = 'john.smith@testmail.com';
acc1.First_Name__c = 'John';
acc1.Last_Name__c = 'Smith';
acc1.Date_of_Birth__c = '1985-06-15';
// Skipping EPPS fields: EPPS_ID__c, EPPS_Integration_Status__c, Last_EPPS_Integration__c

// ============================================
// UPDATE ACCOUNT 2: Johnson Household
// ============================================
acc2.Name = 'Johnson Household';
acc2.Type = 'Customer';
acc2.BillingStreet = '456 Oak Avenue';
acc2.BillingCity = 'Dallas';
acc2.BillingState = 'TX';
acc2.BillingPostalCode = '75201';
acc2.BillingCountry = 'USA';
acc2.BillingLatitude = 32.7767;
acc2.BillingLongitude = -96.7970;
acc2.ShippingStreet = '456 Oak Avenue';
acc2.ShippingCity = 'Dallas';
acc2.ShippingState = 'TX';
acc2.ShippingPostalCode = '75201';
acc2.ShippingCountry = 'USA';
acc2.ShippingLatitude = 32.7767;
acc2.ShippingLongitude = -96.7970;
acc2.Phone = '214-555-4321';
acc2.Website = 'https://johnsonhousehold.example.com';
acc2.Industry = 'Other';
acc2.NumberOfEmployees = 1;
acc2.Description = 'Johnson Household - Debt Settlement Client';
acc2.EIN_Employer_Identification_Number__c = '99-8877662';
acc2.Type_of_Business__c = 'Business Consulting';
acc2.Quick_Notes__c = 'Client enrolled in DCG DEBT program. Requires follow-up calls.';
acc2.UCC_Exposure__c = 'Low';
acc2.File_Notes__c = 'Waiting for additional bank statements.';
acc2.Number_of_Owners__c = 2;
acc2.Start_of_Business__c = Date.newInstance(2018, 7, 20);
acc2.Monthly_Revenue__c = 12000;
acc2.Gross_Profit_Margin__c = 4500;
acc2.Net_Profit_or_Loss__c = 2200;
acc2.Hardship__c = 'Medical expenses and business slowdown.';
acc2.Source_origin__c = 'Referral';
acc2.Source_origin_ID__c = 'REF-2024-002';
acc2.Bank_Name__c = 'Bank of America';
acc2.Bank_Account_Type__c = 'Checking';
acc2.Routing__c = '026009593';
acc2.Bank_Account__c = '987654321098';
acc2.Bank_Street_Address__c = '200 Finance Street';
acc2.State__c = 'Texas';
acc2.City__c = 'Dallas';
acc2.Zip_Code__c = '75201';
acc2.Bank_Phone__c = '800-555-1212';
acc2.Account_Holder_Name__c = 'Sarah';
acc2.Account_Holder_Last_Name__c = 'Johnson';
acc2.Acct_Street_Address__c = '456 Oak Avenue';
acc2.Acct_Phone__c = '214-555-4321';
acc2.City1__c = 'Dallas';
acc2.Zip_Code1__c = '75201';
acc2.State1__c = 'Texas';
acc2.Phone_2__c = '214-555-8765';
acc2.Phone_3__c = '214-555-3456';
acc2.Email__c = 'sarah.johnson@testmail.com';
acc2.First_Name__c = 'Sarah';
acc2.Last_Name__c = 'Johnson';
acc2.Date_of_Birth__c = '1990-11-22';
// Skipping EPPS fields: EPPS_ID__c, EPPS_Integration_Status__c, Last_EPPS_Integration__c

update new List<Account>{acc1, acc2};
System.debug('Updated Accounts');

// ============================================
// UPDATE CONTACT 1: John Smith
// ============================================
con1.FirstName = 'John';
con1.MiddleName = 'Robert';
con1.LastName = 'Smith';
con1.Suffix = 'Jr';
con1.Salutation = 'Mr.';
con1.Title = 'Business Owner';
con1.Department = 'Management';
con1.Email = 'john.smith@testmail.com';
con1.Phone = '512-555-1234';
con1.MobilePhone = '512-555-5678';
con1.HomePhone = '512-555-9012';
con1.Fax = '512-555-3456';
con1.MailingStreet = '123 Main Street';
con1.MailingCity = 'Austin';
con1.MailingState = 'TX';
con1.MailingPostalCode = '78701';
con1.MailingCountry = 'USA';
con1.MailingLatitude = 30.2672;
con1.MailingLongitude = -97.7431;
con1.Birthdate = Date.newInstance(1985, 6, 15);
con1.Phone_2__c = '512-555-7890';
con1.Phone_3__c = '512-555-2345';
con1.Owner_s_SSN__c = '123456789';
con1.Name_2__c = 'Johnny Smith';
con1.Leadtrac_File_ID__c = 'LT-2024-0001';
con1.Type__c = 'Contact';
con1.gclid__c = 'gclid_smith_12345';
con1.SMS_Status__c = 'Sent';
con1.SMS_Message_Name__c = 'Welcome Message';
con1.SMS_Message__c = 'Welcome to our debt settlement program!';
con1.Personalized_SMS_Message__c = 'Hi John, welcome to DCG!';

// ============================================
// UPDATE CONTACT 2: Sarah Johnson
// ============================================
con2.FirstName = 'Sarah';
con2.MiddleName = 'Marie';
con2.LastName = 'Johnson';
con2.Suffix = null;
con2.Salutation = 'Ms.';
con2.Title = 'Co-Owner';
con2.Department = 'Operations';
con2.Email = 'sarah.johnson@testmail.com';
con2.Phone = '214-555-4321';
con2.MobilePhone = '214-555-8765';
con2.HomePhone = '214-555-3456';
con2.Fax = '214-555-7890';
con2.MailingStreet = '456 Oak Avenue';
con2.MailingCity = 'Dallas';
con2.MailingState = 'TX';
con2.MailingPostalCode = '75201';
con2.MailingCountry = 'USA';
con2.MailingLatitude = 32.7767;
con2.MailingLongitude = -96.7970;
con2.Birthdate = Date.newInstance(1990, 11, 22);
con2.Phone_2__c = '214-555-2345';
con2.Phone_3__c = '214-555-6789';
con2.Owner_s_SSN__c = '987654321';
con2.Name_2__c = 'S. Johnson';
con2.Leadtrac_File_ID__c = 'LT-2024-0002';
con2.Type__c = 'Contact';
con2.gclid__c = 'gclid_johnson_67890';
con2.SMS_Status__c = 'Pending';
con2.SMS_Message_Name__c = 'Welcome Message';
con2.SMS_Message__c = 'Welcome to our debt settlement program!';
con2.Personalized_SMS_Message__c = 'Hi Sarah, welcome to DCG!';

update new List<Contact>{con1, con2};
System.debug('Updated Contacts');

// ============================================
// UPDATE OPPORTUNITY 1: Smith - Debt Settlement
// ============================================
opp1.Name = 'Smith - Debt Settlement';
opp1.Description = 'Debt settlement program for Smith Family Trust. Total debt approximately $45,000.';
opp1.StageName = 'Prospecting';
opp1.Amount = 45000;
opp1.Probability = 50;
opp1.CloseDate = Date.today().addDays(30);
opp1.Type = 'New Business';
opp1.NextStep = 'Schedule welcome call';
opp1.LeadSource = 'Web';
opp1.ForecastCategoryName = 'Pipeline';
opp1.Budget_Confirmed__c = true;
opp1.Discovery_Completed__c = true;
opp1.ROI_Analysis_Completed__c = false;
opp1.Payment_Frequency__c = 'Weekly';
opp1.Doc_Submission_Status__c = 'Submitted';
opp1.Estimated_Total_Debt__c = 45000;
opp1.Estimated_Current_Payment__c = 1200;
opp1.Number_of_Weeks__c = 156;
opp1.First_Draft_Date__c = Date.today().addDays(14);
opp1.Docs_received__c = true;
opp1.Quick_Notes__c = 'Client is motivated to resolve debt. Good candidate for program.';
opp1.Nurturing__c = false;
opp1.Phone_2__c = '512-555-5678';
opp1.Phone_3__c = '512-555-9012';
opp1.Email__c = 'john.smith@testmail.com';
opp1.Lost__c = false;
opp1.Est_weekly_payment__c = 288.46;
opp1.Lead_Source__c = 'App';
opp1.utm_source__c = 'google';
opp1.utm_medium__c = 'cpc';
opp1.utm_campaign__c = 'debt_settlement_2024';
opp1.utm_content__c = 'ad_variant_a';
opp1.utm_term__c = 'debt help';
opp1.Docs_Link__c = 'https://docs.example.com/smith-documents';
opp1.Created_Date_from_Pipedrive__c = Date.today().addDays(-10);
opp1.Funding__c = false;
opp1.Medical_Debt__c = false;
opp1.Personal_Consumer_Debt2__c = true;
opp1.Tax_Debt__c = false;
opp1.Contact_Name__c = 'John Smith';
opp1.Phone__c = '512-555-1234';
opp1.Desired_Weekly_Payment__c = 300;
opp1.Main_Source__c = 'Google Ads';
opp1.Time_Zone__c = 'CST';
opp1.Personal_Consumer_Debt__c = 'Personal Consumer Debt';
opp1.Client_Status__c = 'Approved Send Contract';
opp1.Quiz_Quote__c = 45000;
opp1.gclid__c = 'gclid_smith_12345';
opp1.hashed_email__c = 'john.smith.hashed@testmail.com';
opp1.Mobile__c = '512-555-5678';
opp1.SMS_Sent_Contract_Signed__c = false;
opp1.Send_SMS_Enrolled__c = true;
opp1.Contract_SIgned_to_Cases__c = false;
opp1.Leadtrac_File_ID__c = 'LT-2024-0001';
opp1.Business_Type__c = 'Sole Prop';
opp1.Business_DBA_Name__c = 'Smith Trust';
opp1.NSF_Count__c = 0;
opp1.VOsoAI__c = false;
opp1.First_Name__c = 'John';
opp1.Last_name__c = 'Smith';
opp1.Middle_name__c = 'Robert';
opp1.Retainer_Fee_Term__c = '10';
opp1.Setup_Fee_Term__c = '10';
opp1.No_Fee_Program__c = false;
opp1.Est_Settlement__c = '43%';
opp1.Program_Fee__c = '25%';
opp1.Banking_Fee__c = 10;
opp1.SFMC_Sync__c = false;
opp1.Program_Type__c = 'DCG MOD';
// Skipping EPPS_ID__c

// ============================================
// UPDATE OPPORTUNITY 2: Johnson - Debt Settlement
// ============================================
opp2.Name = 'Johnson - Debt Settlement';
opp2.Description = 'Debt settlement program for Johnson Household. Total debt approximately $72,000.';
opp2.StageName = 'Qualification';
opp2.Amount = 72000;
opp2.Probability = 60;
opp2.CloseDate = Date.today().addDays(45);
opp2.Type = 'New Business';
opp2.NextStep = 'Review financial documents';
opp2.LeadSource = 'Referral';
opp2.ForecastCategoryName = 'Pipeline';
opp2.Budget_Confirmed__c = true;
opp2.Discovery_Completed__c = true;
opp2.ROI_Analysis_Completed__c = true;
opp2.Payment_Frequency__c = 'Weekly';
opp2.Doc_Submission_Status__c = 'Pending';
opp2.Estimated_Total_Debt__c = 72000;
opp2.Estimated_Current_Payment__c = 2100;
opp2.Number_of_Weeks__c = 208;
opp2.First_Draft_Date__c = Date.today().addDays(7);
opp2.Docs_received__c = false;
opp2.Quick_Notes__c = 'Client referred by existing customer. Higher debt amount requires additional review.';
opp2.Nurturing__c = false;
opp2.Phone_2__c = '214-555-8765';
opp2.Phone_3__c = '214-555-3456';
opp2.Email__c = 'sarah.johnson@testmail.com';
opp2.Lost__c = false;
opp2.Est_weekly_payment__c = 346.15;
opp2.Lead_Source__c = 'BrodyLeads';
opp2.utm_source__c = 'referral';
opp2.utm_medium__c = 'partner';
opp2.utm_campaign__c = 'referral_program_2024';
opp2.utm_content__c = 'partner_link';
opp2.utm_term__c = 'debt relief';
opp2.Docs_Link__c = 'https://docs.example.com/johnson-documents';
opp2.Created_Date_from_Pipedrive__c = Date.today().addDays(-5);
opp2.Funding__c = false;
opp2.Medical_Debt__c = true;
opp2.Personal_Consumer_Debt2__c = true;
opp2.Tax_Debt__c = false;
opp2.Contact_Name__c = 'Sarah Johnson';
opp2.Phone__c = '214-555-4321';
opp2.Desired_Weekly_Payment__c = 350;
opp2.Main_Source__c = 'Referral Partner';
opp2.Time_Zone__c = 'CST';
opp2.Personal_Consumer_Debt__c = 'Medical Debt';
opp2.Client_Status__c = 'Missing Info';
opp2.Quiz_Quote__c = 72000;
opp2.gclid__c = 'gclid_johnson_67890';
opp2.hashed_email__c = 'sarah.johnson.hashed@testmail.com';
opp2.Mobile__c = '214-555-8765';
opp2.SMS_Sent_Contract_Signed__c = false;
opp2.Send_SMS_Enrolled__c = true;
opp2.Contract_SIgned_to_Cases__c = false;
opp2.Leadtrac_File_ID__c = 'LT-2024-0002';
opp2.Business_Type__c = 'LLC';
opp2.Business_DBA_Name__c = 'Johnson Enterprises';
opp2.NSF_Count__c = 0;
opp2.VOsoAI__c = false;
opp2.First_Name__c = 'Sarah';
opp2.Last_name__c = 'Johnson';
opp2.Middle_name__c = 'Marie';
opp2.Retainer_Fee_Term__c = '8';
opp2.Setup_Fee_Term__c = '8';
opp2.No_Fee_Program__c = false;
opp2.Est_Settlement__c = '60%';
opp2.Program_Fee__c = '30%';
opp2.Banking_Fee__c = 10;
opp2.SFMC_Sync__c = false;
opp2.Program_Type__c = 'DCG DEBT';
// Skipping EPPS_ID__c

update new List<Opportunity>{opp1, opp2};
System.debug('Updated Opportunities');

// ============================================
// SUMMARY OUTPUT
// ============================================
System.debug('========== ALL FIELDS UPDATED SUCCESSFULLY ==========');
System.debug('Record Set 1:');
System.debug('  Account: ' + acc1.Name + ' (Id: ' + acc1.Id + ')');
System.debug('  Contact: ' + con1.FirstName + ' ' + con1.LastName + ' (Id: ' + con1.Id + ')');
System.debug('  Opportunity: ' + opp1.Name + ' (Id: ' + opp1.Id + ')');
System.debug('');
System.debug('Record Set 2:');
System.debug('  Account: ' + acc2.Name + ' (Id: ' + acc2.Id + ')');
System.debug('  Contact: ' + con2.FirstName + ' ' + con2.LastName + ' (Id: ' + con2.Id + ')');
System.debug('  Opportunity: ' + opp2.Name + ' (Id: ' + opp2.Id + ')');
System.debug('======================================================');
System.debug('SKIPPED EPPS FIELDS: EPPS_ID__c, EPPS_Integration_Status__c, Last_EPPS_Integration__c');
