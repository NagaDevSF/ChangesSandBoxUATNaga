/**
 * Test class for SalesCalculatorService
 * @author DCG Development Team
 * @date 2025-09-02
 */
@isTest
private class SalesCalculatorServiceTest {
    // Deterministic IDs for reuse across tests
    private static Id TEST_ACCOUNT_ID;
    private static Id TEST_OPPORTUNITY_ID;
    private static Id TEST_SYSADMIN_ID;
    
    private static void ensureAdmin() {
        if (TEST_SYSADMIN_ID == null) {
            User admin = TestPermsUtil.createSysAdminUser();
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Sales_Calculator'];
            PermissionSetAssignment psa = new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = ps.Id);
            insert psa;
            TEST_SYSADMIN_ID = admin.Id;
        }
    }
    
    @testSetup
    static void setup() {
        // Use factory for consistency, then store IDs for reuse
        User admin = TestPermsUtil.createSysAdminUser();
        TEST_SYSADMIN_ID = admin.Id;
        
        System.runAs(admin) {

            Account a = TestDataFactory.makeAccount('Test Account');
            TEST_ACCOUNT_ID = a.Id;
            Opportunity o = TestDataFactory.makeOpp(a.Id, 'Test Opportunity');
            TEST_OPPORTUNITY_ID = o.Id;
    
            //List<Creditor__c> creditors = TestDataFactory.makeCreditors(3, 'Test Creditor');
            List<Account> creditors = TestDataFactory.makeCreditorsAsAccount(3, 'Test Creditor');
            TestDataFactory.linkCredsToOpp(o.Id, creditors, 10000, 100, 3);
        }
    }
    
    @isTest
    static void testCalculatePaymentPlan_DCGModProgram() {
        ensureAdmin();
        // Use deterministic opportunity Id
        //Id testOpp = TEST_OPPORTUNITY_ID;
        Id testOpp = [SELECT Id FROM Opportunity].Id;
        
        // Prepare parameters
        Map<String, Object> params = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 1000,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'firstPaymentDate' => String.valueOf(Date.today().addDays(7)),
            'preferredDayOfWeek' => 2,
            'noFeeProgram' => false,
            'versionNotes' => 'Test calculation'
        };
        
        Test.startTest();
        PaymentPlan__c result;
        System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
            result = SalesCalculatorService.calculatePaymentPlan(testOpp, params);
        }
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result, 'Payment plan should be created');
        System.assertEquals(testOpp, result.Opportunity__c, 'Payment plan should be linked to opportunity');
        System.assertEquals(1, result.Version_Number__c, 'Should be version 1');
        System.assertEquals('Initial', result.Version_Type__c, 'Should be initial version');
        System.assertEquals('Draft', result.Version_Status__c, 'Should be in draft status');
        System.assertEquals(false, result.Is_Active__c, 'Should not be active by default');
        
        // Verify calculation fields
        //System.assertEquals(45000, result.Total_Debt__c, 'Total debt should be sum of creditor amounts');
        //System.assertEquals(27000, result.Settlement_Amount__c, 'Settlement should be 60% of debt');
        //System.assertEquals(15750, result.Program_Fee_Amount__c, 'Program fee should be 35% of debt');
        //System.assertEquals(1000, result.Setup_Fee__c, 'Setup fee should match parameter');
        //System.assertNotEquals(null, result.Weekly_Payment__c, 'Weekly payment should be calculated');
        //System.assertNotEquals(null, result.Number_of_Payments__c, 'Number of payments should be calculated');
    }
    
    @isTest
    static void testCalculatePaymentPlan_DCGDebtProgram() {
        ensureAdmin();
        // Use deterministic opportunity Id
        //Id testOpp = TEST_OPPORTUNITY_ID;
        Id testOpp = [SELECT Id FROM Opportunity].Id;
        
        // Prepare parameters for DCG Debt program
        Map<String, Object> params = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 1000,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'firstPaymentDate' => String.valueOf(Date.today().addDays(7)),
            'noFeeProgram' => false
        };
        
        Test.startTest();
        PaymentPlan__c result;
        System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
            result = SalesCalculatorService.calculatePaymentPlan(testOpp, params);
        }
        Test.stopTest();
        
        // Verify DCG Debt specific settings
        System.assertEquals('DCG_DEBT', result.Program_Type__c, 'Program type should be DCG Debt');
        System.assertNotEquals(null, result.Payment_Schedule_JSON__c, 'Payment schedule should be generated');
    }
    
    @isTest
    static void testCalculatePaymentPlan_NoFeeProgram() {
        ensureAdmin();
        // Use deterministic opportunity Id
        //Id testOpp = TEST_OPPORTUNITY_ID;
        Id testOpp = [SELECT Id FROM Opportunity].Id;
        
        // Prepare parameters for no-fee program
        Map<String, Object> params = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'settlementPercentage' => 60,
            'programFeePercentage' => 0,
            'setupFee' => 2500,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'noFeeProgram' => true
        };
        
        Test.startTest();
        PaymentPlan__c result;
        System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
            result = SalesCalculatorService.calculatePaymentPlan(testOpp, params);
        }
        Test.stopTest();
        
        // Verify no-fee program settings
        System.assertEquals(true, result.No_Fee_Program__c, 'Should be marked as no-fee program');
        System.assertEquals(0, result.Program_Fee_Percentage__c, 'Program fee should be 0 for no-fee program');
    }
    
    @isTest
    static void testVersionControl() {
        ensureAdmin();
        // Use deterministic opportunity Id
        //Id testOpp = TEST_OPPORTUNITY_ID;
        Id testOpp = [SELECT Id FROM Opportunity].Id;
        
        Map<String, Object> params = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 1000,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };
        
        Test.startTest();
        PaymentPlan__c version1;
        PaymentPlan__c version2;
        System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
            // Create first version
            version1 = SalesCalculatorService.calculatePaymentPlan(testOpp, params);
            // Create second version
            params.put('settlementPercentage', 55);
            version2 = SalesCalculatorService.calculatePaymentPlan(testOpp, params);
        }
        Test.stopTest();
        
        // Verify version numbers
        System.assertEquals(1, version1.Version_Number__c, 'First plan should be version 1');
        System.assertEquals(2, version2.Version_Number__c, 'Second plan should be version 2');
        //System.assertEquals(version1.Id, version2.Previous_Version__c, 'Version 2 should reference version 1');
    }
    
    @isTest
    static void testInvalidOpportunity() {
        ensureAdmin();  
        
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
                // Use a valid non-Opportunity Id (Account) to avoid Id format issues
                Account invalidAccount = new Account(Name = 'Invalid For Opp Test');
                insert invalidAccount;
                Id fakeOppId = invalidAccount.Id;
                
                Map<String, Object> params = new Map<String, Object>{
                    'programType' => 'Custom'
                };
                SalesCalculatorService.calculatePaymentPlan(fakeOppId, params);
            }
        } catch (Exception e) {
            exceptionThrown = true;
            //System.assert(e.getMessage().contains('Failed to calculate payment plan'), 'Should throw wrapped calculation error');
        }
        Test.stopTest();
        
        System.assert(exceptionThrown, 'Exception should be thrown for invalid opportunity');
    }
    
    @isTest
    static void testNoCreditors() {
        ensureAdmin();
        
        Test.startTest();
        PaymentPlan__c result;
        
        System.runAs(new User(Id = TEST_SYSADMIN_ID)) {
             // Create opportunity without creditors
            Account acc = new Account(Name = 'Test Account 2');
            insert acc;
            
            Opportunity oppNoCreditors = new Opportunity(
                Name = 'Opp Without Creditors',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30)
            );
            insert oppNoCreditors;
            
            Map<String, Object> params = new Map<String, Object>{
                'programType' => 'DCG_MOD',
                'settlementPercentage' => 60,
                'programFeePercentage' => 35
            };
            result = SalesCalculatorService.calculatePaymentPlan(oppNoCreditors.Id, params);
        }
        Test.stopTest();
        
        // Should handle empty creditors gracefully
        System.assertEquals(0, result.Total_Debt__c, 'Total debt should be 0 with no creditors');
        System.assertEquals(0, result.Settlement_Amount__c, 'Settlement should be 0 with no creditors');
    }
}