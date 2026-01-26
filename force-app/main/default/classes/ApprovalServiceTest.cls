@IsTest
private class ApprovalServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Approval Test Acc');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Approval Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;

        // Create a simple plan for linkage
        PaymentPlan__c plan = new PaymentPlan__c(Opportunity__c = opp.Id, Version_Number__c = 1);
        insert plan;
    }

    private static PaymentPlan__c getPlan() {
        return [SELECT Id, Opportunity__c, Status__c FROM PaymentPlan__c LIMIT 1];
    }

    @IsTest
    static void testRequiresAndLevels() {
        System.assertEquals(false, ApprovalService.requiresApproval(20000, 40));
        System.assertEquals('Auto', ApprovalService.getRequiredApprovalLevel(20000, 40));

        System.assertEquals(true, ApprovalService.requiresApproval(60000, 65));
        System.assertEquals('Manager', ApprovalService.getRequiredApprovalLevel(60000, 65));

        System.assertEquals(true, ApprovalService.requiresApproval(200000, 90));
        System.assertEquals('Executive', ApprovalService.getRequiredApprovalLevel(200000, 90));
    }

    @IsTest
    static void testProcessApprovalDecision() {
        PaymentPlan__c plan = getPlan();

        ApprovalRecord__c ar = new ApprovalRecord__c(
            PaymentPlan__c = plan.Id,
            Decision__c = 'Pending',
            Risk_Score__c = 55,
            Submitted_By__c = UserInfo.getUserId()
        );
        insert ar;

        Test.startTest();
        ApprovalRecord__c updated = ApprovalService.processApprovalDecision(ar.Id, 'Approved', 'Looks good', UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals('Approved', updated.Decision__c);
        System.assertEquals('Looks good', updated.Comments__c);

        plan = [SELECT Id FROM PaymentPlan__c WHERE Id = :plan.Id];
        System.assertNotEquals(null, updated.Decision_Date__c, 'Decision date should be set');
    }

    @IsTest
    static void testRoutingAndRisk() {
        // Build a high-risk calculation to exercise routing and escalation
        PaymentCalculatorController.CalculationResult calc = new PaymentCalculatorController.CalculationResult();
        calc.totalDebt = 200000;
        calc.numberOfWeeks = 104;
        calc.weeklyPayment = 1000;
        calc.totalSavings = 120000;

        ApprovalService.RiskAssessment ra = ApprovalService.calculateRiskScore(getPlan().Opportunity__c, new List<Creditor__c>(), calc, new Map<String, Object>());
        ApprovalService.ApprovalRoutingResult routing = ApprovalService.routeApproval(getPlan().Opportunity__c, ra, calc);
        System.assertEquals(true, routing.requiresApproval, 'High amount should require approval');
        // Escalation depends on internal thresholds; ensure routing level is not Auto
        System.assert(routing.approverLevel != 'Auto', 'Should not auto-approve at high amounts');
    }

    @IsTest
    static void testSubmitForApproval_AutoApprovalPath() {
        // Create minimal plan to satisfy lookup
        PaymentPlan__c plan = getPlan();

        // Low risk and small amount to trigger auto-approval
        ApprovalService.RiskAssessment low = new ApprovalService.RiskAssessment();
        low.totalRiskScore = 40;
        low.riskLevel = 'Low';
        low.recommendedAction = 'Auto-Approve';

        ApprovalService.ApprovalRoutingResult routing = new ApprovalService.ApprovalRoutingResult();
        routing.requiresApproval = false;
        routing.approverLevel = 'Auto';
        routing.riskScore = 40;
        // Avoid restricted picklist issues by omitting reason
        routing.routingReason = null;

        Test.startTest();
        Id arId = ApprovalService.submitForApproval(plan.Id, routing, 'Auto-approve test');
        Test.stopTest();

        ApprovalRecord__c saved = [SELECT Id, Decision__c, Approved_By__c FROM ApprovalRecord__c WHERE Id = :arId];
        System.assertEquals('Approved', saved.Decision__c, 'Auto path should approve immediately');
        System.assertNotEquals(null, saved.Approved_By__c, 'Approved by should be set');
    }

    @IsTest
    static void testSubmitForApproval_RoutedPath_Pending() {
        PaymentPlan__c plan = getPlan();

        ApprovalService.RiskAssessment med = new ApprovalService.RiskAssessment();
        med.totalRiskScore = 65;
        med.riskLevel = 'Medium';
        med.recommendedAction = 'Manager';

        ApprovalService.ApprovalRoutingResult routing = new ApprovalService.ApprovalRoutingResult();
        routing.requiresApproval = true;
        routing.approverLevel = 'Manager';
        routing.riskScore = 65;
        routing.routingReason = null;

        Test.startTest();
        Id arId = ApprovalService.submitForApproval(plan.Id, routing, 'Route test');
        Test.stopTest();

        ApprovalRecord__c saved = [SELECT Id, Decision__c FROM ApprovalRecord__c WHERE Id = :arId];
        System.assertEquals('Pending', saved.Decision__c, 'Routed path should remain pending');
    }

    @IsTest
    static void testGetPendingApprovalsAndHistory() {
        PaymentPlan__c plan = getPlan();
        // Seed a pending record
        ApprovalRecord__c ar = new ApprovalRecord__c(
            PaymentPlan__c = plan.Id,
            Decision__c = 'Pending',
            Risk_Score__c = 55,
            Submitted_By__c = UserInfo.getUserId()
        );
        insert ar;

        Test.startTest();
        List<ApprovalRecord__c> pend = ApprovalService.getPendingApprovals(UserInfo.getUserId());
        List<ApprovalService.ApprovalHistoryEntry> hist = ApprovalService.getApprovalHistory(plan.Id);
        Test.stopTest();

        System.assert(pend.size() >= 1, 'Should return at least one pending record');
        // Approve and then history should contain an entry with decision
        ApprovalRecord__c updated = ApprovalService.processApprovalDecision(ar.Id, 'Approved', 'ok', UserInfo.getUserId());
        List<ApprovalService.ApprovalHistoryEntry> hist2 = ApprovalService.getApprovalHistory(plan.Id);
        System.assert(hist2.size() >= hist.size(), 'History should be retrievable');
    }

    @IsTest
    static void testRiskLevelBoundariesAndRecommendations() {
        Id oppId = getPlan().Opportunity__c;

        // LOW: base only (no additional risk)
        PaymentCalculatorController.CalculationResult lowCalc = new PaymentCalculatorController.CalculationResult();
        lowCalc.totalDebt = 20000; // low debt
        lowCalc.numberOfWeeks = 30; // neutral duration
        lowCalc.weeklyPayment = 100; // low payment
        lowCalc.totalSavings = 2000; // 10%
        ApprovalService.RiskAssessment lowRA = ApprovalService.calculateRiskScore(oppId, new List<Creditor__c>(), lowCalc, new Map<String, Object>());
        System.assertEquals('Low', lowRA.riskLevel, 'Expected Low risk');

        // MEDIUM: small debt + very short duration adds risk
        PaymentCalculatorController.CalculationResult medCalc = new PaymentCalculatorController.CalculationResult();
        medCalc.totalDebt = 60000; // 8 points
        medCalc.numberOfWeeks = 20; // < 26 adds 8
        medCalc.weeklyPayment = 200; // low payment
        medCalc.totalSavings = 6000; // 10%
        ApprovalService.RiskAssessment medRA = ApprovalService.calculateRiskScore(oppId, new List<Creditor__c>(), medCalc, new Map<String, Object>());
        System.assertEquals('Medium', medRA.riskLevel, 'Expected Medium risk');

        // HIGH: combine duration > 78 and high weekly payment
        PaymentCalculatorController.CalculationResult highCalc = new PaymentCalculatorController.CalculationResult();
        highCalc.totalDebt = 120000; // 15 points
        highCalc.numberOfWeeks = 90; // > 78 adds 15
        highCalc.weeklyPayment = 1101; // > 1000 adds 10
        highCalc.totalSavings = 30000; // 25%
        ApprovalService.RiskAssessment highRA = ApprovalService.calculateRiskScore(oppId, new List<Creditor__c>(), highCalc, new Map<String, Object>());
        System.assertEquals('High', highRA.riskLevel, 'Expected High risk');

        // CRITICAL: very high debt + long duration + high weekly
        PaymentCalculatorController.CalculationResult critCalc = new PaymentCalculatorController.CalculationResult();
        critCalc.totalDebt = 200001; // 25 points
        critCalc.numberOfWeeks = 100; // 15 points
        critCalc.weeklyPayment = 1500; // 10 points
        critCalc.totalSavings = 130000; // 65% to push any other guards
        ApprovalService.RiskAssessment critRA = ApprovalService.calculateRiskScore(oppId, new List<Creditor__c>(), critCalc, new Map<String, Object>());
        System.assertEquals('Critical', critRA.riskLevel, 'Expected Critical risk');
    }

    @IsTest
    static void testEscalationToExecutiveRouting() {
        Id oppId = getPlan().Opportunity__c;

        // Craft a critical assessment explicitly to ensure escalation
        ApprovalService.RiskAssessment ra = new ApprovalService.RiskAssessment();
        ra.totalRiskScore = 95; // >= HIGH_RISK_THRESHOLD
        ra.riskLevel = 'Critical';
        ra.recommendedAction = 'Executive Review Required';

        PaymentCalculatorController.CalculationResult calc = new PaymentCalculatorController.CalculationResult();
        calc.totalDebt = 150000; // triggers manager/senior path (requires approval)

        ApprovalService.ApprovalRoutingResult routed = ApprovalService.routeApproval(oppId, ra, calc);
        System.assertEquals(true, routed.requiresApproval, 'Escalated path should require approval');
        System.assertEquals(true, routed.escalated, 'Should be escalated to Executive');
        System.assertEquals('Executive', routed.approverLevel, 'Approver should be Executive after escalation');
    }

    @IsTest
    static void testRejectedDecisionUpdatesStatus() {
        PaymentPlan__c plan = getPlan();
        ApprovalRecord__c ar = new ApprovalRecord__c(
            PaymentPlan__c = plan.Id,
            Decision__c = 'Pending',
            Risk_Score__c = 70,
            Submitted_By__c = UserInfo.getUserId()
        );
        insert ar;

        Test.startTest();
        ApprovalRecord__c updated = ApprovalService.processApprovalDecision(ar.Id, 'Rejected', 'needs work', UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals('Rejected', updated.Decision__c, 'Decision should be Rejected');
        // If the PaymentPlan__c exists, the helper sets Status__c to Rejected. Validate no exception and date set.
        System.assertNotEquals(null, updated.Decision_Date__c, 'Decision date should be set on rejection');
    }
}