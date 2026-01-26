/**
 * @description LWC Controller for Settlement Plan Calculator.
 *              Provides @AuraEnabled methods for Lightning components to invoke
 *              settlement plan calculations and save results.
 * @author Settlement Calculator Team
 * @date December 2025
 *
 * ============================================================================
 * ASSUMPTIONS DOCUMENTED IN THIS FILE:
 * ============================================================================
 * UI/UX:
 * U1: LWC is a HEADLESS quick action (no preview before save)
 * U2: calculateAndSavePlan always deletes existing items (deleteExisting defaults to true)
 *
 * Note: The LWC component (calculatePaymentPlanButton) calls calculateAndSavePlan
 * with deleteExisting=true, meaning it always replaces existing payment items.
 * ============================================================================
 */
public with sharing class SettlementPlanCalculatorController {

    /**
     * @description Calculate settlement plan items from segments (preview only, no save)
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return CalculationResult with generated items and summary
     */
    @AuraEnabled
    public static SettlementPlanCalculatorService.CalculationResult calculatePlan(Id creditorOpportunityId) {
        try {
            // Validate input
            if (creditorOpportunityId == null) {
                SettlementPlanCalculatorService.CalculationResult result =
                    new SettlementPlanCalculatorService.CalculationResult();
                result.success = false;
                result.errorMessage = 'Creditor Opportunity ID is required.';
                return result;
            }

            // Create service and calculate
            SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
            return service.calculatePlan(creditorOpportunityId);

        } catch (Exception e) {
            SettlementPlanCalculatorService.CalculationResult result =
                new SettlementPlanCalculatorService.CalculationResult();
            result.success = false;
            result.errorMessage = 'Error calculating plan: ' + e.getMessage();
            return result;
        }
    }

    /**
     * @description Calculate and save settlement plan items
     *
     * ASSUMPTION U1: This is called from a HEADLESS quick action
     * - No preview step, calculates and saves immediately
     * - User sees toast notification with result
     *
     * ASSUMPTION U2: deleteExisting defaults to true
     * - If deleteExisting is null or not provided, it defaults to true
     * - This means existing payment items are ALWAYS replaced
     * - The LWC component hardcodes deleteExisting=true
     *
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @param deleteExisting Whether to delete existing items before saving
     * @return CalculationResult with saved items
     */
    @AuraEnabled
    public static SettlementPlanCalculatorService.CalculationResult calculateAndSavePlan(
        Id creditorOpportunityId,
        Boolean deleteExisting
    ) {
        try {
            // Validate input
            if (creditorOpportunityId == null) {
                SettlementPlanCalculatorService.CalculationResult result =
                    new SettlementPlanCalculatorService.CalculationResult();
                result.success = false;
                result.errorMessage = 'Creditor Opportunity ID is required.';
                return result;
            }

            // ASSUMPTION U2: deleteExisting defaults to true (always replace)
            // Create service and calculate + save
            SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
            return service.saveCalculation(creditorOpportunityId, deleteExisting != false);

        } catch (Exception e) {
            SettlementPlanCalculatorService.CalculationResult result =
                new SettlementPlanCalculatorService.CalculationResult();
            result.success = false;
            result.errorMessage = 'Error saving plan: ' + e.getMessage();
            return result;
        }
    }

    /**
     * @description Get segments for a CreditorOpportunity
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return List of Settlement_Segment__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Settlement_Segment__c> getSegments(Id creditorOpportunityId) {
        if (creditorOpportunityId == null) {
            return new List<Settlement_Segment__c>();
        }
        return [
            SELECT Id,
                   Name,
                   Segment_Order__c,
                   Segment_Type__c,
                   Payment_Amount__c,
                   Payment_Count__c,
                   Calculated_Amount__c,
                   Calculated_Count__c,
                   Frequency__c,
                   Start_Date__c,
                   End_Date__c,
                   Segment_Total__c,
                   Is_First_Segment__c,
                   Continues_From_Previous__c
            FROM Settlement_Segment__c
            WHERE Creditors_List__c = :creditorOpportunityId
            ORDER BY Segment_Order__c ASC
        ];
    }

    /**
     * @description Get existing settlement plan items for a CreditorOpportunity
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return List of Settlement_Plan_Item__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Settlement_Plan_Item__c> getExistingPlanItems(Id creditorOpportunityId) {
        if (creditorOpportunityId == null) {
            return new List<Settlement_Plan_Item__c>();
        }
        return [
            SELECT Id,
                   Name,
                   Payment_Number__c,
                   Payment_Date__c,
                   Original_Payment_Date__c,
                   Payment_Amount__c,
                   Commission_Fee__c,
                   Bank_Fee__c,
                   EPPS_Transaction_Fee__c,
                   EPPS_Month_End_Fee__c,
                   Total_Fees__c,
                   Total_Payment__c,
                   Running_Balance__c,
                   Escrow_Balance__c,
                   Status__c,
                   Is_Escrow_Shortage__c,
                   Settlement_Segment__c,
                   Settlement_Segment__r.Name
            FROM Settlement_Plan_Item__c
            WHERE Creditors_List__c = :creditorOpportunityId
            ORDER BY Payment_Number__c ASC
        ];
    }

    /**
     * @description Get CreditorOpportunity details needed for calculation
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return CreditorOpportunity__c record with relevant fields
     */
    @AuraEnabled(cacheable=true)
    public static CreditorOpportunity__c getCreditorOpportunity(Id creditorOpportunityId) {
        List<CreditorOpportunity__c> credOpps = [
            SELECT Id,
                   Name,
                   Amount__c,
                   Settlement_Offer_Amount__c,
                   Settlement_Percentage__c,
                   Settlement_Status__c,
                   Escrow_Start_Balance__c,
                   Commission_Fee__c,
                   Bank_Fee__c,
                   First_Payment_Date__c,
                   Final_Payment_Date__c,
                   Settlement_Term_Weeks__c,
                   Number_of_Payments__c,
                   Total_Scheduled_Amount__c,
                   Total_Paid_Amount__c,
                   Remaining_Balance__c,
                   Total_Fees__c,
                   Has_Escrow_Shortage__c,
                   Escrow_Shortage_Count__c
            FROM CreditorOpportunity__c
            WHERE Id = :creditorOpportunityId
            LIMIT 1
        ];

        return credOpps.isEmpty() ? null : credOpps[0];
    }

    /**
     * @description Delete all settlement plan items for a CreditorOpportunity
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean deletePlanItems(Id creditorOpportunityId) {
        if (creditorOpportunityId == null) {
            throw new AuraHandledException('Creditor Opportunity ID is required.');
        }
        try {
            // Check delete permission before querying
            if (!Schema.sObjectType.Settlement_Plan_Item__c.isDeletable()) {
                throw new AuraHandledException('Insufficient permissions to delete Settlement Plan Items.');
            }

            List<Settlement_Plan_Item__c> items = [
                SELECT Id FROM Settlement_Plan_Item__c
                WHERE Creditors_List__c = :creditorOpportunityId
                WITH SECURITY_ENFORCED
            ];

            if (!items.isEmpty()) {
                delete items;
            }

            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting items: ' + e.getMessage());
        }
    }

    /**
     * @description Validate that segments can be calculated
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return ValidationResult with any warnings or errors
     */
    @AuraEnabled
    public static ValidationResult validateBeforeCalculation(Id creditorOpportunityId) {
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        result.warnings = new List<String>();
        result.errors = new List<String>();

        try {
            // Get CreditorOpportunity
            CreditorOpportunity__c credOpp = getCreditorOpportunity(creditorOpportunityId);

            if (credOpp == null) {
                result.isValid = false;
                result.errors.add('Creditor Opportunity not found.');
                return result;
            }

            // Check Settlement Offer Amount
            if (credOpp.Settlement_Offer_Amount__c == null || credOpp.Settlement_Offer_Amount__c <= 0) {
                result.isValid = false;
                result.errors.add('Settlement Offer Amount must be set and greater than zero.');
            }

            // Get segments
            List<Settlement_Segment__c> segments = getSegments(creditorOpportunityId);

            if (segments.isEmpty()) {
                result.isValid = false;
                result.errors.add('No segments found. Please create at least one segment.');
                return result;
            }

            // Check first segment has start date
            if (segments[0].Start_Date__c == null) {
                result.isValid = false;
                result.errors.add('First segment must have a Start Date.');
            }

            // Validate each segment
            for (Settlement_Segment__c seg : segments) {
                if (String.isBlank(seg.Segment_Type__c)) {
                    result.isValid = false;
                    result.errors.add('Segment "' + seg.Name + '" is missing Segment Type.');
                }

                if (seg.Segment_Type__c == 'Fixed' || seg.Segment_Type__c == 'Remainder') {
                    if (seg.Payment_Amount__c == null || seg.Payment_Amount__c <= 0) {
                        result.isValid = false;
                        result.errors.add('Segment "' + seg.Name + '" requires Payment Amount.');
                    }
                }

                if (seg.Segment_Type__c == 'Fixed' || seg.Segment_Type__c == 'SolveAmount') {
                    if (seg.Payment_Count__c == null || seg.Payment_Count__c <= 0) {
                        result.isValid = false;
                        result.errors.add('Segment "' + seg.Name + '" requires Payment Count.');
                    }
                }
            }

            // Check for existing items (warning only)
            List<Settlement_Plan_Item__c> existingItems = getExistingPlanItems(creditorOpportunityId);
            if (!existingItems.isEmpty()) {
                result.warnings.add('There are ' + existingItems.size() +
                    ' existing payment items. They will be replaced when you save.');
            }

            // Check escrow balance (warning only)
            if (credOpp.Escrow_Start_Balance__c == null || credOpp.Escrow_Start_Balance__c <= 0) {
                result.warnings.add('Escrow Start Balance is not set. Escrow tracking will show as shortage.');
            }

        } catch (Exception e) {
            result.isValid = false;
            result.errors.add('Validation error: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Wrapper class for validation results
     */
    public class ValidationResult {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }
    }
}