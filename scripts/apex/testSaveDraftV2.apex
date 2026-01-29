// Test saveDraftV2 method simulating what LWC sends
// This will show debug logs to identify the issue

// Find an opportunity to test with
List<Opportunity> opps = [SELECT Id, Name FROM Opportunity ORDER BY CreatedDate DESC LIMIT 1];
if (opps.isEmpty()) {
    System.debug('ERROR: No opportunities found');
    return;
}
Id oppId = opps[0].Id;
System.debug('Testing with Opportunity: ' + opps[0].Name + ' (' + oppId + ')');

// Build config map (simulating LWC)
Map<String, Object> config = new Map<String, Object>{
    'programType' => 'DCG_MOD',
    'paymentFrequency' => 'WEEKLY',
    'calculateBy' => 'DESIRED',
    'targetPaymentPercent' => 50,
    'setupFeePayments' => 5,
    'setupFeeTotal' => 1500,
    'bankingFee' => 35,
    'firstDraftDate' => Date.today().addDays(7),
    'noFeeProgram' => false
};

// Build payment schedule (simulating what LWC would send)
List<Map<String, Object>> paymentSchedule = new List<Map<String, Object>>();
Date startDate = Date.today().addDays(7);
for (Integer i = 1; i <= 48; i++) {
    Map<String, Object> item = new Map<String, Object>{
        'paymentNumber' => i,
        'paymentDate' => String.valueOf(startDate.addDays((i-1) * 7)),
        'totalPayment' => 500.00,
        'setupFee' => i <= 5 ? 50.00 : 0,
        'bankingFee' => 35.00,
        'programPayment' => 100.00,
        'escrowPayment' => 315.00
    };
    paymentSchedule.add(item);
}

// Build calculationsOptional map (simulating LWC)
Map<String, Object> calculationsOptional = new Map<String, Object>{
    'totalDebt' => 100000,
    'currentPayment' => 1000,
    'settlementAmount' => 60000,
    'programFeeAmount' => 35000,
    'setupFeeTotal' => 1500,
    'bankingFeeTotal' => 1680,
    'totalProgramCost' => 98180,
    'savingsAmount' => 1820,
    'programLength' => 48,
    'weeklyPayment' => 500,
    'paymentSchedule' => paymentSchedule
};

System.debug('=== Config keys: ' + config.keySet());
System.debug('=== calculationsOptional keys: ' + calculationsOptional.keySet());
System.debug('=== paymentSchedule size: ' + paymentSchedule.size());
System.debug('=== First schedule item: ' + paymentSchedule[0]);

// Call saveDraftV2
try {
    Id newDraftId = PaymentCalculatorController.saveDraftV2(
        oppId,
        'Test Draft ' + String.valueOf(Datetime.now()),
        config,
        null,  // no overwrite - create new
        calculationsOptional
    );
    System.debug('=== SUCCESS: Created draft with Id: ' + newDraftId);

    // Check if items were created
    List<Payment_Draft_Item__c> items = [
        SELECT Id, Draft_Number__c, Total_Draft__c, Is_Active__c
        FROM Payment_Draft_Item__c
        WHERE Payment_Draft__c = :newDraftId
        ORDER BY Draft_Number__c
    ];
    System.debug('=== Payment_Draft_Item__c count: ' + items.size());
    if (!items.isEmpty()) {
        System.debug('=== First item: Draft#=' + items[0].Draft_Number__c + ', Total=' + items[0].Total_Draft__c);
        System.debug('=== Last item: Draft#=' + items[items.size()-1].Draft_Number__c + ', Total=' + items[items.size()-1].Total_Draft__c);
    }
} catch (Exception e) {
    System.debug('=== ERROR: ' + e.getMessage());
    System.debug('=== Stack: ' + e.getStackTraceString());
}
