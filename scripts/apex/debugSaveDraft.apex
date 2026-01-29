// Debug script to test saveDraftV2 and Payment_Draft_Item__c creation
// Test with an existing Opportunity

// Find an opportunity with a recent draft
List<PaymentDraft__c> recentDrafts = [
    SELECT Id, Draft_Name__c, Opportunity__c, Opportunity__r.Name,
           Weekly_Payment__c, Number_of_Weeks__c, Settlement_Amount__c,
           Program_Fee_Amount__c, Banking_Fee__c, First_Draft_Date__c
    FROM PaymentDraft__c
    WHERE Opportunity__c != null
    ORDER BY CreatedDate DESC
    LIMIT 1
];

if (recentDrafts.isEmpty()) {
    System.debug('ERROR: No drafts found');
    return;
}

PaymentDraft__c draft = recentDrafts[0];
System.debug('=== Testing with Draft: ' + draft.Id + ' ===');
System.debug('Opportunity: ' + draft.Opportunity__r.Name);
System.debug('Weekly Payment: ' + draft.Weekly_Payment__c);
System.debug('Number of Weeks: ' + draft.Number_of_Weeks__c);

// Check if this draft has any Payment_Draft_Item__c records
List<Payment_Draft_Item__c> existingItems = [
    SELECT Id, Draft_Number__c, Total_Draft__c, Is_Active__c
    FROM Payment_Draft_Item__c
    WHERE Payment_Draft__c = :draft.Id
];
System.debug('Existing Payment_Draft_Item__c count: ' + existingItems.size());

// Now let's manually test creating items
// First, build a mock payment schedule
Integer numWeeks = draft.Number_of_Weeks__c != null ? draft.Number_of_Weeks__c.intValue() : 52;
Decimal weeklyPayment = draft.Weekly_Payment__c != null ? draft.Weekly_Payment__c : 500;
Date firstDate = draft.First_Draft_Date__c != null ? draft.First_Draft_Date__c : Date.today().addDays(7);

System.debug('=== Building test payment schedule ===');
System.debug('numWeeks: ' + numWeeks);
System.debug('weeklyPayment: ' + weeklyPayment);
System.debug('firstDate: ' + firstDate);

// Create test payment draft items directly
List<Payment_Draft_Item__c> testItems = new List<Payment_Draft_Item__c>();
for (Integer i = 1; i <= Math.min(numWeeks, 5); i++) { // Only create 5 for testing
    Payment_Draft_Item__c item = new Payment_Draft_Item__c();
    item.Payment_Draft__c = draft.Id;
    item.Draft_Number__c = i;
    item.Total_Draft__c = weeklyPayment;
    item.Banking_Fee__c = 10;
    item.Setup_Fee__c = i <= 5 ? 50 : 0;
    item.Savings__c = weeklyPayment * 0.4;
    item.Program_Fee__c = weeklyPayment * 0.2;
    item.Draft_Due_Date__c = firstDate.addDays((i - 1) * 7);
    item.Is_Active__c = true;
    item.Calculation_Version__c = 1;
    testItems.add(item);
}

System.debug('=== Attempting to insert ' + testItems.size() + ' test items ===');

try {
    insert testItems;
    System.debug('SUCCESS: Inserted ' + testItems.size() + ' Payment_Draft_Item__c records');
    for (Payment_Draft_Item__c item : testItems) {
        System.debug('  Item ' + item.Draft_Number__c + ': Id=' + item.Id + ', Total=' + item.Total_Draft__c);
    }
} catch (Exception e) {
    System.debug('ERROR inserting items: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
}

// Verify the items were created
List<Payment_Draft_Item__c> verifyItems = [
    SELECT Id, Draft_Number__c, Total_Draft__c, Is_Active__c
    FROM Payment_Draft_Item__c
    WHERE Payment_Draft__c = :draft.Id AND Is_Active__c = true
    ORDER BY Draft_Number__c
];
System.debug('=== Verification: Found ' + verifyItems.size() + ' active items ===');
