/**
 * @description Standalone LWC for Settlement Plan Builder.
 *              Designed to be placed on a Lightning Record Page tab.
 *              Manages draft payment plans for CreditorOpportunity records.
 * @author Settlement Calculator Team
 * @date January 2026
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import LightningConfirm from 'lightning/confirm';

// Schema imports for dynamic picklist
import SETTLEMENT_PLAN_ITEM_OBJECT from '@salesforce/schema/Settlement_Plan_Item__c';
import STATUS_FIELD from '@salesforce/schema/Settlement_Plan_Item__c.Status__c';

// Apex methods
import initializeModal from '@salesforce/apex/SettlementDraftController.initializeModal';
import getDraftWithDetails from '@salesforce/apex/SettlementDraftController.getDraftWithDetails';
import createAndSaveDraft from '@salesforce/apex/SettlementDraftController.createAndSaveDraft';
import saveDraftWithRecords from '@salesforce/apex/SettlementDraftController.saveDraftWithRecords';
import cloneDraft from '@salesforce/apex/SettlementDraftController.cloneDraft';
import deleteDraft from '@salesforce/apex/SettlementDraftController.deleteDraft';
import calculateDraftPlan from '@salesforce/apex/SettlementDraftController.calculateDraftPlan';
import recalculateBalances from '@salesforce/apex/SettlementDraftController.recalculateBalances';
import activateDraft from '@salesforce/apex/SettlementDraftController.activateDraft';
import suspendPaymentItems from '@salesforce/apex/SettlementDraftController.suspendPaymentItems';
import addSuspendedImmediateProcessingPayment from '@salesforce/apex/SettlementDraftController.addSuspendedImmediateProcessingPayment';
import getFeeConfig from '@salesforce/apex/SettlementDraftController.getFeeConfig';
import validatePaymentDates from '@salesforce/apex/SettlementDraftController.validatePaymentDates';

// Modal
import AddSuspendedPaymentModal from 'c/addSuspendedPaymentModal';

// CreditorOpportunity fields for @wire
const FIELDS = ['CreditorOpportunity__c.Name'];

// Field mapping: SObject field names → camelCase JS property names
// Used by normalizeSegments, normalizePaymentItems, updateLocalItemsFromRecalc
const SEGMENT_FIELD_MAP = {
    'Id': 'id',
    'Segment_Order__c': 'segmentOrder',
    'Segment_Type__c': 'segmentType',
    'Payment_Amount__c': 'paymentAmount',
    'Payment_Count__c': 'paymentCount',
    'Frequency__c': 'frequency',
    'Start_Date__c': 'startDate',
    'End_Date__c': 'endDate'
};

const ITEM_FIELD_MAP = {
    'Id': 'id',
    'Payment_Number__c': 'paymentNumber',
    'Payment_Date__c': 'paymentDate',
    'Original_Payment_Date__c': 'originalPaymentDate',
    'Status__c': 'status',
    'Payment_Method__c': 'paymentMethod',
    'Has_Override__c': 'isManuallyModified',
    'Settlement_Segment__c': 'segmentId'
};

export default class SettlementPlanBuilder extends LightningElement {
    // Public API - receives recordId from Lightning Record Page
    @api recordId;

    // Wire adapter to get record name (triggers re-render on record change)
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    creditorOppRecord;

    // Wire adapters for dynamic picklist values
    @wire(getObjectInfo, { objectApiName: SETTLEMENT_PLAN_ITEM_OBJECT })
    settlementPlanItemInfo;

    @track statusOptions = [];
    statusValueByLabelLower = {};
    scheduledStatusValue = null;
    clearedStatusValue = null;
    processingStatusValue = null;

    @wire(getPicklistValues, {
        recordTypeId: '$settlementPlanItemInfo.data.defaultRecordTypeId',
        fieldApiName: STATUS_FIELD
    })
    wiredStatusPicklist({ error, data }) {
        if (data) {
            this.statusOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            const map = {};
            data.values.forEach(item => {
                if (item.label) {
                    map[item.label.toLowerCase()] = item.value;
                }
                if (item.value) {
                    map[item.value.toLowerCase()] = item.value;
                }
            });
            this.statusValueByLabelLower = map;
            this.scheduledStatusValue = this.resolveStatusValue('Scheduled', null);
            this.clearedStatusValue = this.resolveStatusValue('Cleared', 'Paid');
            this.processingStatusValue = this.resolveStatusValue('Processing', null);

            // Re-compute status flags now that picklist values are resolved
            if (this.paymentItems && this.paymentItems.length > 0) {
                this.paymentItems = this.paymentItems.map(item => {
                    if (!item.id || !item.dbStatus) return item;
                    const isScheduled = this.isScheduledStatus(item.dbStatus);
                    const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();
                    const isProcessing = (item.dbStatus || '').toLowerCase() === processingValue;
                    const hasDbId = !!item.id;
                    return {
                        ...item,
                        isLocked: !isScheduled,
                        // Phase 41: Simplified action flags
                        isScheduledWithDbId: isScheduled && hasDbId,
                        isProcessingWithDbId: isProcessing && hasDbId,
                        isUnsavedRow: !hasDbId
                    };
                });
            }
        } else if (error) {
            console.error('Error loading status picklist:', error);
            // Fallback to empty array - user will see empty dropdown
            this.statusOptions = [];
            this.statusValueByLabelLower = {};
            this.scheduledStatusValue = null;
            this.clearedStatusValue = null;
            this.processingStatusValue = null;
        }
    }

    // State management - individual tracked properties for better reactivity performance
    // Data properties
    @track creditorOpportunity = null;
    @track drafts = [];
    @track currentDraftId = null;
    @track currentDraft = null;
    @track segments = [];
    @track paymentItems = [];

    // UI state properties
    @track isLoading = false;
    @track isDirty = false;
    @track error = null;
    @track editingRowId = null;
    // Snapshot of row being edited (for cancel/revert)
    editingRowSnapshot = null;
    isInitialized = false; // No @track needed - only used internally, not in template

    // Lazy draft creation state
    @track isNewUnsavedDraft = false;  // True when "New Draft" clicked but not yet saved to DB
    @track hasCalculated = false;      // True after Calculate clicked (enables Save for new drafts)

    // Accordion state - controls which sections are expanded
    @track activeSections = [];  // ['settlement-details', 'payment-segments'] when expanded

    // Fee config - loaded on init for Add Row and Calculate preview (no dependency on previous rows)
    @track feeConfig = { commissionFee: 0, eppsTransactionFee: 0, fullyFundedTolerance: 0.01 };

    // Fee records from Settlement_Fee__c - source of truth for fee data (Phase 44)
    // Map: itemId → { paymentAmount, commissionFee, eppsTransactionFee }
    feesByItemId = new Map();

    // Frequency options for segments
    get frequencyOptions() {
        return [
            { label: 'Weekly', value: 'Weekly' },
            { label: 'Bi-Weekly', value: 'Bi-Weekly' },
            { label: 'Semi-Monthly', value: 'Semi-Monthly' },
            { label: 'Monthly', value: 'Monthly' }
        ];
    }

    // Segment type options
    get segmentTypeOptions() {
        return [
            { label: 'Fixed', value: 'Fixed' },
            { label: 'Remainder', value: 'Remainder' },
            { label: 'SolveAmount', value: 'SolveAmount' }
        ];
    }

    resolveStatusValue(label, fallbackLabel) {
        const map = this.statusValueByLabelLower || {};
        if (label) {
            const key = label.toLowerCase();
            if (map[key]) return map[key];
        }
        if (fallbackLabel) {
            const key = fallbackLabel.toLowerCase();
            if (map[key]) return map[key];
        }
        return label || fallbackLabel;
    }

    isScheduledStatus(status) {
        const scheduled = this.scheduledStatusValue || 'Scheduled';
        return (status || '').toLowerCase() === scheduled.toLowerCase();
    }

    isPaidStatus(status) {
        const cleared = this.clearedStatusValue || 'Cleared';
        const processing = this.processingStatusValue || 'Processing';
        const value = (status || '').toLowerCase();
        return value === cleared.toLowerCase() || value === processing.toLowerCase();
    }

    // Computed properties
    get isReadOnly() {
        const status = this.currentDraft?.Status__c;
        return status === 'Active' || status === 'Suspended' || status === 'Archived';
    }

    get isEditable() {
        return !this.isReadOnly;
    }

    get hasDrafts() {
        return this.drafts && this.drafts.length > 0;
    }

    get hasPaymentItems() {
        return this.paymentItems && this.paymentItems.length > 0;
    }

    get shouldEnablePaymentTableVerticalScroll() {
        return (this.paymentItems?.length || 0) > 4;
    }

    get paymentTableContainerClass() {
        const base = 'payment-table-container slds-scrollable_x';
        const verticalScrollClass = this.shouldEnablePaymentTableVerticalScroll
            ? 'payment-table-container--scroll-y'
            : 'payment-table-container--no-scroll-y';
        return `${base} ${verticalScrollClass}`;
    }

    get hasSegments() {
        return this.segments && this.segments.length > 0;
    }

    get isSummaryFromDb() {
        return !!this.currentDraft?.Id && !this.isNewUnsavedDraft && !this.isDirty;
    }

    get isSummaryPreview() {
        return !this.isSummaryFromDb;
    }

    /**
     * Get effective settlement amount (revised if set, otherwise original)
     */
    get effectiveSettlementAmount() {
        return this.currentDraft?.Revised_Settlement_Amount__c ||
               this.currentDraft?.Settlement_Offer_Amount__c || 0;
    }

    get fundingDifferenceValue() {
        const totalPaid = this.summaryTotalPaidAmount;
        const totalScheduled = this.summaryTotalScheduledAmount;
        const effectiveOffer = this.effectiveSettlementAmount;

        const processingTotal = this.summaryTotalProcessingAmount;

        // Paid + Processing + Scheduled should cover the offer
        return (totalPaid + processingTotal + totalScheduled) - effectiveOffer;
    }

    get isBalanced() {
        return Math.abs(this.fundingDifferenceValue) <= this.feeConfig.fullyFundedTolerance;
    }

    get balanceStatusText() {
        if (this.isBalanced) return 'Balanced';
        if (this.fundingDifferenceValue < 0) return 'Underfunded';
        return 'Overfunded';
    }

    /**
     * Summary box class - changes border color based on funding status
     */
    get summaryBoxClass() {
        let baseClass = 'slds-box slds-theme_default summary-box';
        if (this.isBalanced) {
            return baseClass + ' summary-box-balanced';
        } else if (this.fundingDifferenceValue < 0) {
            return baseClass + ' summary-box-underfunded';
        }
        return baseClass + ' summary-box-overfunded';
    }

    /**
     * Funding status indicator class
     */
    get fundingStatusClass() {
        let baseClass = 'funding-status-indicator';
        if (this.isBalanced) {
            return baseClass + ' funding-balanced';
        } else if (this.fundingDifferenceValue < 0) {
            return baseClass + ' funding-underfunded';
        }
        return baseClass + ' funding-overfunded';
    }

    /**
     * Funding status icon
     */
    get fundingStatusIcon() {
        if (this.isBalanced) return 'utility:success';
        if (this.fundingDifferenceValue < 0) return 'utility:warning';
        return 'utility:info';
    }

    /**
     * Funding status message with amount
     */
    get fundingStatusMessage() {
        const diff = Math.abs(this.fundingDifferenceValue);
        const formattedDiff = this.formatCurrency(diff);
        if (this.isBalanced) {
            return 'Plan is balanced - Total scheduled matches settlement offer';
        } else if (this.fundingDifferenceValue < 0) {
            return `Underfunded by ${formattedDiff} - Schedule more payments or reduce settlement offer`;
        }
        return `Overfunded by ${formattedDiff} - Scheduled payments exceed settlement offer`;
    }

    /**
     * Current balance text class - red if negative
     */
    get currentBalanceClass() {
        const balance = this.summaryCurrentBalance;
        if (balance < 0) {
            return 'slds-text-heading_medium summary-value-error';
        } else if (balance === 0) {
            return 'slds-text-heading_medium summary-value-success';
        }
        return 'slds-text-heading_medium';
    }

    get formattedTotalPaidAmount() {
        return this.formatCurrency(this.summaryTotalPaidAmount);
    }

    get formattedTotalScheduledAmount() {
        return this.formatCurrency(this.summaryTotalScheduledAmount);
    }

    get formattedCurrentBalance() {
        return this.formatCurrency(this.summaryCurrentBalance);
    }

    get formattedOriginalOfferAmount() {
        return this.formatCurrency(this.currentDraft?.Settlement_Offer_Amount__c || 0);
    }

    get formattedEffectiveOfferAmount() {
        return this.formatCurrency(this.effectiveSettlementAmount || 0);
    }

    get shouldShowOfferAmount() {
        return this.currentDraft?.Revised_Settlement_Amount__c != null;
    }

    get formattedNumberOfPayments() {
        return this.summaryNumberOfPayments;
    }

    get createdByName() {
        return this.currentDraft?.CreatedBy?.Name || '';
    }

    get previewTotals() {
        const totals = {
            totalPaid: 0,
            totalScheduled: 0,
            totalProcessing: 0,
            numberOfPayments: 0
        };

        const items = this.paymentItems || [];
        totals.numberOfPayments = items.length;

        if (items.length === 0) {
            return totals;
        }

        const clearedValue = (this.clearedStatusValue || 'Cleared').toLowerCase();
        const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();

        for (const item of items) {
            const amount = parseFloat(item.paymentAmount) || 0;
            const statusValue = (item.status || '').toLowerCase();

            if (statusValue === processingValue) {
                totals.totalProcessing += amount;
                continue;
            }

            if (statusValue === clearedValue) {
                totals.totalPaid += amount;
                continue;
            }

            if (this.isScheduledStatus(item.status)) {
                totals.totalScheduled += amount;
            }
        }

        return totals;
    }

    get summaryTotalPaidAmount() {
        if (this.isSummaryFromDb) {
            return this.currentDraft?.Total_Paid_Amount__c || 0;
        }
        return this.previewTotals.totalPaid;
    }

    get summaryTotalScheduledAmount() {
        if (this.isSummaryFromDb) {
            return this.currentDraft?.Total_Scheduled_Amount__c || 0;
        }
        return this.previewTotals.totalScheduled;
    }

    get summaryTotalProcessingAmount() {
        if (this.isSummaryFromDb) {
            return this.processingTotalFromItems;
        }
        return this.previewTotals.totalProcessing;
    }

    get summaryNumberOfPayments() {
        if (this.isSummaryFromDb) {
            return this.currentDraft?.Number_of_Payments__c || 0;
        }
        return this.previewTotals.numberOfPayments;
    }

    get summaryCurrentBalance() {
        if (this.isSummaryFromDb) {
            return this.currentDraft?.Current_Balance__c || 0;
        }
        return (this.effectiveSettlementAmount || 0) - this.summaryTotalPaidAmount;
    }

    get processingTotalFromItems() {
        const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();
        return (this.paymentItems || [])
            .filter(item => (item.status || '').toLowerCase() === processingValue)
            .reduce((sum, item) => sum + (parseFloat(item.paymentAmount) || 0), 0);
    }

    get canSave() {
        // Basic conditions
        if (this.isReadOnly || !this.currentDraft || this.isLoading) {
            return false;
        }
        // For new unsaved drafts, require Calculate first (ensures user previews before saving)
        if (this.isNewUnsavedDraft && !this.hasCalculated) {
            return false;
        }
        return true;
    }

    get saveButtonTooltip() {
        if (this.isNewUnsavedDraft && !this.hasCalculated) {
            return 'Click Calculate to preview before saving';
        }
        if (this.isLoading) {
            return 'Please wait...';
        }
        return 'Save draft';
    }

    get canActivate() {
        // Cannot activate unsaved drafts (must save first, consistent with Clone/Delete)
        if (this.isNewUnsavedDraft) {
            return false;
        }
        return !this.isReadOnly &&
               this.hasPaymentItems &&
               this.currentDraft?.Status__c === 'Draft';
    }

    get canClone() {
        // Cannot clone unsaved drafts (no DB record exists yet)
        if (this.isNewUnsavedDraft) {
            return false;
        }
        // Only allow clone when draft exists and has been saved (no unsaved local changes)
        return this.currentDraft && !this.isDirty;
    }

    get canDelete() {
        // Cannot delete unsaved drafts (no DB record exists yet)
        if (this.isNewUnsavedDraft) {
            return false;
        }
        return this.currentDraft?.Status__c === 'Draft' ||
               this.currentDraft?.Status__c === 'Archived';
    }

    get canSuspend() {
        // Only Active plans can be suspended
        return this.currentDraft?.Status__c === 'Active' && this.hasPaymentItems;
    }

    get canAddPayment() {
        // Only Suspended plans can accept a one-off Immediate Processing payment
        return this.currentDraft?.Status__c === 'Suspended' && this.hasPaymentItems;
    }

    // Negated getters for template use
    get hasNoCurrentDraft() {
        return this.currentDraft === null || this.currentDraft === undefined;
    }

    get cannotClone() {
        return !this.canClone;
    }

    get cannotDelete() {
        return !this.canDelete;
    }

    get cannotActivate() {
        return !this.canActivate;
    }

    get cannotSave() {
        return !this.canSave;
    }

    get draftTabs() {
        const tabs = this.drafts.map(draft => {
            const isActive = draft.Status__c === 'Active';
            const isSuspended = draft.Status__c === 'Suspended';
            const isSelected = draft.Id === this.currentDraftId;

            // Build tab class - add green highlight for active plans
            let tabClass = 'slds-tabs_default__item';
            if (isSelected) {
                tabClass += ' slds-is-active';
            }
            if (isActive) {
                tabClass += ' active-plan-tab';
            }

            return {
                id: draft.Id,
                label: draft.Name,
                isActive: isActive,
                isSuspended: isSuspended,
                isArchived: draft.Status__c === 'Archived',
                statusIcon: isActive ? 'utility:check' : null,
                isSelected: isSelected,
                tabClass: tabClass,
                isUnsaved: false
            };
        });

        // Add tab for unsaved new draft (not yet in database)
        if (this.isNewUnsavedDraft && this.currentDraft) {
            tabs.push({
                id: 'new-unsaved',
                label: this.currentDraft.Name || 'New Draft',
                isActive: false,
                isArchived: false,
                statusIcon: null,
                isSelected: true,
                tabClass: 'slds-tabs_default__item slds-is-active',
                isUnsaved: true
            });
        }

        return tabs;
    }

    get statusBadgeClass() {
        const status = this.currentDraft?.Status__c;
        switch (status) {
            case 'Active': return 'slds-badge slds-badge_success';
            case 'Suspended': return 'slds-badge slds-badge_warning';
            case 'Archived': return 'slds-badge';
            default: return 'slds-badge slds-badge_lightest';
        }
    }

    // Problem statuses that show red highlighting
    get problemStatuses() {
        return ['Suspended', 'Cancelled', 'Missed', 'Skipped'];
    }

    get formattedPaymentItems() {
        if (!this.paymentItems) return [];

        let runningBalance = this.effectiveSettlementAmount || 0;
        const editingRowId = this.editingRowId;
        const editingSnapshot = this.editingRowSnapshot;

        const shouldPreferOpenUpForLastDropdown = !this.shouldEnablePaymentTableVerticalScroll;
        let lastDropdownIndex = -1;
        if (shouldPreferOpenUpForLastDropdown) {
            // When not using a scroll container (<= 4 rows), the menu can open downward and get clipped by the viewport.
            // Prefer an upward-opening alignment for the last row that actually renders the dropdown.
            this.paymentItems.forEach((candidate, index) => {
                const candidateStatus = candidate.dbStatus || candidate.status || 'Scheduled';
                const candidateHasDbId = !!candidate.id;
                const candidateIsScheduled = this.isScheduledStatus(candidateStatus);
                if (candidateIsScheduled && candidateHasDbId) {
                    lastDropdownIndex = index;
                }
            });
        }

        return this.paymentItems.map((item, index) => {
            const status = item.status || 'Scheduled';
            // isLocked reflects DB state only - set in normalizePaymentItems when loading from DB
            // Row should only lock after save, not when user changes status in dropdown
            const isLocked = item.isLocked === true;
            const isProblemStatus = this.problemStatuses.includes(status);

            const isEditingRow = editingRowId === item.sequenceNumber;
            let balanceItem = item;
            if (isEditingRow) {
                balanceItem = editingSnapshot || null;
            }

            if (balanceItem) {
                const balanceStatus = balanceItem.status || 'Scheduled';
                const shouldReduceBalance =
                    this.isScheduledStatus(balanceStatus) || this.isPaidStatus(balanceStatus);
                if (shouldReduceBalance) {
                    const balanceAmount = parseFloat(balanceItem.paymentAmount) || 0;
                    runningBalance -= balanceAmount;
                }
            }

            const formattedRunningBalance = isEditingRow
                ? '--'
                : this.formatCurrency(runningBalance);

            // Build row class - priority: locked > problem > modified
            let rowClass = 'slds-hint-parent';
            if (isLocked) {
                rowClass += ' locked-row';
            } else if (isProblemStatus) {
                rowClass += ' problem-row';
            } else if (item.isManuallyModified) {
                rowClass += ' modified-row';
            }

            // Compute action flags fresh each render (fixes race condition with picklist loading)
            const hasDbId = !!item.id;
            const isScheduled = this.isScheduledStatus(item.dbStatus || status);
            const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();
            const isProcessing = ((item.dbStatus || status) || '').toLowerCase() === processingValue;

            const actionsMenuAlignment =
                shouldPreferOpenUpForLastDropdown && index === lastDropdownIndex
                    ? 'bottom-right'
                    : 'auto';

            return {
                ...item,
                formattedDate: this.formatDate(item.paymentDate),
                formattedAmount: this.formatCurrency(item.paymentAmount),
                formattedCommissionFee: this.formatCurrency(item.commissionFee),
                formattedEppsFee: this.formatCurrency(item.eppsTransactionFee),
                formattedTotalFees: this.formatCurrency(item.totalFees),
                formattedRunningBalance: formattedRunningBalance,
                status: status,
                paymentMethod: item.paymentMethod || '',
                rowClass: rowClass,
                statusBadgeClass: this.getPaymentStatusBadgeClass(status),
                isEditing: this.editingRowId === item.sequenceNumber,
                isLocked: isLocked,
                canEdit: !isLocked,
                canDelete: !isLocked,
                editButtonTitle: isLocked ? 'Historical payments cannot be edited' : 'Edit row',
                deleteButtonTitle: isLocked ? 'Historical payments cannot be deleted' : 'Delete row',
                showModifiedIcon: item.isManuallyModified && !isLocked,
                // Action flags computed fresh (not from pre-stored values)
                isScheduledWithDbId: isScheduled && hasDbId,
                isProcessingWithDbId: isProcessing && hasDbId,
                isUnsavedRow: !hasDbId,
                actionsMenuAlignment: actionsMenuAlignment
            };
        });
    }

    /**
     * Get badge class for payment item status
     */
    getPaymentStatusBadgeClass(status) {
        const baseClass = 'slds-badge payment-status-badge';
        const statusValue = (status || '').toLowerCase();
        const cleared = (this.clearedStatusValue || 'Cleared').toLowerCase();
        const processing = (this.processingStatusValue || 'Processing').toLowerCase();

        if (statusValue === cleared) return `${baseClass} payment-status-cleared`;
        if (statusValue === processing) return `${baseClass} payment-status-processing`;

        switch (statusValue) {
            case 'missed': return `${baseClass} payment-status-missed`;
            case 'cancelled': return `${baseClass} payment-status-warning`;
            case 'canceled': return `${baseClass} payment-status-warning`;
            case 'skipped': return `${baseClass} payment-status-warning`;
            case 'suspended': return `${baseClass} payment-status-warning`;
            default: return `${baseClass} payment-status-neutral`; // Scheduled/Void/Immediate Processing/Other
        }
    }

    get creditorName() {
        return this.creditorOpportunity?.Name || 'Creditor';
    }

    // Lifecycle
    connectedCallback() {
        if (this.recordId && !this.isInitialized) {
            this.loadInitialData();
            this.loadFeeConfig(); // Load fee config for Add Row (runs in parallel, cacheable)
        }
    }

    renderedCallback() {
        // Set native select values after render (needed because <option selected> binding is tricky in LWC)
        if (this.editingRowId) {
            const selectElements = this.template.querySelectorAll('select[data-field="status"]');
            selectElements.forEach(select => {
                const rowId = select.dataset.row;
                const item = this.paymentItems.find(i => i.sequenceNumber === rowId);
                if (item && select.value !== item.status) {
                    select.value = item.status;
                }
            });
        }
    }

    // Data loading methods
    async loadInitialData() {
        if (!this.recordId) return;
        
        this.isInitialized = true;
        this.isLoading = true;
        this.error = null;

        try {
            const result = await initializeModal({
                creditorOpportunityId: this.recordId
            });

            this.creditorOpportunity = result.creditorOpportunity;
            this.drafts = result.drafts || [];

            // Set default accordion state based on whether drafts exist
            if (this.drafts.length === 0) {
                // First draft - expand sections to guide user
                this.activeSections = ['settlement-details', 'payment-segments'];
            } else {
                // Existing drafts - collapse sections
                this.activeSections = [];
            }

            if (result.defaultDraftDetails) {
                this.loadDraftDetails(result.defaultDraftDetails);
            } else if (this.drafts.length > 0) {
                await this.selectDraft(this.drafts[0].Id);
            }

        } catch (error) {
            this.error = error;
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    loadDraftDetails(wrapper) {
        this.currentDraftId = wrapper.draft?.Id;
        this.currentDraft = wrapper.draft;
        this.segments = this.normalizeSegments(wrapper.segments || []);

        // Build fee map from Settlement_Fee__c records (Phase 44)
        this.buildFeeMap(wrapper.feeRecords || []);

        this.paymentItems = this.normalizePaymentItems(wrapper.paymentItems || []);
        this.isDirty = false;
        this.editingRowId = null;
        this.editingRowSnapshot = null;

        // Reset lazy draft creation state when loading an existing draft
        this.isNewUnsavedDraft = false;
        this.hasCalculated = false;
    }

    /**
     * Build fee map from Settlement_Fee__c records
     * Maps itemId → { paymentAmount, commissionFee, eppsTransactionFee }
     * @param {Array} feeRecords - Array of Settlement_Fee__c records from Apex
     */
    buildFeeMap(feeRecords) {
        this.feesByItemId = new Map();

        if (!feeRecords || feeRecords.length === 0) {
            return;
        }

        for (const fee of feeRecords) {
            const itemId = fee.Settlement_Plan_Item__c;
            if (!itemId) continue;

            if (!this.feesByItemId.has(itemId)) {
                this.feesByItemId.set(itemId, {
                    paymentAmount: 0,
                    commissionFee: 0,
                    eppsTransactionFee: 0
                });
            }

            const fees = this.feesByItemId.get(itemId);
            const amount = fee.Amount__c || 0;

            switch (fee.Type__c) {
                case 'SettlementPayment':
                    fees.paymentAmount = amount;
                    break;
                case 'Commission Fee':
                    fees.commissionFee = amount;
                    break;
                case 'Settlement Fee':
                    fees.eppsTransactionFee = amount;
                    break;
                default:
                    // Unknown fee type - ignore
                    break;
            }
        }
    }

    /**
     * Load fee config values for Add Row and Calculate preview
     * Called on init - all fees now come from config (no user input)
     */
    async loadFeeConfig() {
        try {
            const config = await getFeeConfig();
            this.feeConfig = {
                commissionFee: config.commissionFee || 0,
                eppsTransactionFee: config.eppsTransactionFee || 0,
                fullyFundedTolerance: config.fullyFundedTolerance || 0.01
            };
        } catch (error) {
            console.error('Error loading fee config:', error);
            // Keep defaults of 0 - fees will be recalculated on save anyway
        }
    }

    async selectDraft(draftId) {
        if (this.isDirty) {
            const confirmSwitch = await this.confirmAction(
                'You have unsaved changes. Switch drafts anyway?'
            );
            if (!confirmSwitch) return;
        }

        this.isLoading = true;
        try {
            const wrapper = await getDraftWithDetails({ draftId });
            this.loadDraftDetails(wrapper);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Draft management
    handleDraftTabClick(event) {
        const draftId = event.currentTarget.dataset.id;
        // Ignore clicks on unsaved draft tab (no DB record to fetch)
        if (draftId === 'new-unsaved') {
            return;
        }
        if (draftId !== this.currentDraftId) {
            this.selectDraft(draftId);
        }
    }

    // Handler for accordion section toggle
    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    async handleNewDraftClick() {
        if (this.isDirty) {
            const confirmSwitch = await this.confirmAction(
                'You have unsaved changes. Create new draft anyway?'
            );
            if (!confirmSwitch) return;
        }

        // LAZY DRAFT CREATION: Don't create in DB yet - just set up local state
        // Draft will be created when user clicks Save after Calculate
        const today = new Date();
        const dateStr = this.formatLocalDateYYYYMMDD(today);
        const draftName = `Draft ${dateStr}`;

        // Set lazy draft creation state
        this.isNewUnsavedDraft = true;
        this.currentDraftId = null;
        this.hasCalculated = false;

        // Create local draft object with defaults from CreditorOpportunity
        // Commission_Fee__c removed - fees now come from config and stored in Settlement_Fee__c
        this.currentDraft = {
            Name: draftName,
            Status__c: 'Draft',
            Balance__c: this.creditorOpportunity?.Amount__c,
            Escrow_Start_Balance__c: this.creditorOpportunity?.Escrow_Start_Balance__c,
            Settlement_Offer_Amount__c: null,
            Revised_Settlement_Amount__c: null,
            Is_Manually_Modified__c: false
        };

        // Initialize with one default segment
        const defaultSegment = {
            key: `seg-${Date.now()}`,
            segmentOrder: 1,
            segmentType: 'Fixed',
            paymentAmount: null,
            paymentCount: null,
            frequency: 'Monthly',
            startDate: dateStr
        };
        this.segments = [defaultSegment];
        this.paymentItems = [];
        this.isDirty = true;

        // Expand accordion sections for new draft configuration
        this.activeSections = ['settlement-details', 'payment-segments'];

        this.showToast('Info', 'New draft created. Configure segments and click Calculate to preview, then Save.', 'info');
    }

    // Event handlers - Input changes
    handleInputChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;

        const numVal = parseFloat(value);
        value = isNaN(numVal) ? null : numVal;

        this.currentDraft = {
            ...this.currentDraft,
            [field]: value
        };
        this.isDirty = true;
    }

    handleNameChange(event) {
        this.currentDraft = {
            ...this.currentDraft,
            Name: event.target.value
        };
        this.isDirty = true;
    }

    // Event handlers - Segments
    handleSegmentChange(event) {
        this.segments = event.detail.segments;
        this.isDirty = true;
    }

    handleSegmentError(event) {
        this.showToast('Warning', event.detail.message, 'warning');
    }

    // Event handlers - Calculate
    async handleCalculate() {
        if (this.segments.length === 0) {
            this.showToast('Error', 'Please add at least one segment', 'error');
            return;
        }

        // Warn if items already exist (recalculation will regenerate Scheduled items)
        if (this.paymentItems && this.paymentItems.length > 0) {
            const scheduledCount = this.paymentItems.filter(
                item => this.isScheduledStatus(item.status)
            ).length;
            const preservedCount = this.paymentItems.length - scheduledCount;

            let message = `This will regenerate ${scheduledCount} Scheduled payment(s) based on your segments.`;
            if (preservedCount > 0) {
                message += ` ${preservedCount} non-Scheduled payment(s) will be preserved.`;
            }
            message += '\n\nPlease verify your segments before continuing.';

            const confirmed = await LightningConfirm.open({
                message: message,
                label: 'Recalculate Payments?',
                theme: 'warning'
            });

            if (!confirmed) {
                return;
            }
        }

        this.isLoading = true;
        try {
            // Convert segments from camelCase to Salesforce field names for Apex
            const segmentsForApex = this.segments.map((seg, index) => ({
                Segment_Order__c: seg.segmentOrder || seg.Segment_Order__c || (index + 1),
                Segment_Type__c: seg.segmentType || seg.Segment_Type__c,
                Payment_Amount__c: seg.paymentAmount || seg.Payment_Amount__c,
                Payment_Count__c: seg.paymentCount || seg.Payment_Count__c,
                Frequency__c: seg.frequency || seg.Frequency__c,
                Start_Date__c: seg.startDate || seg.Start_Date__c,
                End_Date__c: seg.endDate || seg.End_Date__c || null
            }));

            const result = await calculateDraftPlan({
                // Pass null draftId for new unsaved drafts (no DB record yet)
                draftId: this.isNewUnsavedDraft ? null : this.currentDraftId,
                segments: segmentsForApex,
                balance: this.currentDraft?.Balance__c,
                settlementOffer: this.effectiveSettlementAmount,
                totalPaidAmount: this.getLocalPaidTotal()
            });

            if (result.success) {
                // Normalize payment items from SObject field names to camelCase
                this.paymentItems = this.normalizePaymentItems(result.paymentItems);
                this.isDirty = true;

                // Enable Save button for new drafts after Calculate
                this.hasCalculated = true;

                this.showToast('Success', `Generated ${result.numberOfPayments} payments`, 'success');
            } else {
                this.showToast('Calculation Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Payment table row editing
    handleRowEditClick(event) {
        const rowId = event.currentTarget.dataset.row;
        this.handleRowEditClickInternal(rowId);
    }

    handleRowEditClickInternal(rowId) {
        const item = this.paymentItems.find(i => i.sequenceNumber === rowId);
        if (item && item.isLocked) {
            this.showToast('Warning', 'This payment is locked and cannot be edited', 'warning');
            return;
        }

        // If switching from another row, handle the previous row first
        if (this.editingRowId && this.editingRowId !== rowId) {
            this.handleRowCancelClick(); // Revert/remove previous
        }

        // Store snapshot of current values for revert on cancel
        this.editingRowSnapshot = item ? { ...item } : null;
        this.editingRowId = rowId;
    }

    handleRowSaveClick() {
        // Find the item being edited
        const editingItem = this.paymentItems.find(
            item => item.sequenceNumber === this.editingRowId
        );

        if (!editingItem) {
            this.editingRowId = null;
            return;
        }

        // Validate required fields
        const errors = [];
        if (!editingItem.paymentDate) {
            errors.push('Payment Date is required');
        }
        if (!editingItem.paymentAmount || parseFloat(editingItem.paymentAmount) <= 0) {
            errors.push('Payment Amount must be greater than zero');
        }

        if (errors.length > 0) {
            this.showToast('Validation Error', errors.join('. '), 'error');
            return; // Stay in edit mode
        }

        // Validation passed - clear edit state
        this.editingRowSnapshot = null;
        this.editingRowId = null;
        this.isDirty = true;
        this.sortPaymentItemsByDate();
    }

    /**
     * Sort payment items by date and renumber sequence
     */
    sortPaymentItemsByDate() {
        const items = [...this.paymentItems];
        
        // Sort by payment date
        items.sort((a, b) => {
            const dateA = a.paymentDate || '9999-12-31';
            const dateB = b.paymentDate || '9999-12-31';
            return dateA.localeCompare(dateB);
        });

        // Renumber sequence numbers after sorting
        items.forEach((item, index) => {
            item.sequenceNumber = String(index + 1);
            item.paymentNumber = index + 1;
        });

        this.paymentItems = items;
    }

    getLocalPaidTotal() {
        if (!this.paymentItems || this.paymentItems.length === 0) {
            return 0;
        }
        return this.paymentItems.reduce((sum, item) => {
            // Paid total should reflect historical DB state, not unsaved local status edits.
            // Only count items that exist in the DB (have dbStatus).
            const paidStatus = item.dbStatus;
            if (paidStatus && this.isPaidStatus(paidStatus)) {
                const amount = parseFloat(item.paymentAmount || item.Payment_Amount__c || 0) || 0;
                return sum + amount;
            }
            return sum;
        }, 0);
    }

    /**
     * Remove a row from paymentItems and renumber remaining rows
     */
    removePaymentRow(sequenceNumber) {
        const items = this.paymentItems.filter(i => i.sequenceNumber !== sequenceNumber);
        items.forEach((itm, index) => {
            itm.sequenceNumber = String(index + 1);
            itm.paymentNumber = index + 1;
        });
        this.paymentItems = items;
    }

    handleRowCancelClick() {
        if (!this.editingRowId) return;

        const item = this.paymentItems.find(i => i.sequenceNumber === this.editingRowId);

        if (item) {
            // Row added via Add Row (snapshot is null) - remove on cancel
            // Note: We check snapshot, not item.id, because Calculate-generated rows
            // also have id=null before Save, but they DO have a snapshot when edited
            if (this.editingRowSnapshot === null) {
                this.removePaymentRow(this.editingRowId);
            }
            // Row had prior state (Calculate-generated or DB-saved) - revert to snapshot
            else {
                const index = this.paymentItems.findIndex(i => i.sequenceNumber === this.editingRowId);
                if (index >= 0) {
                    this.paymentItems[index] = { ...this.editingRowSnapshot };
                    this.paymentItems = [...this.paymentItems]; // Trigger reactivity
                }
            }
        }

        this.editingRowSnapshot = null;
        this.editingRowId = null;
    }

    // Fields that affect Settlement_Fee__c records (amount + fee fields)
    static FEE_FIELDS = new Set(['paymentAmount', 'commissionFee', 'eppsTransactionFee']);

    handleCellEdit(event) {
        const rowId = event.target.dataset.row;
        const field = event.target.dataset.field;
        let value = event.target.value;

        const items = [...this.paymentItems];
        const itemIndex = items.findIndex(item => item.sequenceNumber === rowId);

        if (itemIndex >= 0) {
            const updates = {
                [field]: value,
                isManuallyModified: true
            };
            // Only flag fee changes when a fee/amount field is edited
            if (SettlementPlanBuilder.FEE_FIELDS.has(field)) {
                updates.hasPendingFeeChanges = true;
            }
            items[itemIndex] = {
                ...items[itemIndex],
                ...updates
            };

            this.paymentItems = items;
            this.currentDraft = {
                ...this.currentDraft,
                Is_Manually_Modified__c: true
            };
            this.isDirty = true;
        }
    }

    /**
     * Handle blur for numeric cell edits (amount, fees) to avoid cursor jump issues
     */
    handleCellEditBlur(event) {
        const rowId = event.target.dataset.row;
        const field = event.target.dataset.field;
        let value = event.target.value;

        const items = [...this.paymentItems];
        const itemIndex = items.findIndex(item => item.sequenceNumber === rowId);

        if (itemIndex >= 0) {
            // Parse numeric fields (amount and fees)
            if (field === 'paymentAmount' || field === 'commissionFee') {
                value = parseFloat(value) || 0;
            }

            items[itemIndex] = {
                ...items[itemIndex],
                [field]: value,
                isManuallyModified: true,
                // handleCellEditBlur only fires for fee/amount fields, so always flag fee changes
                hasPendingFeeChanges: true
            };

            // Recalculate totalFees when any fee field changes
            if (field === 'commissionFee' || field === 'eppsTransactionFee') {
                const item = items[itemIndex];
                items[itemIndex].totalFees =
                    (item.commissionFee || 0) +
                    (item.eppsTransactionFee || 0);
            }

            this.paymentItems = items;
            this.currentDraft = {
                ...this.currentDraft,
                Is_Manually_Modified__c: true
            };
            this.isDirty = true;
        }
    }

    /**
     * Add a new empty payment row and enter edit mode
     * All fees come from config (loaded on init) - no user input needed
     * No dependency on previous rows - works for any insertion order
     */
    handleAddPaymentRow() {
        const items = [...this.paymentItems];

        const newSequenceNumber = items.length > 0
            ? Math.max(...items.map(i => parseInt(i.sequenceNumber, 10))) + 1
            : 1;

        // All fees from config (loaded on init)
        const commissionFee = this.feeConfig.commissionFee;
        const eppsTransactionFee = this.feeConfig.eppsTransactionFee;
        const totalFees = commissionFee + eppsTransactionFee;

        // Create new row - fees are derived from config + commission
        const newItem = {
            sequenceNumber: String(newSequenceNumber),
            paymentNumber: newSequenceNumber,
            paymentDate: null,
            originalPaymentDate: null,
            paymentAmount: null,
            commissionFee: commissionFee,
            eppsTransactionFee: eppsTransactionFee,
            totalFees: totalFees,
            status: this.scheduledStatusValue || 'Scheduled',
            paymentMethod: null, // User must select explicitly
            isManuallyModified: true,
            hasPendingFeeChanges: true, // New rows need fee record creation
            isLocked: false, // New rows are never locked - only locks after save/reload
            dbStatus: null,
            // Phase 41: Simplified action flags - new rows show Edit/Delete icons
            isScheduledWithDbId: false,
            isProcessingWithDbId: false,
            isUnsavedRow: true
        };

        items.push(newItem);
        this.paymentItems = items;
        this.currentDraft = {
            ...this.currentDraft,
            Is_Manually_Modified__c: true
        };
        this.isDirty = true;

        // Auto-enter edit mode for the new row
        // New rows have no snapshot to revert to (cancel removes them entirely)
        this.editingRowSnapshot = null;
        this.editingRowId = String(newSequenceNumber);

        // Auto-scroll to bottom of table to show new row
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const tableContainer = this.template.querySelector('.payment-table-container');
            if (tableContainer) {
                tableContainer.scrollTop = tableContainer.scrollHeight;
            }
        }, 100);
    }

    /**
     * Delete a payment row from the schedule (event handler)
     */
    handleDeletePaymentRow(event) {
        const rowId = event.currentTarget.dataset.row;
        this.handleDeletePaymentRowInternal(rowId);
    }

    /**
     * Delete a payment row from the schedule (internal implementation)
     */
    handleDeletePaymentRowInternal(rowId) {
        // Check if row is locked (based on DB state, not current in-memory status)
        const itemToDelete = this.paymentItems.find(i => i.sequenceNumber === rowId);
        if (itemToDelete && itemToDelete.isLocked) {
            this.showToast('Warning', 'This payment is locked and cannot be deleted', 'warning');
            return;
        }

        if (this.paymentItems.length <= 1) {
            this.showToast('Warning', 'Cannot delete the last payment row', 'warning');
            return;
        }

        // Clear edit state if deleting the row currently being edited
        if (this.editingRowId === rowId) {
            this.editingRowId = null;
            this.editingRowSnapshot = null;
        }

        // Track which item is being edited (by reference, before filter/renumber)
        let editingItem = null;
        if (this.editingRowId) {
            editingItem = this.paymentItems.find(i => i.sequenceNumber === this.editingRowId);
        }

        const items = this.paymentItems.filter(item => item.sequenceNumber !== rowId);

        // Renumber sequence numbers
        items.forEach((item, index) => {
            item.sequenceNumber = String(index + 1);
            item.paymentNumber = index + 1;
        });

        this.paymentItems = items;

        // Update editingRowId to match renumbered sequence of the item being edited
        if (editingItem) {
            this.editingRowId = editingItem.sequenceNumber;
        }
        this.currentDraft = {
            ...this.currentDraft,
            Is_Manually_Modified__c: true
        };
        this.isDirty = true;

        this.showToast('Info', 'Payment row deleted', 'info');
    }

    /**
     * Handle row actions from dropdown menu
     * Routes to appropriate handler based on action value
     */
    handleRowAction(event) {
        const action = event.detail.value;
        // Get row ID from data-row attribute on the lightning-button-menu
        // Use currentTarget (the element with the handler) not target (shadow DOM issues)
        const rowId = event.currentTarget.dataset.row;

        if (!rowId) {
            console.error('Could not determine row ID for action:', action);
            return;
        }

        switch (action) {
            case 'edit':
                this.handleRowEditClickInternal(rowId);
                break;
            case 'delete':
                this.handleDeletePaymentRowInternal(rowId);
                break;
            case 'void':
            case 'immediateProcess':
                // Placeholder until Apex methods are ready
                this.showToast('Info', 'Currently in Test', 'info');
                break;
            default:
                console.warn('Unknown action:', action);
        }
    }

    /**
     * Handle Void button click (Phase 41 - direct button instead of dropdown)
     * For Processing rows only
     */
    handleVoidClick(event) {
        const rowId = event.currentTarget.dataset.row;
        // Placeholder until Apex method is ready
        this.showToast('Info', 'Void functionality coming soon', 'info');
        console.log('Void clicked for row:', rowId);
    }

    /**
     * Validate payment items before save
     * @returns {Object} { isValid: boolean, errorMessage: string }
     */
    validatePaymentItems() {
        const errors = [];

        this.paymentItems.forEach((item, index) => {
            const rowNum = index + 1;
            if (!item.paymentDate || item.paymentDate === '') {
                errors.push(`Row ${rowNum}: Payment Date is required`);
            }
            if (!item.paymentNumber) {
                errors.push(`Row ${rowNum}: Payment Number is required`);
            }
            if (!item.paymentAmount || parseFloat(item.paymentAmount) <= 0) {
                errors.push(`Row ${rowNum}: Payment Amount must be greater than zero`);
            }
        });

        if (errors.length > 0) {
            return {
                isValid: false,
                errorMessage: errors.slice(0, 3).join('. ') +
                              (errors.length > 3 ? ` (+${errors.length - 3} more)` : '')
            };
        }

        return { isValid: true, errorMessage: null };
    }

    // Event handlers - Save
    async handleSaveDraft() {
        // Validate payment items before saving
        if (this.paymentItems && this.paymentItems.length > 0) {
            const validation = this.validatePaymentItems();
            if (!validation.isValid) {
                this.showToast('Validation Error', validation.errorMessage, 'error');
                return false;
            }
        }

        // Check for weekend/holiday dates and warn user
        if (this.paymentItems && this.paymentItems.length > 0) {
            const paymentDates = this.paymentItems
                .map(item => item.paymentDate)
                .filter(d => d != null);

            if (paymentDates.length > 0) {
                try {
                    const dateValidation = await validatePaymentDates({ paymentDates });
                    if (dateValidation.hasNonBusinessDays) {
                        const warningLines = dateValidation.nonBusinessDays.map(info =>
                            `Row ${info.rowNumber}: ${this.formatDate(info.paymentDate)} (${info.dateType})`
                        );
                        const message = 'The following payment dates fall on a weekend or holiday:\n\n' +
                            warningLines.join('\n') +
                            '\n\nDates will be saved as entered. Continue?';

                        const confirmed = await LightningConfirm.open({
                            message: message,
                            label: 'Non-Business Day Warning',
                            theme: 'warning'
                        });

                        if (!confirmed) {
                            return false;
                        }
                    }
                } catch (error) {
                    console.error('[SettlementPlanBuilder] Date validation error:', error);
                    // Continue with save if validation fails - don't block user
                }
            }
        }

        this.isLoading = true;
        let didSave = false;
        try {
            // Convert segments to SObject format for Apex
            // Include Id field for upsert - without it, Apex inserts duplicates
            const segmentsToSave = this.segments.map((seg, index) => ({
                Id: seg.id || null,
                Segment_Order__c: seg.segmentOrder || seg.Segment_Order__c || (index + 1),
                Segment_Type__c: seg.segmentType || seg.Segment_Type__c,
                Payment_Amount__c: seg.paymentAmount || seg.Payment_Amount__c,
                Payment_Count__c: seg.paymentCount || seg.Payment_Count__c,
                Frequency__c: seg.frequency || seg.Frequency__c,
                Start_Date__c: seg.startDate || seg.Start_Date__c,
                End_Date__c: seg.endDate || seg.End_Date__c || null
            }));

            // Convert payment items to DTO format (camelCase matching @AuraEnabled properties)
            // IMPORTANT: Include id for historical items so they are
            // recognized and skipped during save (not duplicated)
            let itemsForSave = this.paymentItems.map((item, index) => {
                const paymentDate = item.paymentDate || null;
                const paymentNumber = item.paymentNumber || (index + 1);

                // Diagnostic logging for missing required fields
                if (!paymentDate || !paymentNumber) {
                    console.error('[SettlementPlanBuilder] Item missing required fields at index', index,
                        'paymentDate:', item.paymentDate, 'paymentNumber:', item.paymentNumber,
                        'full item:', JSON.stringify(item));
                }

                return {
                    id: item.id || null,
                    segmentId: item.segmentId || null,
                    paymentNumber: paymentNumber,
                    paymentDate: paymentDate,
                    originalPaymentDate: item.originalPaymentDate || null,
                    paymentAmount: item.paymentAmount || 0,
                    commissionFee: item.commissionFee || 0,
                    eppsTransactionFee: item.eppsTransactionFee || 0,
                    status: item.status || this.scheduledStatusValue || 'Scheduled',
                    paymentMethod: item.paymentMethod || null,
                    hasOverride: item.hasPendingFeeChanges || false
                };
            });

            // Recalculate balances before saving (handles manually added/edited rows)
            // Skip for new drafts with no items (Calculate generates fresh items)
            if (itemsForSave.length > 0) {
                const recalcResult = await recalculateBalances({
                    items: itemsForSave,
                    settlementOffer: this.effectiveSettlementAmount
                });

                if (recalcResult.success) {
                    // Keep original itemsForSave (plain objects) for save —
                    // recalculate only computes summary totals, does not modify item data.
                    // Replacing with recalcResult.paymentItems (Apex response proxy)
                    // causes null fields on the next Apex call.

                    // Update local state with recalculated values
                    this.updateLocalItemsFromRecalc(recalcResult.paymentItems);
                }
            }

            // Build draft fields to save (Commission_Fee__c removed - fees now in Settlement_Fee__c)
            const draftFieldsToSave = {
                Name: this.currentDraft?.Name,
                Balance__c: this.currentDraft?.Balance__c,
                Settlement_Offer_Amount__c: this.currentDraft?.Settlement_Offer_Amount__c,
                Revised_Settlement_Amount__c: this.currentDraft?.Revised_Settlement_Amount__c,
                Escrow_Start_Balance__c: this.currentDraft?.Escrow_Start_Balance__c,
                Is_Manually_Modified__c: this.currentDraft?.Is_Manually_Modified__c,
                Contract_File_ID__c: this.currentDraft?.Contract_File_ID__c
            };

            let savedDraft;

            if (this.isNewUnsavedDraft) {
                // NEW DRAFT: Create and save in one atomic transaction
                // This prevents orphan drafts when user previews but never saves
                savedDraft = await createAndSaveDraft({
                    creditorOpportunityId: this.recordId,
                    draftName: this.currentDraft?.Name,
                    segments: segmentsToSave,
                    items: itemsForSave,
                    draftFields: draftFieldsToSave
                });

                // Update local state - draft now exists in DB
                this.currentDraftId = savedDraft.Id;
                this.isNewUnsavedDraft = false;
                this.drafts = [...this.drafts, savedDraft];

            } else {
                // EXISTING DRAFT: Use current save logic
                savedDraft = await saveDraftWithRecords({
                    draftId: this.currentDraftId,
                    segments: segmentsToSave,
                    items: itemsForSave,
                    draftFields: draftFieldsToSave
                });

                // Update draft in list
                const draftsCopy = [...this.drafts];
                const index = draftsCopy.findIndex(d => d.Id === savedDraft.Id);
                if (index >= 0) {
                    draftsCopy[index] = savedDraft;
                    this.drafts = draftsCopy;
                }
            }

            this.currentDraft = savedDraft;
            this.isDirty = false;

            // Reload draft details to get database-assigned IDs (prevents duplicate inserts on next save)
            const wrapper = await getDraftWithDetails({ draftId: savedDraft.Id });
            this.segments = this.normalizeSegments(wrapper.segments || []);
            // Rebuild fee map before normalizing items (fee map drives amount/fee display)
            this.buildFeeMap(wrapper.feeRecords || []);
            this.paymentItems = this.normalizePaymentItems(wrapper.paymentItems || []);

            this.showToast('Success', 'Draft saved', 'success');
            didSave = true;
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }

        return didSave;
    }

    // Event handlers - Update (creates a copy of the draft)
    async handleCloneDraft() {
        const existingNames = (this.drafts || []).map(d => d?.Name).filter(Boolean);
        const cloneName = this.buildNextDraftVersionName(this.currentDraft?.Name, existingNames);

        this.isLoading = true;
        try {
            const clonedDraft = await cloneDraft({
                sourceDraftId: this.currentDraftId,
                newName: cloneName
            });

            this.drafts = [...this.drafts, clonedDraft];
            await this.selectDraft(clonedDraft.Id);

            this.showToast('Success', 'Draft updated', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Delete
    async handleDeleteDraft() {
        const confirmDelete = await this.confirmAction(
            'Are you sure you want to delete this draft? This cannot be undone.'
        );
        if (!confirmDelete) return;

        this.isLoading = true;
        try {
            await deleteDraft({ draftId: this.currentDraftId });

            this.drafts = this.drafts.filter(d => d.Id !== this.currentDraftId);

            if (this.drafts.length > 0) {
                await this.selectDraft(this.drafts[0].Id);
            } else {
                this.currentDraftId = null;
                this.currentDraft = null;
                this.segments = [];
                this.paymentItems = [];
            }

            this.showToast('Success', 'Draft deleted', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Activate
    async handleActivate() {
        // Check if bank account information is set on the CreditorOpportunity
        if (!this.creditorOpportunity?.Account_Bank_Information__c) {
            this.showToast(
                'Missing Bank Information',
                'Please set the Account Bank Information on the Creditor Opportunity before activating.',
                'error'
            );
            return;
        }

        if (!this.isBalanced) {
            const proceed = await this.confirmAction(
                `The plan is ${this.balanceStatusText.toLowerCase()} by $${Math.abs(this.fundingDifferenceValue).toFixed(2)}. Activate anyway?`
            );
            if (!proceed) return;
        }

        const confirmActivate = await this.confirmAction(
            'This will create real payment records and replace any existing plan. Continue?'
        );
        if (!confirmActivate) return;

        if (this.isDirty) {
            const saved = await this.handleSaveDraft();
            if (!saved) return;
        }

        this.isLoading = true;
        try {
            const result = await activateDraft({ draftId: this.currentDraftId });

            if (result.success) {
                this.showToast(
                    'Success',
                    `Activated plan with ${result.paymentItemCount} payment items`,
                    'success'
                );
                // Reload to show updated status
                this.isInitialized = false;
                await this.loadInitialData();
            } else {
                this.showToast('Activation Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Suspend
    async handleAddPaymentOnSuspended() {
        if (!this.currentDraftId) return;

        try {
            const result = await AddSuspendedPaymentModal.open({
                label: 'Submit a Payment to Escrow',
                size: 'small',
                commissionFee: this.feeConfig.commissionFee || 0
            });

            if (!result) return;

            this.isLoading = true;

            const wrapper = await addSuspendedImmediateProcessingPayment({
                draftId: this.currentDraftId,
                paymentDate: result.paymentDate,
                paymentAmount: result.paymentAmount,
                commissionFee: result.commissionFee
            });

            this.loadDraftDetails(wrapper);

            // Update draft status in tabs list (draft stays Suspended, totals may change)
            const draftsCopy = [...this.drafts];
            const index = draftsCopy.findIndex(d => d.Id === this.currentDraftId);
            if (index >= 0) {
                draftsCopy[index] = wrapper.draft;
                this.drafts = draftsCopy;
            }

            this.showToast('Success', 'Payment submitted for immediate processing.', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSuspendPlan() {
        // Count Scheduled items that will be suspended (only Scheduled items get suspended now)
        const suspendableCount = this.paymentItems.filter(
            item => this.isScheduledStatus(item.status)
        ).length;

        if (suspendableCount === 0) {
            this.showToast('Info', 'No payments to suspend.', 'info');
            return;
        }

        // Confirmation
        const confirmed = await LightningConfirm.open({
            message: `Are you sure you want to suspend ${suspendableCount} payment(s)? This will mark the plan as Suspended.`,
            label: 'Confirm Suspend',
            theme: 'warning'
        });

        if (!confirmed) return;

        this.isLoading = true;
        try {
            const count = await suspendPaymentItems({ draftId: this.currentDraftId });

            // Reload current draft details directly (not loadInitialData which searches for Active/Draft)
            const wrapper = await getDraftWithDetails({ draftId: this.currentDraftId });
            this.loadDraftDetails(wrapper);

            // Update draft status in tabs list
            const draftsCopy = [...this.drafts];
            const index = draftsCopy.findIndex(d => d.Id === this.currentDraftId);
            if (index >= 0) {
                draftsCopy[index] = wrapper.draft;
                this.drafts = draftsCopy;
            }

            this.showToast('Success', `${count} payment(s) suspended.`, 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Utility methods

    /**
     * Map SObject fields to JS property names using a field map
     * @param {Object} sObject - Object with SObject field names
     * @param {Object} fieldMap - Map of SObject field names to JS property names
     * @returns {Object} - Object with JS property names
     */
    mapSObjectToJs(sObject, fieldMap) {
        const result = {};
        for (const [sfField, jsField] of Object.entries(fieldMap)) {
            if (sObject[sfField] !== undefined) {
                result[jsField] = sObject[sfField];
            }
        }
        return result;
    }

    /**
     * Compute all status-related flags for a payment item
     * Centralizes status logic that was previously duplicated in normalizePaymentItems and updateLocalItemsFromRecalc
     * @param {Object} item - Payment item (can have SObject or JS property names)
     * @returns {Object} - Status info with isScheduled, isProcessing, isLocked, and action flags
     */
    getItemStatusInfo(item) {
        const status = item.Status__c || item.status || 'Scheduled';
        const hasDbId = !!(item.Id || item.id);
        const dbStatus = hasDbId ? status : null;
        const isScheduled = this.isScheduledStatus(status);
        const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();
        const isProcessing = (status || '').toLowerCase() === processingValue;

        return {
            status,
            dbStatus,
            isScheduled,
            isProcessing,
            isLocked: dbStatus ? !isScheduled : false,
            // Simplified action flags for Phase 41
            isScheduledWithDbId: isScheduled && hasDbId,
            isProcessingWithDbId: isProcessing && hasDbId,
            isUnsavedRow: !hasDbId
        };
    }

    /**
     * Normalize segments from SObject field names to camelCase JS property names
     * Used when loading draft details to convert Apex response for segmentBuilder component
     * @param {Array} segments - Array of segments with SObject field names
     * @returns {Array} - Array of segments with camelCase property names
     */
    normalizeSegments(segments) {
        if (!segments || segments.length === 0) return [];
        
        return segments.map((seg, index) => ({
            key: `seg-${Date.now()}-${index}`,
            id: seg.Id,
            segmentOrder: seg.Segment_Order__c || seg.segmentOrder || (index + 1),
            segmentType: seg.Segment_Type__c || seg.segmentType || 'Fixed',
            paymentAmount: seg.Payment_Amount__c || seg.paymentAmount,
            paymentCount: seg.Payment_Count__c || seg.paymentCount,
            frequency: seg.Frequency__c || seg.frequency || 'Monthly',
            startDate: seg.Start_Date__c || seg.startDate,
            endDate: seg.End_Date__c || seg.endDate || null
        }));
    }

    /**
     * Normalize payment items from SObject or DTO shape to camelCase JS property names.
     * Handles both SObject shape (from getDraftWithDetails) and DTO shape (from calculateDraftPlan).
     * Preserves item IDs (important for locked items that should not be duplicated on save).
     * For Calculate-generated items (no ID), applies config fees for preview display.
     * @param {Array} items - Array of payment items (SObject or DTO shape)
     * @returns {Array} - Array of payment items with camelCase property names
     */
    normalizePaymentItems(items) {
        if (!items || items.length === 0) return [];

        return items.map((item, index) => {
            // Detect if item is SObject shape (from DB load) or DTO shape (from calculate)
            const isSObject = 'Payment_Date__c' in item;

            // Map fields based on shape
            const mapped = isSObject
                ? this.mapSObjectToJs(item, ITEM_FIELD_MAP)
                : {};

            // Base fields - prefer DTO fields, fall back to mapped SObject fields
            const id = item.id || item.Id || mapped.id || null;
            const paymentNumber = item.paymentNumber || mapped.paymentNumber || item.Payment_Number__c || index + 1;
            const paymentDate = item.paymentDate || mapped.paymentDate || null;
            const originalPaymentDate = item.originalPaymentDate || mapped.originalPaymentDate || null;
            const segmentId = item.segmentId || mapped.segmentId || null;
            const paymentMethod = item.paymentMethod || mapped.paymentMethod || '';
            const isManuallyModified = item.hasOverride || mapped.isManuallyModified || false;

            // Use helper to compute all status-related flags
            const statusInfo = isSObject
                ? this.getItemStatusInfo(item)
                : this.getItemStatusInfo({
                    Id: id,
                    Status__c: item.status || 'Scheduled'
                });

            // Settlement_Fee__c is the source of truth for all fee/amount data
            // - DB items: Read from Fee records (feesByItemId map)
            // - Preview items (no ID): Apply config fees for display
            const hasDbId = !!id;
            let paymentAmount, commissionFee, eppsTransactionFee;

            if (hasDbId && this.feesByItemId.has(id)) {
                // DB item with fee records
                const feeData = this.feesByItemId.get(id);
                paymentAmount = feeData.paymentAmount || 0;
                commissionFee = feeData.commissionFee || 0;
                eppsTransactionFee = feeData.eppsTransactionFee || 0;
            } else if (hasDbId) {
                // DB item without fee records (legacy)
                paymentAmount = 0;
                commissionFee = 0;
                eppsTransactionFee = 0;
            } else {
                // Preview item (from calculate) — amount from DTO, fees from config
                paymentAmount = item.paymentAmount || 0;
                commissionFee = this.feeConfig.commissionFee || 0;
                eppsTransactionFee = this.feeConfig.eppsTransactionFee || 0;
            }

            const totalFees = commissionFee + eppsTransactionFee;

            return {
                id,
                sequenceNumber: String(index + 1),
                paymentNumber,
                paymentDate,
                originalPaymentDate,
                segmentId,
                paymentAmount,
                commissionFee,
                eppsTransactionFee,
                totalFees,
                status: statusInfo.status,
                paymentMethod,
                isManuallyModified,
                hasPendingFeeChanges: false, // DB load = fees already saved, no pending changes
                isLocked: statusInfo.isLocked,
                dbStatus: statusInfo.dbStatus,
                isScheduledWithDbId: statusInfo.isScheduledWithDbId,
                isProcessingWithDbId: statusInfo.isProcessingWithDbId,
                isUnsavedRow: statusInfo.isUnsavedRow
            };
        });
    }

    /**
     * Update local payment items with recalculated values from Apex.
     * Recalculate response now returns DTOs (camelCase).
     * Preserves item IDs, dbStatus, isLocked, and fees from original items.
     */
    updateLocalItemsFromRecalc(recalcItems) {
        if (!recalcItems || recalcItems.length === 0) return;

        const updatedItems = recalcItems.map((item, index) => {
            const existingItem = this.paymentItems.find(e => e.id && e.id === item.id) || this.paymentItems[index];
            // DTO uses camelCase directly
            const itemId = item.id || existingItem?.id || null;

            const dbStatus = existingItem?.dbStatus || null;
            const isLocked = dbStatus ? !this.isScheduledStatus(dbStatus) : (existingItem?.isLocked || false);

            const status = item.status || 'Scheduled';
            const hasDbId = !!itemId;
            const isScheduled = this.isScheduledStatus(status);
            const processingValue = (this.processingStatusValue || 'Processing').toLowerCase();
            const isProcessing = (status || '').toLowerCase() === processingValue;

            // Fees preserved from existing item (recalc doesn't change fees)
            const commissionFee = existingItem?.commissionFee || 0;
            const eppsTransactionFee = existingItem?.eppsTransactionFee || 0;
            const totalFees = existingItem?.totalFees || 0;

            return {
                id: itemId,
                sequenceNumber: String(index + 1),
                paymentNumber: item.paymentNumber || existingItem?.paymentNumber || index + 1,
                paymentDate: item.paymentDate || existingItem?.paymentDate,
                originalPaymentDate: item.originalPaymentDate || existingItem?.originalPaymentDate,
                segmentId: item.segmentId || existingItem?.segmentId,
                paymentAmount: item.paymentAmount ?? existingItem?.paymentAmount ?? 0,
                commissionFee,
                eppsTransactionFee,
                totalFees,
                status,
                paymentMethod: item.paymentMethod || existingItem?.paymentMethod || '',
                isManuallyModified: item.hasOverride || existingItem?.isManuallyModified || false,
                hasPendingFeeChanges: existingItem?.hasPendingFeeChanges || false,
                isLocked,
                dbStatus,
                isScheduledWithDbId: isScheduled && hasDbId,
                isProcessingWithDbId: isProcessing && hasDbId,
                isUnsavedRow: !hasDbId
            };
        });

        this.paymentItems = updatedItems;
    }

    formatCurrency(value) {
        if (value === null || value === undefined) return '$0.00';
        // Normalize near-zero to avoid "-$0.00" from floating-point arithmetic
        if (Math.abs(value) < 0.005) value = 0;
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        // Handle both ISO string and Date object
        const date = typeof dateValue === 'string' ? new Date(dateValue + 'T00:00:00') : dateValue;
        return date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        });
    }

    formatLocalDateYYYYMMDD(date) {
        const yyyy = String(date.getFullYear());
        const mm = String(date.getMonth() + 1).padStart(2, '0');
        const dd = String(date.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }

    buildNextDraftVersionName(currentName, existingNames) {
        const MAX_NAME_LENGTH = 80;

        const existingLower = new Set((existingNames || []).map(n => String(n).toLowerCase()));

        let name = (currentName || '').trim();
        if (!name) {
            name = `Draft ${this.formatLocalDateYYYYMMDD(new Date())}`;
        }

        // If the name already ends with vN, increment N. Otherwise start at v2.
        // Only treat it as a version when it's a trailing token.
        const versionMatch = name.match(/\s+v(\d+)\s*$/i);
        let base = name;
        let nextVersion = 2;

        if (versionMatch) {
            nextVersion = parseInt(versionMatch[1], 10) + 1;
            base = name.slice(0, versionMatch.index).trim();
        }

        // Safety: trim base so the final name fits typical Salesforce Name limits.
        const buildCandidate = (versionNumber) => {
            const suffix = ` v${versionNumber}`;
            let trimmedBase = (base || '').trim();
            const maxBaseLen = Math.max(0, MAX_NAME_LENGTH - suffix.length);
            if (trimmedBase.length > maxBaseLen) {
                trimmedBase = trimmedBase.slice(0, maxBaseLen).trimEnd();
            }
            if (!trimmedBase) {
                trimmedBase = 'Draft';
            }
            return `${trimmedBase}${suffix}`;
        };

        let candidate = buildCandidate(nextVersion);
        while (existingLower.has(candidate.toLowerCase())) {
            nextVersion += 1;
            candidate = buildCandidate(nextVersion);
        }

        return candidate;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }

    async confirmAction(message) {
        return await LightningConfirm.open({
            message: message,
            variant: 'header',
            label: 'Confirm Action',
            theme: 'warning'
        });
    }
}