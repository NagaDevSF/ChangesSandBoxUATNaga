/**
 * @description Test class for PaymentPlanCalculationService
 * Focuses on covering shared helper methods and edge-case branches
 * including DraftNumberSortWrapper comparator (null dates, same dates,
 * null payment numbers), distributeAmountEvenly, separateItemsByStatus,
 * calculatePaidSums, cloneItemForNewPlan, and parsePercentageToDecimal.
 *
 * @author DCG Development Team
 * @since 2024-01
 */
@IsTest
private class PaymentPlanCalculationServiceTest {

    // ==================================================================================
    // TEST SETUP
    // ==================================================================================

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account acc = new Account(Name = 'CalcSvc Test Account');
        insert acc;

        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'CalcSvc Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create Payment Plan
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Program_Type__c = 'DCG MOD',
            Total_Debt__c = 50000,
            Settlement_Percentage__c = 50,
            Program_Fee_Percentage__c = 20,
            Total_Program_Cost__c = 35000,
            Weekly_Payment__c = 500,
            Current_Payment__c = 1000,
            Number_of_Payments__c = 10,
            First_Payment_Date__c = Date.today(),
            Status__c = 'Active',
            Version_Number__c = 1,
            Is_Active__c = true,
            Banking_Fee__c = 15,
            Setup_Fee__c = 1000,
            Setup_Fee_Payments__c = 4
        );
        insert plan;

        // Create Payment Schedule Items with mixed statuses
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        Date paymentDate = Date.today();
        Decimal runningBalance = 0;

        for (Integer i = 1; i <= 10; i++) {
            Decimal setupFee = (i <= 4) ? 250 : 0;
            Decimal bankingFee = 15;
            Decimal totalPayment = 500;
            Decimal toSavings = totalPayment - setupFee - bankingFee;
            runningBalance += toSavings;

            String status;
            if (i <= 2) {
                status = 'Cleared';
            } else if (i == 3) {
                status = 'NSF';
            } else if (i == 4) {
                status = 'Cancelled';
            } else {
                status = 'Scheduled';
            }

            Payment_Schedule_Item__c item = new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Number__c = i,
                Draft_Number__c = String.valueOf(i),
                Payment_Date__c = paymentDate,
                Total_Payment__c = totalPayment,
                Retainer_Fee_Amount__c = 0,
                Setup_Fee_Amount__c = setupFee,
                Program_Fee_Amount__c = 100,
                Banking_Fee_Amount__c = bankingFee,
                Bank2_Fee_Amount__c = 0,
                Additional_Products_Amount__c = 0,
                Savings_Balance__c = runningBalance,
                To_Escrow_Amount__c = toSavings,
                Status__c = status
            );
            items.add(item);
            paymentDate = paymentDate.addDays(7);
        }
        insert items;
    }

    // ==================================================================================
    // HELPER METHODS
    // ==================================================================================

    private static PaymentPlan__c getTestPlan() {
        return [SELECT Id, Opportunity__c FROM PaymentPlan__c LIMIT 1];
    }

    private static List<Payment_Schedule_Item__c> getTestItems() {
        String fields = PaymentPlanCalculationService.getScheduleItemQueryFields();
        String query = 'SELECT ' + fields + ' FROM Payment_Schedule_Item__c ORDER BY Payment_Number__c';
        return Database.query(query);
    }

    // ==================================================================================
    // parsePercentageToDecimal TESTS
    // ==================================================================================

    @IsTest
    static void testParsePercentageToDecimal() {
        // Arrange - various input formats
        Test.startTest();

        // Act & Assert - percentage with % sign
        Decimal result1 = PaymentPlanCalculationService.parsePercentageToDecimal('35%');
        System.assertEquals(35, result1, 'Should parse "35%" to 35');

        // Plain number string
        Decimal result2 = PaymentPlanCalculationService.parsePercentageToDecimal('35');
        System.assertEquals(35, result2, 'Should parse "35" to 35');

        // Decimal percentage
        Decimal result3 = PaymentPlanCalculationService.parsePercentageToDecimal('20.5%');
        System.assertEquals(20.5, result3, 'Should parse "20.5%" to 20.5');

        // Non-numeric string
        Decimal result4 = PaymentPlanCalculationService.parsePercentageToDecimal('abc');
        System.assertEquals(null, result4, 'Should return null for non-numeric "abc"');

        // Null input
        Decimal result5 = PaymentPlanCalculationService.parsePercentageToDecimal(null);
        System.assertEquals(null, result5, 'Should return null for null input');

        Test.stopTest();
    }

    @IsTest
    static void testParsePercentageToDecimalBlank() {
        // Arrange - blank and edge-case inputs

        Test.startTest();

        // Empty string
        Decimal result1 = PaymentPlanCalculationService.parsePercentageToDecimal('');
        System.assertEquals(null, result1, 'Should return null for empty string');

        // Whitespace only
        Decimal result2 = PaymentPlanCalculationService.parsePercentageToDecimal('   ');
        System.assertEquals(null, result2, 'Should return null for whitespace-only string');

        // Just a % sign
        Decimal result3 = PaymentPlanCalculationService.parsePercentageToDecimal('%');
        System.assertEquals(null, result3, 'Should return null for bare "%" sign');

        // Negative percentage
        Decimal result4 = PaymentPlanCalculationService.parsePercentageToDecimal('-5%');
        System.assertEquals(-5, result4, 'Should parse "-5%" to -5');

        Test.stopTest();
    }

    // ==================================================================================
    // distributeAmountEvenly TESTS
    // ==================================================================================

    @IsTest
    static void testDistributeAmountEvenly() {
        // Arrange
        Decimal totalAmount = 100;
        Integer count = 3;

        // Act
        Test.startTest();
        List<Decimal> distributed = PaymentPlanCalculationService.distributeAmountEvenly(totalAmount, count);
        Test.stopTest();

        // Assert
        System.assertEquals(3, distributed.size(), 'Should return 3 distributed amounts');

        // 100 / 3 = 33.33 (base), remainder = 100 - (33.33 * 3) = 100 - 99.99 = 0.01
        // First payment gets 33.33 + 0.01 = 33.34
        System.assertEquals(33.34, distributed[0], 'First payment should get base + remainder (33.34)');
        System.assertEquals(33.33, distributed[1], 'Second payment should get base amount (33.33)');
        System.assertEquals(33.33, distributed[2], 'Third payment should get base amount (33.33)');

        // Verify total sums correctly
        Decimal total = 0;
        for (Decimal d : distributed) {
            total += d;
        }
        System.assertEquals(100.00, total, 'Sum of distributed amounts should equal total');
    }

    @IsTest
    static void testDistributeAmountEvenlyZero() {
        // Arrange & Act
        Test.startTest();

        // Zero amount
        List<Decimal> zeroAmount = PaymentPlanCalculationService.distributeAmountEvenly(0, 3);
        System.assertEquals(3, zeroAmount.size(), 'Should return 3 items for zero amount');
        System.assertEquals(0, zeroAmount[0], 'All items should be 0 for zero amount');
        System.assertEquals(0, zeroAmount[1], 'All items should be 0 for zero amount');
        System.assertEquals(0, zeroAmount[2], 'All items should be 0 for zero amount');

        // Zero count
        List<Decimal> zeroCount = PaymentPlanCalculationService.distributeAmountEvenly(100, 0);
        System.assertEquals(0, zeroCount.size(), 'Should return empty list for zero count');

        // Negative count
        List<Decimal> negativeCount = PaymentPlanCalculationService.distributeAmountEvenly(100, -1);
        System.assertEquals(0, negativeCount.size(), 'Should return empty list for negative count');

        // Even distribution (no remainder)
        List<Decimal> evenSplit = PaymentPlanCalculationService.distributeAmountEvenly(100, 4);
        System.assertEquals(4, evenSplit.size(), 'Should return 4 items');
        System.assertEquals(25.00, evenSplit[0], 'Each payment should be exactly 25.00');
        System.assertEquals(25.00, evenSplit[3], 'Last payment should be exactly 25.00');

        Test.stopTest();
    }

    // ==================================================================================
    // recalculateDraftNumbers TESTS
    // ==================================================================================

    @IsTest
    static void testRecalculateDraftNumbers() {
        // Arrange - items with mixed statuses
        List<Payment_Schedule_Item__c> items = getTestItems();

        // Act
        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(items);
        Test.stopTest();

        // Assert - NSF (item 3) and Cancelled (item 4) should have null Draft_Number__c
        // The rest should be sequentially numbered
        Integer draftCount = 0;
        for (Payment_Schedule_Item__c item : items) {
            if (item.Status__c == 'NSF' || item.Status__c == 'Cancelled') {
                System.assertEquals(null, item.Draft_Number__c,
                    'NSF/Cancelled items should have null Draft_Number__c');
            } else {
                draftCount++;
                System.assertNotEquals(null, item.Draft_Number__c,
                    'Scheduled/Cleared items should have a draft number');
            }
        }
        System.assert(draftCount > 0, 'Should have at least one item with a draft number');
    }

    @IsTest
    static void testRecalculateDraftNumbersNullDates() {
        // Arrange - use existing test items, then set Payment_Date__c to null in-memory
        // (Payment_Date__c is required on insert, so we modify in-memory for the sort test)
        PaymentPlan__c plan = getTestPlan();

        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();

        // Insert valid items first
        for (Integer i = 1; i <= 4; i++) {
            items.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Number__c = 100 + i,
                Payment_Date__c = Date.today().addDays(100 + i),
                Total_Payment__c = 100,
                Status__c = 'Scheduled'
            ));
        }
        insert items;

        // Re-query to get Ids
        List<Payment_Schedule_Item__c> insertedItems = [
            SELECT Id, Payment_Plan__c, Payment_Number__c, Payment_Date__c,
                   Total_Payment__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :items
            ORDER BY Payment_Number__c
        ];

        // Now set dates to null in-memory to trigger null-date sorting branches
        insertedItems[1].Payment_Date__c = null; // triggers thisDate==null
        insertedItems[2].Payment_Date__c = null; // triggers both-null branch
        insertedItems[3].Payment_Date__c = null;
        insertedItems[3].Payment_Number__c = null; // triggers null payment number branch

        // Act
        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(insertedItems);
        Test.stopTest();

        // Assert - all items are Scheduled so all should have draft numbers
        for (Payment_Schedule_Item__c item : insertedItems) {
            System.assertNotEquals(null, item.Draft_Number__c,
                'All Scheduled items should get a draft number even with null dates');
        }
    }

    @IsTest
    static void testRecalculateDraftNumbersSameDate() {
        // Arrange - items with same date to trigger "same date, sort by payment number" path
        PaymentPlan__c plan = getTestPlan();
        Date sameDate = Date.today().addDays(30);

        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();

        // Multiple items on the same date with different payment numbers
        Payment_Schedule_Item__c itemA = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 5,
            Payment_Date__c = sameDate,
            Total_Payment__c = 100,
            Status__c = 'Scheduled'
        );
        items.add(itemA);

        Payment_Schedule_Item__c itemB = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 2,
            Payment_Date__c = sameDate,
            Total_Payment__c = 100,
            Status__c = 'Scheduled'
        );
        items.add(itemB);

        Payment_Schedule_Item__c itemC = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 8,
            Payment_Date__c = sameDate,
            Total_Payment__c = 100,
            Status__c = 'Scheduled'
        );
        items.add(itemC);

        // Item with same date (payment number set to null in-memory after insert)
        Payment_Schedule_Item__c itemD = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 99,
            Payment_Date__c = sameDate,
            Total_Payment__c = 100,
            Status__c = 'Scheduled'
        );
        items.add(itemD);

        insert items;

        // Re-query
        List<Payment_Schedule_Item__c> insertedItems = [
            SELECT Id, Payment_Plan__c, Payment_Number__c, Payment_Date__c,
                   Total_Payment__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :items
        ];

        // Set Payment_Number__c to null on last item in-memory to trigger null branch
        for (Payment_Schedule_Item__c item : insertedItems) {
            if (item.Payment_Number__c == 99) {
                item.Payment_Number__c = null;
                break;
            }
        }

        // Act
        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(insertedItems);
        Test.stopTest();

        // Assert - all 4 items should get sequential draft numbers (all Scheduled)
        Integer assignedDraftNumbers = 0;
        for (Payment_Schedule_Item__c item : insertedItems) {
            if (item.Draft_Number__c != null) {
                assignedDraftNumbers++;
            }
        }
        System.assertEquals(4, assignedDraftNumbers,
            'All 4 Scheduled items on same date should have draft numbers');
    }

    @IsTest
    static void testRecalculateDraftNumbersEmpty() {
        // Arrange - empty list and null list

        Test.startTest();

        // Act with empty list (should not throw)
        List<Payment_Schedule_Item__c> emptyList = new List<Payment_Schedule_Item__c>();
        PaymentPlanCalculationService.recalculateDraftNumbers(emptyList);

        // Act with null list (should not throw)
        PaymentPlanCalculationService.recalculateDraftNumbers(null);

        Test.stopTest();

        // Assert - no exceptions thrown
        System.assert(true, 'Should handle empty and null lists without exceptions');
    }

    // ==================================================================================
    // separateItemsByStatus TESTS
    // ==================================================================================

    @IsTest
    static void testSeparateItemsByStatus() {
        // Arrange
        List<Payment_Schedule_Item__c> allItems = getTestItems();
        List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
        List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();

        // Act
        Test.startTest();
        PaymentPlanCalculationService.separateItemsByStatus(allItems, nonScheduledItems, scheduledItems);
        Test.stopTest();

        // Assert
        // Test data has 2 Cleared, 1 NSF, 1 Cancelled, 6 Scheduled
        System.assertEquals(4, nonScheduledItems.size(),
            'Should have 4 non-scheduled items (2 Cleared + 1 NSF + 1 Cancelled)');
        System.assertEquals(6, scheduledItems.size(),
            'Should have 6 scheduled items');

        // Verify non-scheduled items have correct statuses
        Set<String> nonScheduledStatuses = new Set<String>();
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            nonScheduledStatuses.add(item.Status__c);
        }
        System.assert(nonScheduledStatuses.contains('Cleared'),
            'Non-scheduled items should include Cleared');
        System.assert(nonScheduledStatuses.contains('NSF'),
            'Non-scheduled items should include NSF');
        System.assert(nonScheduledStatuses.contains('Cancelled'),
            'Non-scheduled items should include Cancelled');

        // Verify all scheduled items have Scheduled status
        for (Payment_Schedule_Item__c item : scheduledItems) {
            System.assertEquals('Scheduled', item.Status__c,
                'All items in scheduled list should have Scheduled status');
        }
    }

    // ==================================================================================
    // calculatePaidSums TESTS
    // ==================================================================================

    @IsTest
    static void testCalculatePaidSums() {
        // Arrange - get non-scheduled items (Cleared, NSF, Cancelled)
        List<Payment_Schedule_Item__c> allItems = getTestItems();
        List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
        List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();
        PaymentPlanCalculationService.separateItemsByStatus(allItems, nonScheduledItems, scheduledItems);

        // Act
        Test.startTest();
        PaymentPlanCalculationService.PaidSumsWrapper sums =
            PaymentPlanCalculationService.calculatePaidSums(nonScheduledItems);
        Test.stopTest();

        // Assert
        System.assertEquals(4, sums.nonScheduledCount,
            'Should count all 4 non-scheduled items');

        // Only Cleared items (2 items) contribute to setup/program/escrow sums
        // Each cleared item has Setup_Fee=250, Program_Fee=100
        System.assertEquals(500, sums.setupFee,
            'Setup fee should be sum of 2 cleared items (2 x 250 = 500)');
        System.assertEquals(200, sums.programFee,
            'Program fee should be sum of 2 cleared items (2 x 100 = 200)');

        // Escrow: each cleared item has To_Escrow = 500 - 250 - 15 = 235
        System.assertEquals(470, sums.escrow,
            'Escrow should be sum of 2 cleared items escrow amounts');

        // Savings balance should be from the highest payment number cleared item
        System.assert(sums.savingsBalance >= 0,
            'Savings balance should be non-negative from cleared items');
    }

    @IsTest
    static void testCalculatePaidSumsNoCleared() {
        // Arrange - items with only NSF status (no cleared items)
        PaymentPlan__c plan = getTestPlan();

        List<Payment_Schedule_Item__c> nsfItems = new List<Payment_Schedule_Item__c>();

        Payment_Schedule_Item__c nsf1 = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 1,
            Payment_Date__c = Date.today(),
            Total_Payment__c = 500,
            Setup_Fee_Amount__c = 250,
            Program_Fee_Amount__c = 100,
            Banking_Fee_Amount__c = 15,
            To_Escrow_Amount__c = 135,
            Savings_Balance__c = 135,
            Status__c = 'NSF'
        );
        nsfItems.add(nsf1);

        Payment_Schedule_Item__c nsf2 = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 2,
            Payment_Date__c = Date.today().addDays(7),
            Total_Payment__c = 500,
            Setup_Fee_Amount__c = 250,
            Program_Fee_Amount__c = 100,
            Banking_Fee_Amount__c = 15,
            To_Escrow_Amount__c = 135,
            Savings_Balance__c = 270,
            Status__c = 'NSF'
        );
        nsfItems.add(nsf2);

        insert nsfItems;

        // Re-query to get full records
        List<Payment_Schedule_Item__c> queriedNsfItems = [
            SELECT Id, Payment_Number__c, Status__c, Setup_Fee_Amount__c,
                   Program_Fee_Amount__c, To_Escrow_Amount__c, Savings_Balance__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :nsfItems
        ];

        // Act
        Test.startTest();
        PaymentPlanCalculationService.PaidSumsWrapper sums =
            PaymentPlanCalculationService.calculatePaidSums(queriedNsfItems);
        Test.stopTest();

        // Assert - NSF items should NOT contribute to paid sums
        System.assertEquals(2, sums.nonScheduledCount,
            'Should count 2 non-scheduled items');
        System.assertEquals(0, sums.setupFee,
            'Setup fee should be 0 when only NSF items');
        System.assertEquals(0, sums.programFee,
            'Program fee should be 0 when only NSF items');
        System.assertEquals(0, sums.escrow,
            'Escrow should be 0 when only NSF items');
        System.assertEquals(0, sums.savingsBalance,
            'Savings balance should be 0 when no cleared items');
    }

    // ==================================================================================
    // carryOverWireFees TESTS
    // ==================================================================================

    @IsTest
    static void testCarryOverWireFeesEmpty() {
        // Arrange - empty and null lists

        Test.startTest();

        // Act with null lists (should not throw)
        PaymentPlanCalculationService.carryOverWireFees(null, null);

        // Act with empty lists (should not throw)
        PaymentPlanCalculationService.carryOverWireFees(
            new List<Payment_Schedule_Item__c>(),
            new List<Payment_Schedule_Item__c>()
        );

        // Act with one null, one empty
        PaymentPlanCalculationService.carryOverWireFees(
            null,
            new List<Payment_Schedule_Item__c>()
        );

        PaymentPlanCalculationService.carryOverWireFees(
            new List<Payment_Schedule_Item__c>(),
            null
        );

        Test.stopTest();

        // Assert - no exceptions
        System.assert(true, 'Should handle empty and null lists without exceptions');
    }

    // ==================================================================================
    // cloneItemForNewPlan TESTS
    // ==================================================================================

    @IsTest
    static void testCloneItemForNewPlan() {
        // Arrange
        PaymentPlan__c plan = getTestPlan();
        List<Payment_Schedule_Item__c> items = getTestItems();
        Payment_Schedule_Item__c original = items[0];

        // Create a second plan to clone into
        PaymentPlan__c newPlan = new PaymentPlan__c(
            Opportunity__c = plan.Opportunity__c,
            Program_Type__c = 'DCG MOD',
            Total_Debt__c = 50000,
            Weekly_Payment__c = 500,
            Number_of_Payments__c = 10,
            First_Payment_Date__c = Date.today(),
            Status__c = 'Draft',
            Version_Number__c = 2
        );
        insert newPlan;

        // Act
        Test.startTest();
        Payment_Schedule_Item__c cloned =
            PaymentPlanCalculationService.cloneItemForNewPlan(original, newPlan.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(newPlan.Id, cloned.Payment_Plan__c,
            'Cloned item should reference the new plan');
        System.assertNotEquals(original.Id, cloned.Id,
            'Cloned item should not have the original Id');
        System.assertEquals(original.Payment_Number__c, cloned.Payment_Number__c,
            'Cloned item should preserve Payment_Number__c');
        System.assertEquals(original.Total_Payment__c, cloned.Total_Payment__c,
            'Cloned item should preserve Total_Payment__c');
        System.assertEquals(original.Status__c, cloned.Status__c,
            'Cloned item should preserve Status__c');
        System.assertEquals(original.Payment_Date__c, cloned.Payment_Date__c,
            'Cloned item should preserve Payment_Date__c');
        System.assertEquals(original.Setup_Fee_Amount__c, cloned.Setup_Fee_Amount__c,
            'Cloned item should preserve Setup_Fee_Amount__c');
        System.assertEquals(original.Banking_Fee_Amount__c, cloned.Banking_Fee_Amount__c,
            'Cloned item should preserve Banking_Fee_Amount__c');
    }

    // ==================================================================================
    // getScheduleItemQueryFields / getPaymentPlanQueryFields TESTS
    // ==================================================================================

    @IsTest
    static void testGetScheduleItemQueryFields() {
        // Act
        Test.startTest();
        String fields = PaymentPlanCalculationService.getScheduleItemQueryFields();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, fields,
            'Should return a non-null field list');
        System.assert(fields.length() > 0,
            'Should return a non-empty field list');
        System.assert(fields.containsIgnoreCase('Id'),
            'Should include Id field');
        System.assert(fields.containsIgnoreCase('payment_number__c'),
            'Should include Payment_Number__c field');
        System.assert(fields.containsIgnoreCase('status__c'),
            'Should include Status__c field');
    }

    @IsTest
    static void testGetPaymentPlanQueryFields() {
        // Act
        Test.startTest();
        String fields = PaymentPlanCalculationService.getPaymentPlanQueryFields();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, fields,
            'Should return a non-null field list');
        System.assert(fields.length() > 0,
            'Should return a non-empty field list');
        System.assert(fields.containsIgnoreCase('Id'),
            'Should include Id field');
    }

    // ==================================================================================
    // BULK OPERATION TESTS
    // ==================================================================================

    @IsTest
    static void testRecalculateDraftNumbersBulk() {
        // Arrange - create 200+ items to test bulk handling
        PaymentPlan__c plan = getTestPlan();
        List<Payment_Schedule_Item__c> bulkItems = new List<Payment_Schedule_Item__c>();
        Date startDate = Date.today().addDays(100);

        for (Integer i = 1; i <= 210; i++) {
            String status;
            if (Math.mod(i, 10) == 0) {
                status = 'NSF';
            } else if (Math.mod(i, 15) == 0) {
                status = 'Cancelled';
            } else {
                status = 'Scheduled';
            }

            bulkItems.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Number__c = 100 + i,
                Payment_Date__c = startDate.addDays(i * 7),
                Total_Payment__c = 500,
                Status__c = status
            ));
        }
        insert bulkItems;

        // Re-query
        List<Payment_Schedule_Item__c> queriedItems = [
            SELECT Id, Payment_Number__c, Payment_Date__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :bulkItems
            ORDER BY Payment_Number__c
        ];

        // Act
        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(queriedItems);
        Test.stopTest();

        // Assert - count draft numbers assigned
        Integer draftCount = 0;
        Integer nullDraftCount = 0;
        for (Payment_Schedule_Item__c item : queriedItems) {
            if (item.Draft_Number__c != null) {
                draftCount++;
            } else {
                nullDraftCount++;
            }
        }
        System.assert(draftCount > 0, 'Should assign draft numbers to non-NSF/Cancelled items');
        System.assert(nullDraftCount > 0, 'Should null draft numbers for NSF/Cancelled items');
        System.assertEquals(210, draftCount + nullDraftCount,
            'Total items should be 210');
    }

    // ==================================================================================
    // EDGE CASE TESTS
    // ==================================================================================

    @IsTest
    static void testDistributeAmountEvenlySmallAmount() {
        // Arrange - edge case: very small amount across many payments

        Test.startTest();

        // $0.01 across 1 payment
        List<Decimal> singlePenny = PaymentPlanCalculationService.distributeAmountEvenly(0.01, 1);
        System.assertEquals(1, singlePenny.size(), 'Should return 1 item');
        System.assertEquals(0.01, singlePenny[0], 'Single payment should get full penny');

        // $1.00 across 7 payments
        List<Decimal> sevenWay = PaymentPlanCalculationService.distributeAmountEvenly(1.00, 7);
        System.assertEquals(7, sevenWay.size(), 'Should return 7 items');
        Decimal sevenTotal = 0;
        for (Decimal d : sevenWay) {
            sevenTotal += d;
        }
        System.assertEquals(1.00, sevenTotal, 'Sum across 7 payments should equal $1.00');

        Test.stopTest();
    }

    @IsTest
    static void testRecalculateDraftNumbersOnlyNSFAndCancelled() {
        // Arrange - all items are NSF or Cancelled (no items get draft numbers)
        PaymentPlan__c plan = getTestPlan();
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();

        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 1,
            Payment_Date__c = Date.today(),
            Total_Payment__c = 500,
            Status__c = 'NSF'
        ));
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 2,
            Payment_Date__c = Date.today().addDays(7),
            Total_Payment__c = 500,
            Status__c = 'Cancelled'
        ));
        insert items;

        List<Payment_Schedule_Item__c> queriedItems = [
            SELECT Id, Payment_Number__c, Payment_Date__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :items
        ];

        // Act
        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(queriedItems);
        Test.stopTest();

        // Assert - all items should have null Draft_Number__c
        for (Payment_Schedule_Item__c item : queriedItems) {
            System.assertEquals(null, item.Draft_Number__c,
                'NSF/Cancelled items should have null Draft_Number__c');
        }
    }

    @IsTest
    static void testCalculatePaidSumsEmptyList() {
        // Arrange - empty list

        Test.startTest();
        PaymentPlanCalculationService.PaidSumsWrapper sums =
            PaymentPlanCalculationService.calculatePaidSums(new List<Payment_Schedule_Item__c>());
        Test.stopTest();

        // Assert
        System.assertEquals(0, sums.nonScheduledCount,
            'Non-scheduled count should be 0 for empty list');
        System.assertEquals(0, sums.setupFee,
            'Setup fee should be 0 for empty list');
        System.assertEquals(0, sums.programFee,
            'Program fee should be 0 for empty list');
        System.assertEquals(0, sums.escrow,
            'Escrow should be 0 for empty list');
        System.assertEquals(0, sums.savingsBalance,
            'Savings balance should be 0 for empty list');
    }

    @IsTest
    static void testSeparateItemsByStatusAllScheduled() {
        // Arrange - all items are Scheduled
        PaymentPlan__c plan = getTestPlan();
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        for (Integer i = 1; i <= 5; i++) {
            items.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Number__c = 50 + i,
                Payment_Date__c = Date.today().addDays(i * 7),
                Total_Payment__c = 500,
                Status__c = 'Scheduled'
            ));
        }
        insert items;

        List<Payment_Schedule_Item__c> queriedItems = [
            SELECT Id, Payment_Number__c, Status__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :items
        ];

        List<Payment_Schedule_Item__c> nonScheduled = new List<Payment_Schedule_Item__c>();
        List<Payment_Schedule_Item__c> scheduled = new List<Payment_Schedule_Item__c>();

        // Act
        Test.startTest();
        PaymentPlanCalculationService.separateItemsByStatus(queriedItems, nonScheduled, scheduled);
        Test.stopTest();

        // Assert
        System.assertEquals(0, nonScheduled.size(),
            'No non-scheduled items expected');
        System.assertEquals(5, scheduled.size(),
            'All 5 items should be scheduled');
    }

    @IsTest
    static void testCalculatePaidSumsNullFields() {
        // Arrange - Cleared items with null fee fields
        PaymentPlan__c plan = getTestPlan();
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();

        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 90,
            Payment_Date__c = Date.today(),
            Total_Payment__c = 500,
            Setup_Fee_Amount__c = null,
            Program_Fee_Amount__c = null,
            To_Escrow_Amount__c = null,
            Savings_Balance__c = null,
            Status__c = 'Cleared'
        ));
        insert items;

        List<Payment_Schedule_Item__c> queriedItems = [
            SELECT Id, Payment_Number__c, Status__c, Setup_Fee_Amount__c,
                   Program_Fee_Amount__c, To_Escrow_Amount__c, Savings_Balance__c
            FROM Payment_Schedule_Item__c
            WHERE Id IN :items
        ];

        // Act
        Test.startTest();
        PaymentPlanCalculationService.PaidSumsWrapper sums =
            PaymentPlanCalculationService.calculatePaidSums(queriedItems);
        Test.stopTest();

        // Assert - null fields should be treated as 0
        System.assertEquals(1, sums.nonScheduledCount,
            'Should count the 1 cleared item');
        System.assertEquals(0, sums.setupFee,
            'Null setup fee should be treated as 0');
        System.assertEquals(0, sums.programFee,
            'Null program fee should be treated as 0');
        System.assertEquals(0, sums.escrow,
            'Null escrow should be treated as 0');
        System.assertEquals(0, sums.savingsBalance,
            'Null savings balance should be treated as 0');
    }

    @IsTest
    static void testPaidSumsWrapperDefaults() {
        // Arrange & Act
        Test.startTest();
        PaymentPlanCalculationService.PaidSumsWrapper wrapper =
            new PaymentPlanCalculationService.PaidSumsWrapper();
        Test.stopTest();

        // Assert - verify default values
        System.assertEquals(0, wrapper.setupFee, 'Default setupFee should be 0');
        System.assertEquals(0, wrapper.programFee, 'Default programFee should be 0');
        System.assertEquals(0, wrapper.escrow, 'Default escrow should be 0');
        System.assertEquals(0, wrapper.savingsBalance, 'Default savingsBalance should be 0');
        System.assertEquals(0, wrapper.nonScheduledCount, 'Default nonScheduledCount should be 0');
    }

    // ==================================================================================
    // recalculateDraftNumbers - Additional edge-case coverage
    // ==================================================================================

    @IsTest
    static void testRecalculateDraftNumbersBothNullPaymentNumbers() {
        // Arrange - items with same date and BOTH having null payment numbers
        // This triggers the num1==null && num2==null branch in comparePaymentNumbers
        PaymentPlan__c plan = getTestPlan();
        Date sameDate = Date.today().addDays(200);

        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id, Payment_Number__c = 201,
            Payment_Date__c = sameDate, Total_Payment__c = 100, Status__c = 'Scheduled'
        ));
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id, Payment_Number__c = 202,
            Payment_Date__c = sameDate, Total_Payment__c = 100, Status__c = 'Scheduled'
        ));
        insert items;

        List<Payment_Schedule_Item__c> insertedItems = [
            SELECT Id, Payment_Plan__c, Payment_Number__c, Payment_Date__c,
                   Total_Payment__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c WHERE Id IN :items
        ];

        // Set BOTH payment numbers to null in-memory (triggers both-null comparePaymentNumbers)
        for (Payment_Schedule_Item__c item : insertedItems) {
            item.Payment_Number__c = null;
        }

        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(insertedItems);
        Test.stopTest();

        Integer draftCount = 0;
        for (Payment_Schedule_Item__c item : insertedItems) {
            if (item.Draft_Number__c != null) draftCount++;
        }
        System.assertEquals(2, draftCount, 'Both Scheduled items should get draft numbers');
    }

    @IsTest
    static void testRecalculateDraftNumbersOneNullPaymentNumber() {
        // Arrange - items with same date, one with null payment number, one with value
        // This triggers num1==null (return 1) and num2==null (return -1) branches
        PaymentPlan__c plan = getTestPlan();
        Date sameDate = Date.today().addDays(300);

        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id, Payment_Number__c = 301,
            Payment_Date__c = sameDate, Total_Payment__c = 100, Status__c = 'Scheduled'
        ));
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id, Payment_Number__c = 302,
            Payment_Date__c = sameDate, Total_Payment__c = 100, Status__c = 'Scheduled'
        ));
        items.add(new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id, Payment_Number__c = 303,
            Payment_Date__c = sameDate, Total_Payment__c = 100, Status__c = 'Scheduled'
        ));
        insert items;

        List<Payment_Schedule_Item__c> insertedItems = [
            SELECT Id, Payment_Plan__c, Payment_Number__c, Payment_Date__c,
                   Total_Payment__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c WHERE Id IN :items
        ];

        // Set first item's payment number to null (triggers num1==null branch)
        insertedItems[0].Payment_Number__c = null;

        Test.startTest();
        PaymentPlanCalculationService.recalculateDraftNumbers(insertedItems);
        Test.stopTest();

        Integer draftCount = 0;
        for (Payment_Schedule_Item__c item : insertedItems) {
            if (item.Draft_Number__c != null) draftCount++;
        }
        System.assertEquals(3, draftCount, 'All 3 Scheduled items should get draft numbers');
    }
}
