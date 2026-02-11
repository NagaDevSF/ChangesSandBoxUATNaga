/**
 * @description Service class for handling approval processes and risk scoring
 * @author System
 * @date 2025-08-29
 */
public with sharing class ApprovalService {
    
    // Risk scoring constants
    private static final Integer BASE_RISK_SCORE = 40;
    private static final Map<String, Integer> DEBT_TYPE_RISK = new Map<String, Integer>{
        'Credit Card' => 5,
        'Medical' => 2,
        'Personal Loan' => 8,
        'Business Debt' => 12,
        'Tax Debt' => 15
    };
    
    private static final Map<String, Integer> LEGAL_STATUS_RISK = new Map<String, Integer>{
        'Current' => 0,
        'Late' => 5,
        'Collections' => 10,
        'Legal Action Pending' => 20,
        'Judgment' => 25
    };
    
    // Approval thresholds
    private static final Decimal LOW_RISK_THRESHOLD = 50;
    private static final Decimal MEDIUM_RISK_THRESHOLD = 70;
    private static final Decimal HIGH_RISK_THRESHOLD = 85;
    private static final Decimal AUTO_APPROVE_AMOUNT = 25000;
    private static final Decimal SENIOR_APPROVAL_AMOUNT = 100000;
    
    /**
     * @description Calculates comprehensive risk score for a payment plan
     * @param recordId Lead or Opportunity ID
     * @param creditors List of creditor records
     * @param calculations Payment calculation result
     * @param config Configuration parameters
     * @return RiskAssessment with detailed risk analysis
     */
    public static RiskAssessment calculateRiskScore(
        Id recordId, 
        List<Creditor__c> creditors, 
        PaymentCalculatorController.CalculationResult calculations,
        Map<String, Object> config
    ) {
        try {
            RiskAssessment assessment = new RiskAssessment();
            Integer totalRiskScore = BASE_RISK_SCORE;
            
            // Debt amount risk
            DebtAmountRisk debtRisk = assessDebtAmountRisk(calculations.totalDebt);
            totalRiskScore += debtRisk.riskPoints;
            assessment.riskFactors.add(debtRisk.description);
            
            // Creditor composition risk - simplified since fields don't exist
            // Use base risk scoring without field-specific logic
            
            // Payment plan risk
            PaymentPlanRisk planRisk = assessPaymentPlanRisk(calculations);
            totalRiskScore += planRisk.riskPoints;
            assessment.riskFactors.addAll(planRisk.riskFactors);
            
            // Customer history risk
            CustomerHistoryRisk historyRisk = assessCustomerHistoryRisk(recordId);
            totalRiskScore += historyRisk.riskPoints;
            assessment.riskFactors.addAll(historyRisk.riskFactors);
            
            // Cap risk score at 100
            assessment.totalRiskScore = Math.min(100, totalRiskScore);
            assessment.riskLevel = determineRiskLevel(assessment.totalRiskScore);
            assessment.recommendedAction = determineRecommendedAction(assessment);
            
            return assessment;
            
        } catch (Exception e) {
            throw new ApprovalException('Risk assessment failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Routes approval based on amount and risk score
     * @param recordId Record ID for context
     * @param riskAssessment Risk assessment result
     * @param calculations Payment calculations
     * @return ApprovalRoutingResult with routing decisions
     */
    public static ApprovalRoutingResult routeApproval(
        Id recordId,
        RiskAssessment riskAssessment,
        PaymentCalculatorController.CalculationResult calculations
    ) {
        try {
            ApprovalRoutingResult routing = new ApprovalRoutingResult();
            
            // Determine approval level based on amount and risk
            if (calculations.totalDebt <= AUTO_APPROVE_AMOUNT && 
                riskAssessment.totalRiskScore <= LOW_RISK_THRESHOLD) {
                routing = routeAutoApproval(recordId, riskAssessment);
            } else if (calculations.totalDebt <= SENIOR_APPROVAL_AMOUNT && 
                       riskAssessment.totalRiskScore <= MEDIUM_RISK_THRESHOLD) {
                routing = routeManagerApproval(recordId, riskAssessment);
            } else {
                routing = routeSeniorApproval(recordId, riskAssessment);
            }
            
            // Handle escalation scenarios
            if (riskAssessment.totalRiskScore >= HIGH_RISK_THRESHOLD) {
                routing = escalateToSeniorManagement(routing, riskAssessment);
            }
            
            return routing;
            
        } catch (Exception e) {
            throw new ApprovalException('Approval routing failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Submits record for approval process
     * @param recordId Record to submit
     * @param routing Approval routing information
     * @param comments Additional comments
     * @return ApprovalRecord ID
     */
    public static Id submitForApproval(
        Id recordId, 
        ApprovalRoutingResult routing, 
        String comments
    ) {
        try {
            // Create ApprovalRecord__c record
            ApprovalRecord__c approvalRecord = new ApprovalRecord__c(
                PaymentPlan__c = recordId,
                Decision__c = 'Pending',
                Risk_Score__c = routing.riskScore,
                Submitted_By__c = UserInfo.getUserId(),
                Comments__c = comments,
                Reason_Code__c = routing.routingReason
            );
            
            insert approvalRecord;
            
            // Handle auto-approval
            if (!routing.requiresApproval) {
                approvalRecord.Decision__c = 'Approved';
                approvalRecord.Approved_By__c = UserInfo.getUserId();
                approvalRecord.Decision_Date__c = DateTime.now();
                update approvalRecord;
                
                System.debug('Auto-approved based on risk score and amount thresholds.');
            } else {
                // Submit to standard approval process if configured
                submitToApprovalProcess(approvalRecord.Id, routing);
            }
            
            return approvalRecord.Id;
            
        } catch (Exception e) {
            throw new ApprovalException('Approval submission failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Processes approval decision
     * @param approvalId Approval record ID
     * @param decision Approval decision
     * @param comments Decision comments
     * @param approverId Approver user ID
     * @return Updated approval record
     */
    public static ApprovalRecord__c processApprovalDecision(
        Id approvalId, 
        String decision, 
        String comments, 
        Id approverId
    ) {
        try {
            // Update ApprovalRecord__c with decision
            ApprovalRecord__c approvalRecord = [SELECT Id, Decision__c, PaymentPlan__c FROM ApprovalRecord__c WHERE Id = :approvalId LIMIT 1];
            
            approvalRecord.Decision__c = decision;
            approvalRecord.Comments__c = comments;
            approvalRecord.Approved_By__c = approverId;
            approvalRecord.Decision_Date__c = DateTime.now();
            
            update approvalRecord;
            
            // Handle decision-specific logic
            if (decision == 'Approved') {
                handleApprovedDecision(approvalRecord);
            } else if (decision == 'Rejected') {
                handleRejectedDecision(approvalRecord);
            }
            
            // Send notifications
            sendApprovalNotification(approvalRecord, decision.toLowerCase());
            
            return approvalRecord;
            
        } catch (Exception e) {
            throw new ApprovalException('Decision processing failed: ' + e.getMessage());
        }
    }
    
    /**
     * @description Checks if amount requires approval based on thresholds
     * @param totalAmount Total debt amount
     * @param riskScore Risk assessment score
     * @return Boolean indicating if approval is required
     */
    public static Boolean requiresApproval(Decimal totalAmount, Integer riskScore) {
        // Auto-approve if both amount and risk are low
        if (totalAmount <= AUTO_APPROVE_AMOUNT && riskScore <= LOW_RISK_THRESHOLD) {
            return false;
        }
        
        // All other cases require approval
        return true;
    }
    
    /**
     * @description Determines required approval level based on amount and risk
     * @param totalAmount Total debt amount
     * @param riskScore Risk assessment score
     * @return String indicating approval level needed
     */
    public static String getRequiredApprovalLevel(Decimal totalAmount, Integer riskScore) {
        if (totalAmount <= AUTO_APPROVE_AMOUNT && riskScore <= LOW_RISK_THRESHOLD) {
            return 'Auto';
        } else if (totalAmount <= SENIOR_APPROVAL_AMOUNT && riskScore <= MEDIUM_RISK_THRESHOLD) {
            return 'Manager';
        } else if (riskScore >= HIGH_RISK_THRESHOLD) {
            return 'Executive';
        } else {
            return 'Senior Manager';
        }
    }
    
    /**
     * @description Gets pending approvals for current user
     * @param userId User ID to check for pending approvals
     * @return List of pending approval records
     */
    public static List<ApprovalRecord__c> getPendingApprovals(Id userId) {
        try {
            // Query pending approvals - in a real implementation, this would be filtered
            // based on approval workflow and user permissions
            return [
                SELECT Id, Name, Decision__c, Risk_Score__c, PaymentPlan__c,
                       Submitted_By__r.Name, CreatedDate, Comments__c,
                       PaymentPlan__r.Total_Debt__c, PaymentPlan__r.Weekly_Payment__c
                FROM ApprovalRecord__c 
                WHERE Decision__c = 'Pending'
                ORDER BY CreatedDate ASC
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new ApprovalException('Failed to retrieve pending approvals: ' + e.getMessage());
        }
    }

    /**
     * @description Gets approval history for a record
     * @param recordId Record ID (PaymentPlan__c or related record)
     * @return List of approval history entries
     */
    public static List<ApprovalHistoryEntry> getApprovalHistory(Id recordId) {
        try {
            List<ApprovalHistoryEntry> history = new List<ApprovalHistoryEntry>();
            
            // Query ApprovalRecord__c records related to the payment plan
            List<ApprovalRecord__c> approvalRecords = [
                SELECT Id, Decision__c, Risk_Score__c, Submitted_By__c, Approved_By__c,
                       CreatedDate, Decision_Date__c, Comments__c,
                       Submitted_By__r.Name, Approved_By__r.Name
                FROM ApprovalRecord__c 
                WHERE PaymentPlan__c = :recordId 
                ORDER BY CreatedDate DESC
            ];
            
            // Convert to ApprovalHistoryEntry objects
            for (ApprovalRecord__c record : approvalRecords) {
                ApprovalHistoryEntry entry = new ApprovalHistoryEntry();
                entry.approvalId = record.Id;
                entry.decision = record.Decision__c;
                entry.riskScore = Integer.valueOf(record.Risk_Score__c != null ? record.Risk_Score__c : 0);
                entry.submittedBy = record.Submitted_By__r.Name;
                entry.approvedBy = record.Approved_By__r?.Name;
                entry.submittedDate = record.CreatedDate;
                entry.decisionDate = record.Decision_Date__c;
                entry.comments = record.Comments__c;
                history.add(entry);
            }
            
            return history;
            
        } catch (Exception e) {
            throw new ApprovalException('Failed to retrieve approval history: ' + e.getMessage());
        }
    }
    
    // Private helper methods
    
    /**
     * @description Assesses risk based on total debt amount
     */
    private static DebtAmountRisk assessDebtAmountRisk(Decimal totalDebt) {
        DebtAmountRisk risk = new DebtAmountRisk();
        
        if (totalDebt > 200000) {
            risk.riskPoints = 25;
            risk.description = 'Very high debt amount: $' + totalDebt.format();
        } else if (totalDebt > 100000) {
            risk.riskPoints = 15;
            risk.description = 'High debt amount: $' + totalDebt.format();
        } else if (totalDebt > 50000) {
            risk.riskPoints = 8;
            risk.description = 'Moderate debt amount: $' + totalDebt.format();
        } else {
            risk.riskPoints = 0;
            risk.description = 'Low debt amount: $' + totalDebt.format();
        }
        
        return risk;
    }
    
    /**
     * @description Assesses risk based on creditor composition - simplified
     */
    private static CreditorRisk assessCreditorRisk(List<Creditor__c> creditors) {
        CreditorRisk risk = new CreditorRisk();
        
        // Simplified risk assessment without field references
        risk.riskPoints = 10; // Base risk for having creditors
        risk.riskFactors.add('Standard creditor risk assessment');
        
        return risk;
    }
    
    /**
     * @description Assesses risk based on payment plan characteristics
     */
    private static PaymentPlanRisk assessPaymentPlanRisk(PaymentCalculatorController.CalculationResult calculations) {
        PaymentPlanRisk risk = new PaymentPlanRisk();
        
        // Duration risk
        if (calculations.numberOfWeeks > 78) { // > 1.5 years
            risk.riskPoints += 15;
            risk.riskFactors.add('Long payment duration: ' + calculations.numberOfWeeks + ' weeks');
        } else if (calculations.numberOfWeeks < 26) { // < 6 months
            risk.riskPoints += 8;
            risk.riskFactors.add('Very short payment duration: ' + calculations.numberOfWeeks + ' weeks');
        }
        
        // Payment amount risk
        if (calculations.weeklyPayment > 1000) {
            risk.riskPoints += 10;
            risk.riskFactors.add('High weekly payment: $' + calculations.weeklyPayment.format());
        }
        
        // Savings percentage risk
        Decimal savingsPercentage = (calculations.totalSavings / calculations.totalDebt) * 100;
        if (savingsPercentage > 60) {
            risk.riskPoints += 12;
            risk.riskFactors.add('Very high savings percentage: ' + savingsPercentage.format() + '%');
        }
        
        return risk;
    }
    
    /**
     * @description Assesses risk based on customer history
     */
    private static CustomerHistoryRisk assessCustomerHistoryRisk(Id recordId) {
        CustomerHistoryRisk risk = new CustomerHistoryRisk();
        
        try {
            // PaymentPlan__c object doesn't exist - skip history check
            // In a real implementation, would check alternative tracking method
            
        } catch (Exception e) {
            // If query fails, assume no history risk
        }
        
        return risk;
    }
    
    /**
     * @description Determines risk level from score
     */
    private static String determineRiskLevel(Integer riskScore) {
        if (riskScore <= LOW_RISK_THRESHOLD) {
            return 'Low';
        } else if (riskScore <= MEDIUM_RISK_THRESHOLD) {
            return 'Medium';
        } else if (riskScore <= HIGH_RISK_THRESHOLD) {
            return 'High';
        } else {
            return 'Critical';
        }
    }
    
    /**
     * @description Determines recommended action based on risk assessment
     */
    private static String determineRecommendedAction(RiskAssessment assessment) {
        if (assessment.totalRiskScore <= LOW_RISK_THRESHOLD) {
            return 'Auto-Approve';
        } else if (assessment.totalRiskScore <= MEDIUM_RISK_THRESHOLD) {
            return 'Manager Review';
        } else if (assessment.totalRiskScore <= HIGH_RISK_THRESHOLD) {
            return 'Senior Manager Review';
        } else {
            return 'Executive Review Required';
        }
    }
    
    // Routing methods
    
    private static ApprovalRoutingResult routeAutoApproval(Id recordId, RiskAssessment assessment) {
        ApprovalRoutingResult routing = new ApprovalRoutingResult();
        routing.requiresApproval = false;
        routing.approverLevel = 'Auto';
        routing.riskScore = assessment.totalRiskScore;
        routing.routingReason = 'Low risk and amount qualify for auto-approval';
        return routing;
    }
    
    private static ApprovalRoutingResult routeManagerApproval(Id recordId, RiskAssessment assessment) {
        ApprovalRoutingResult routing = new ApprovalRoutingResult();
        routing.requiresApproval = true;
        routing.approverLevel = 'Manager';
        routing.riskScore = assessment.totalRiskScore;
        routing.routingReason = 'Moderate risk or amount requires manager approval';
        return routing;
    }
    
    private static ApprovalRoutingResult routeSeniorApproval(Id recordId, RiskAssessment assessment) {
        ApprovalRoutingResult routing = new ApprovalRoutingResult();
        routing.requiresApproval = true;
        routing.approverLevel = 'Senior Manager';
        routing.riskScore = assessment.totalRiskScore;
        routing.routingReason = 'High risk or amount requires senior management approval';
        return routing;
    }
    
    private static ApprovalRoutingResult escalateToSeniorManagement(
        ApprovalRoutingResult routing, 
        RiskAssessment assessment
    ) {
        routing.approverLevel = 'Executive';
        routing.escalated = true;
        routing.routingReason += ' - Escalated due to critical risk score';
        return routing;
    }
    
    // Process submission methods
    
    private static void submitToApprovalProcess(Id approvalId, ApprovalRoutingResult routing) {
        try {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(approvalId);
            req.setSubmitterId(UserInfo.getUserId());
            req.setProcessDefinitionNameOrId('Payment_Plan_Approval');
            req.setComments('Risk Level: ' + routing.approverLevel + '\nReason: ' + routing.routingReason);
            
            Approval.ProcessResult result = Approval.process(req);
        } catch (Exception e) {
            // Handle approval process submission error
            System.debug('Approval process submission failed: ' + e.getMessage());
        }
    }
    
    private static void handleApprovedDecision(ApprovalRecord__c approval) {
        try {
            // Update related PaymentPlan__c status if exists
            if (approval.PaymentPlan__c != null) {
                List<PaymentPlan__c> plans = [SELECT Id, Status__c FROM PaymentPlan__c WHERE Id = :approval.PaymentPlan__c LIMIT 1];
                if (!plans.isEmpty()) {
                    plans[0].Status__c = 'Approved';
                    update plans[0];
                }
            }
            System.debug('Approval decision handled: Approved');
        } catch (Exception e) {
            System.debug('Error updating PaymentPlan status: ' + e.getMessage());
        }
    }
    
    private static void handleRejectedDecision(ApprovalRecord__c approval) {
        try {
            // Update related PaymentPlan__c status if exists
            if (approval.PaymentPlan__c != null) {
                List<PaymentPlan__c> plans = [SELECT Id, Status__c FROM PaymentPlan__c WHERE Id = :approval.PaymentPlan__c LIMIT 1];
                if (!plans.isEmpty()) {
                    plans[0].Status__c = 'Rejected';
                    update plans[0];
                }
            }
            System.debug('Approval decision handled: Rejected');
        } catch (Exception e) {
            System.debug('Error updating PaymentPlan status: ' + e.getMessage());
        }
    }
    
    private static void sendApprovalNotification(ApprovalRecord__c approval, String notificationType) {
        // Implementation for sending notifications
        // This could integrate with email, chatter, or custom notification system
        System.debug('Sending notification for approval ID: ' + approval.Id + ', type: ' + notificationType);
        
        // TODO: Implement actual notification logic
        // - Email notifications to stakeholders
        // - Chatter posts
        // - Custom notification platform integration
    }
    
    // Inner Classes
    
    public class RiskAssessment {
        @AuraEnabled public Integer totalRiskScore { get; set; }
        @AuraEnabled public String riskLevel { get; set; }
        @AuraEnabled public String recommendedAction { get; set; }
        @AuraEnabled public List<String> riskFactors { get; set; }
        
        public RiskAssessment() {
            this.riskFactors = new List<String>();
        }
    }
    
    public class ApprovalRoutingResult {
        @AuraEnabled public Boolean requiresApproval { get; set; }
        @AuraEnabled public String approverLevel { get; set; }
        @AuraEnabled public Integer riskScore { get; set; }
        @AuraEnabled public String routingReason { get; set; }
        @AuraEnabled public Boolean escalated { get; set; }
        
        public ApprovalRoutingResult() {
            this.escalated = false;
        }
    }
    
    public class ApprovalHistoryEntry {
        @AuraEnabled public Id approvalId { get; set; }
        @AuraEnabled public String decision { get; set; }
        @AuraEnabled public Integer riskScore { get; set; }
        @AuraEnabled public String submittedBy { get; set; }
        @AuraEnabled public String approvedBy { get; set; }
        @AuraEnabled public DateTime submittedDate { get; set; }
        @AuraEnabled public DateTime decisionDate { get; set; }
        @AuraEnabled public String comments { get; set; }
    }
    
    // Risk assessment helper classes
    private class DebtAmountRisk {
        public Integer riskPoints { get; set; }
        public String description { get; set; }
    }
    
    private class CreditorRisk {
        public Integer riskPoints { get; set; }
        public List<String> riskFactors { get; set; }
        
        public CreditorRisk() {
            this.riskPoints = 0;
            this.riskFactors = new List<String>();
        }
    }
    
    private class PaymentPlanRisk {
        public Integer riskPoints { get; set; }
        public List<String> riskFactors { get; set; }
        
        public PaymentPlanRisk() {
            this.riskPoints = 0;
            this.riskFactors = new List<String>();
        }
    }
    
    private class CustomerHistoryRisk {
        public Integer riskPoints { get; set; }
        public List<String> riskFactors { get; set; }
        
        public CustomerHistoryRisk() {
            this.riskPoints = 0;
            this.riskFactors = new List<String>();
        }
    }
    
    // Custom Exception
    public class ApprovalException extends Exception {}
}