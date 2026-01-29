/**
 * @description LWC Controller for Settlement Plan Draft operations.
 *              Provides @AuraEnabled methods for Lightning components to manage
 *              draft payment plans, calculate previews, and activate drafts.
 *
 *              REFACTORED: January 2026 - Data Model Refactor
 *              - Updated to use new field references (CreditorOpportunity__c, Settlement_Plan__c)
 *              - Removed JSON-based methods, now uses real SObject records
 *
 * @author Settlement Calculator Team
 * @date January 2026
 *
 * ============================================================================
 * This controller wraps SettlementDraftService methods with proper error
 * handling and makes them accessible to LWC components.
 * ============================================================================
 */
public with sharing class SettlementDraftController {

    /**
     * @description Helper to throw AuraHandledException with accessible message
     */
    private static AuraHandledException createAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /**
     * @description Get all drafts for a CreditorOpportunity
     * @param creditorOpportunityId The parent CreditorOpp ID
     * @return List of drafts ordered by Status (Active first), then LastModifiedDate
     */
    @AuraEnabled
    public static List<Settlement_Plan_Draft__c> getDrafts(Id creditorOpportunityId) {
        try {
            return SettlementDraftService.getDrafts(creditorOpportunityId);
        } catch (Exception e) {
            throw createAuraException('Error loading drafts: ' + e.getMessage());
        }
    }

    /**
     * @description Get a single draft with related segment and item records
     * @param draftId The draft record ID
     * @return DraftWrapper containing draft record + related segments/items
     */
    @AuraEnabled
    public static SettlementDraftService.DraftWrapper getDraftWithDetails(Id draftId) {
        try {
            return SettlementDraftService.getDraftWithDetails(draftId);
        } catch (Exception e) {
            throw createAuraException('Error loading draft details: ' + e.getMessage());
        }
    }

    /**
     * @description Get the default draft for a CreditorOpportunity (Active or newest Draft)
     * @param creditorOpportunityId The parent CreditorOpp ID
     * @return The default draft or null if none exist
     */
    @AuraEnabled
    public static Settlement_Plan_Draft__c getDefaultDraft(Id creditorOpportunityId) {
        try {
            return SettlementDraftService.getDefaultDraft(creditorOpportunityId);
        } catch (Exception e) {
            throw createAuraException('Error loading default draft: ' + e.getMessage());
        }
    }

    /**
     * @description Get CreditorOpportunity details
     * @param creditorOpportunityId The CreditorOpp ID
     * @return CreditorOpportunity record with relevant fields
     */
    @AuraEnabled(cacheable=true)
    public static CreditorOpportunity__c getCreditorOpportunity(Id creditorOpportunityId) {
        try {
            if (creditorOpportunityId == null) {
                return null;
            }
            List<CreditorOpportunity__c> credOpps = [
                SELECT Id,
                       Name,
                       Settlement_Status__c,
                       Amount__c,
                       Escrow_Start_Balance__c,
                       Account_Bank_Information__c
                FROM CreditorOpportunity__c
                WHERE Id = :creditorOpportunityId
                LIMIT 1
            ];
            return credOpps.isEmpty() ? null : credOpps[0];
        } catch (Exception e) {
            throw createAuraException('Error loading Creditor Opportunity: ' + e.getMessage());
        }
    }

    /**
     * @description Save draft with segments and items
     * @param draftId The draft ID
     * @param segments List of segment records
     * @param items List of payment item records (optional)
     * @param draftFields Map of draft field values to update (optional)
     * @return Updated draft record
     */
    @AuraEnabled
    public static Settlement_Plan_Draft__c saveDraftWithRecords(
        Id draftId,
        List<Settlement_Segment__c> segments,
        List<SettlementDraftService.PaymentItemData> items,
        Map<String, Object> draftFields
    ) {
        try {
            if (draftId == null) {
                throw createAuraException('Draft ID is required.');
            }

            // Handle null parameters - platform may pass null for empty arrays/objects
            if (segments == null) {
                segments = new List<Settlement_Segment__c>();
            }
            if (items == null) {
                items = new List<SettlementDraftService.PaymentItemData>();
            }
            if (draftFields == null) {
                draftFields = new Map<String, Object>();
            }

            return SettlementDraftService.saveDraftWithRecords(draftId, segments, items, draftFields);
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw createAuraException('Error saving draft: ' + e.getMessage());
        }
    }

    /**
     * @description Creates a new draft AND saves segments/items in one atomic transaction.
     *              Used for lazy draft creation - draft only created when user clicks Save.
     *              This prevents orphan drafts when user previews but never saves.
     * @param creditorOpportunityId The parent CreditorOpportunity
     * @param draftName Name for the new draft
     * @param segments List of segments to save
     * @param items List of payment items to save
     * @param draftFields Map of draft field values
     * @return The created draft record
     */
    @AuraEnabled
    public static Settlement_Plan_Draft__c createAndSaveDraft(
        Id creditorOpportunityId,
        String draftName,
        List<Settlement_Segment__c> segments,
        List<SettlementDraftService.PaymentItemData> items,
        Map<String, Object> draftFields
    ) {
        try {
            // Handle null parameters - platform may pass null for empty arrays/objects
            if (segments == null) {
                segments = new List<Settlement_Segment__c>();
            }
            if (items == null) {
                items = new List<SettlementDraftService.PaymentItemData>();
            }
            if (draftFields == null) {
                draftFields = new Map<String, Object>();
            }

            return SettlementDraftService.createAndSaveDraft(
                creditorOpportunityId, draftName, segments, items, draftFields
            );
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (Exception e) {
            throw createAuraException('Error creating and saving draft: ' + e.getMessage());
        }
    }

    /**
     * @description Clone an existing draft
     * @param sourceDraftId The draft to clone
     * @param newName Name for the cloned draft
     * @return The new cloned draft record
     */
    @AuraEnabled
    public static Settlement_Plan_Draft__c cloneDraft(Id sourceDraftId, String newName) {
        try {
            return SettlementDraftService.cloneDraft(sourceDraftId, newName);
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (Exception e) {
            throw createAuraException('Error cloning draft: ' + e.getMessage());
        }
    }

    /**
     * @description Delete a draft (only if status = Draft or Archived)
     * @param draftId The draft to delete
     */
    @AuraEnabled
    public static void deleteDraft(Id draftId) {
        try {
            SettlementDraftService.deleteDraft(draftId);
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (Exception e) {
            throw createAuraException('Error deleting draft: ' + e.getMessage());
        }
    }

    /**
     * @description Calculate payment items from segments (preview only)
     * @param draftId The draft ID (optional if segments provided)
     * @param segments List of segments
     * @param balance The balance amount
     * @param settlementOffer The settlement offer amount
     * @param totalPaidAmount Total paid amount from UI (Cleared + Processing)
     * @return DraftCalculationResult with calculated items
     */
    @AuraEnabled
    public static SettlementDraftService.DraftCalculationResult calculateDraftPlan(
        Id draftId,
        List<Settlement_Segment__c> segments,
        Decimal balance,
        Decimal settlementOffer,
        Decimal totalPaidAmount
    ) {
        // Handle null parameter - platform may pass null for empty array
        if (segments == null) {
            segments = new List<Settlement_Segment__c>();
        }

        return SettlementDraftService.calculateDraftPlan(
            draftId, segments, balance, settlementOffer, totalPaidAmount
        );
    }

    /**
     * @description Refresh items after manual edit (running balance logic retired)
     * @param items List of payment items
     * @param settlementOffer The target settlement offer amount
     * @return RecalculationResult with updated items + summary
     */
    @AuraEnabled
    public static SettlementDraftService.RecalculationResult recalculateBalances(
        List<SettlementDraftService.PaymentItemData> items,
        Decimal settlementOffer
    ) {
        if (items == null || items.isEmpty()) {
            SettlementDraftService.RecalculationResult result = new SettlementDraftService.RecalculationResult();
            result.success = false;
            result.errorMessage = 'No payment items provided.';
            return result;
        }

        return SettlementDraftService.recalculateBalances(
            items, settlementOffer
        );
    }

    /**
     * @description Activate a draft - sets status to Active
     * @param draftId The draft to activate
     * @return ActivationResult with success/error and record counts
     */
    @AuraEnabled
    public static SettlementDraftService.ActivationResult activateDraft(Id draftId) {
        try {
            return SettlementDraftService.activateDraft(draftId);
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (Exception e) {
            throw createAuraException('Error activating draft: ' + e.getMessage());
        }
    }

    /**
     * @description Suspend Scheduled items and void Processing items for an active draft
     * @param draftId The draft to suspend
     * @return Number of items updated
     */
    @AuraEnabled
    public static Integer suspendPaymentItems(Id draftId) {
        try {
            return SettlementDraftService.suspendPaymentItems(draftId);
        } catch (SettlementCalculatorException e) {
            throw createAuraException(e.getMessage());
        } catch (Exception e) {
            throw createAuraException('Error suspending payments: ' + e.getMessage());
        }
    }

    /**
     * @description Get fee configuration values for Add Row
     *              Returns commission fee, bank fee and EPPS transaction fee from config.
     *              Used by LWC to populate fees when adding manual rows.
     * @return Map with commissionFee, bankFee and eppsTransactionFee values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Decimal> getFeeConfig() {
        try {
            Settlement_Calc_Config__mdt config = SettlementDraftService.getConfig();
            return new Map<String, Decimal>{
                'commissionFee' => config.Default_Commission_Fee__c,
                'bankFee' => config.Default_Bank_Fee__c,
                'eppsTransactionFee' => config.EPPS_Transaction_Fee__c,
                'fullyFundedTolerance' => config.Fully_Funded_Tolerance__c
            };
        } catch (Exception e) {
            throw createAuraException('Error loading fee config: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper result for modal initialization
     */
    public class ModalInitResult {
        @AuraEnabled public CreditorOpportunity__c creditorOpportunity;
        @AuraEnabled public List<Settlement_Plan_Draft__c> drafts;
        @AuraEnabled public Settlement_Plan_Draft__c defaultDraft;
        @AuraEnabled public SettlementDraftService.DraftWrapper defaultDraftDetails;
        @AuraEnabled public Boolean hasExistingPlan;
    }

    /**
     * @description Initialize the modal with all needed data in a single call
     * @param creditorOpportunityId The CreditorOpp ID
     * @return ModalInitResult with all initialization data
     */
    @AuraEnabled
    public static ModalInitResult initializeModal(Id creditorOpportunityId) {
        ModalInitResult result = new ModalInitResult();

        try {
            // Get CreditorOpportunity
            result.creditorOpportunity = getCreditorOpportunity(creditorOpportunityId);

            // Get all drafts
            result.drafts = SettlementDraftService.getDrafts(creditorOpportunityId);

            // Get default draft
            result.defaultDraft = SettlementDraftService.getDefaultDraft(creditorOpportunityId);

            // Get default draft details if one exists
            if (result.defaultDraft != null) {
                result.defaultDraftDetails = SettlementDraftService.getDraftWithDetails(result.defaultDraft.Id);
            }

            // Check if there's an existing Active plan with items using subquery (single SOQL)
            result.hasExistingPlan = false;
            if (creditorOpportunityId != null) {
                List<Settlement_Plan_Draft__c> activePlans = [
                    SELECT Id, (SELECT Id FROM Settlement_Plan_Items__r LIMIT 1)
                    FROM Settlement_Plan_Draft__c
                    WHERE CreditorOpportunity__c = :creditorOpportunityId
                    AND Status__c = :SettlementDraftService.STATUS_ACTIVE
                    LIMIT 1
                ];

                result.hasExistingPlan = !activePlans.isEmpty() && 
                    !activePlans[0].Settlement_Plan_Items__r.isEmpty();
            }

        } catch (Exception e) {
            throw createAuraException('Error initializing modal: ' + e.getMessage());
        }

        return result;
    }
}