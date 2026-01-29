// Test saveDraftV2 using the same opportunity as the user's draft
// This tests if items get created when paymentSchedule is provided

Id oppId = '006fK000003RBLtQAO';  // Same opportunity as user's draft

// Build config
Map<String, Object> config = new Map<String, Object>{
    'programType' => 'DCG_MOD',
    'paymentFrequency' => 'WEEKLY',
    'calculateBy' => 'DESIRED',
    'setupFeePayments' => 5,
    'bankingFee' => 35,
    'firstDraftDate' => Date.today().addDays(7),
    'noFeeProgram' => false
};

// Build payment schedule with 48 items
List<Map<String, Object>> paymentSchedule = new List<Map<String, Object>>();
Date startDate = Date.today().addDays(7);
for (Integer i = 1; i <= 48; i++) {
    paymentSchedule.add(new Map<String, Object>{
        'paymentNumber' => i,
        'paymentDate' => String.valueOf(startDate.addDays((i-1) * 7)),
        'totalPayment' => 500.00,
        'setupFee' => i <= 5 ? 50.00 : 0,
        'bankingFee' => 35.00,
        'programPayment' => 100.00,
        'escrowPayment' => 315.00
    });
}

// Build calculations with paymentSchedule
Map<String, Object> calculationsOptional = new Map<String, Object>{
    'totalDebt' => 100000,
    'settlementAmount' => 60000,
    'programFeeAmount' => 35000,
    'programLength' => 48,
    'weeklyPayment' => 500,
    'paymentSchedule' => paymentSchedule
};

System.debug('=== Testing saveDraftV2 with paymentSchedule of ' + paymentSchedule.size() + ' items ===');

try {
    Id newDraftId = PaymentCalculatorController.saveDraftV2(
        oppId,
        'Test With Schedule ' + String.valueOf(Datetime.now()),
        config,
        null,
        calculationsOptional
    );

    System.debug('=== Created draft: ' + newDraftId);

    // Check items
    List<Payment_Draft_Item__c> items = [
        SELECT Id, Draft_Number__c, Total_Draft__c
        FROM Payment_Draft_Item__c
        WHERE Payment_Draft__c = :newDraftId
    ];

    System.debug('=== Payment_Draft_Item__c COUNT: ' + items.size());

    if (items.isEmpty()) {
        System.debug('ERROR: NO ITEMS CREATED!');
    } else {
        System.debug('SUCCESS: ' + items.size() + ' items created');
        System.debug('First: #' + items[0].Draft_Number__c + ' = $' + items[0].Total_Draft__c);
    }
} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
