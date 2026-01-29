// Test saveDraftV2 with the EXACT field names that LWC's convertScheduleForDisplay sends
// This helps identify if the field name mapping is the issue

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

// Build payment schedule using EXACT field names from LWC's convertScheduleForDisplay
// This is what the LWC actually sends:
//   draftNumber (not paymentNumber)
//   paymentAmount/totalPayment/draftAmount (instead of totalPayment)
//   programFee/programPortion (instead of programPayment)
//   escrowAmount/savingsBalance (instead of escrowPayment)
//   runningBalance/runningTotal (instead of remainingBalance)
List<Map<String, Object>> paymentSchedule = new List<Map<String, Object>>();
Date startDate = Date.today().addDays(7);
for (Integer i = 1; i <= 48; i++) {
    Map<String, Object> item = new Map<String, Object>{
        // LWC field names from convertScheduleForDisplay
        'id' => 'schedule-' + i,
        'draftNumber' => i,
        'paymentDate' => String.valueOf(startDate.addDays((i-1) * 7)),
        'paymentAmount' => 500.00,
        'totalPayment' => 500.00,
        'draftAmount' => 500.00,
        'retainerFee' => 0,
        'setupFee' => i <= 5 ? 50.00 : 0,
        'setupFeePortion' => i <= 5 ? 50.00 : 0,
        'programFee' => 100.00,
        'programPortion' => 100.00,
        'bankingFee' => 35.00,
        'bankingFeePortion' => 35.00,
        'bank2Fee' => 0,
        'bank2Portion' => 0,
        'additionalProducts' => 0,
        'escrowAmount' => 315.00,
        'savingsBalance' => 315.00,
        'runningBalance' => 100000 - (i * 315),
        'runningTotal' => 100000 - (i * 315)
    };
    paymentSchedule.add(item);
}

// Build calculationsOptional map using LWC field names
Map<String, Object> calculationsOptional = new Map<String, Object>{
    'totalDebt' => 100000,
    'currentPayment' => 1000,
    'settlementAmount' => 60000,
    'programFeeAmount' => 35000,  // LWC uses programFeeAmount
    'setupFeeTotal' => 1500,
    'bankingFeeTotal' => 1680,
    'totalProgramCost' => 98180,  // LWC uses totalProgramCost
    'savingsAmount' => 1820,      // LWC uses savingsAmount
    'programLength' => 48,        // LWC uses programLength
    'weeklyPayment' => 500,
    'paymentSchedule' => paymentSchedule
};

System.debug('=== Testing with LWC field names ===');
System.debug('=== paymentSchedule size: ' + paymentSchedule.size());
System.debug('=== First schedule item keys: ' + paymentSchedule[0].keySet());
System.debug('=== First schedule item: ' + paymentSchedule[0]);

// Call saveDraftV2
try {
    Id newDraftId = PaymentCalculatorController.saveDraftV2(
        oppId,
        'LWC Field Names Test ' + String.valueOf(Datetime.now()),
        config,
        null,  // no overwrite - create new
        calculationsOptional
    );
    System.debug('=== SUCCESS: Created draft with Id: ' + newDraftId);

    // Check if items were created
    List<Payment_Draft_Item__c> items = [
        SELECT Id, Draft_Number__c, Total_Draft__c, Is_Active__c,
               Banking_Fee__c, Setup_Fee__c, Savings__c, Program_Fee__c
        FROM Payment_Draft_Item__c
        WHERE Payment_Draft__c = :newDraftId
        ORDER BY Draft_Number__c
    ];
    System.debug('=== Payment_Draft_Item__c count: ' + items.size());
    if (!items.isEmpty()) {
        System.debug('=== First item: Draft#=' + items[0].Draft_Number__c + ', Total=' + items[0].Total_Draft__c +
                     ', Banking=' + items[0].Banking_Fee__c + ', Setup=' + items[0].Setup_Fee__c +
                     ', Savings=' + items[0].Savings__c + ', Program=' + items[0].Program_Fee__c);
        System.debug('=== Last item: Draft#=' + items[items.size()-1].Draft_Number__c + ', Total=' + items[items.size()-1].Total_Draft__c);
    } else {
        System.debug('=== ERROR: No Payment_Draft_Item__c records created!');
    }
} catch (Exception e) {
    System.debug('=== ERROR: ' + e.getMessage());
    System.debug('=== Stack: ' + e.getStackTraceString());
}
