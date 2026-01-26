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
import getFeeConfig from '@salesforce/apex/SettlementDraftController.getFeeConfig';

// CreditorOpportunity fields for @wire
const FIELDS = ['CreditorOpportunity__c.Name'];

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

            if (this.paymentItems && this.paymentItems.length > 0) {
                this.paymentItems = this.paymentItems.map(item => {
                    if (!item.id || !item.dbStatus) return item;
                    return {
                        ...item,
                        isLocked: !this.isScheduledStatus(item.dbStatus)
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
    isInitialized = false; // No @track needed - only used internally, not in template

    // Lazy draft creation state
    @track isNewUnsavedDraft = false;  // True when "New Draft" clicked but not yet saved to DB
    @track hasCalculated = false;      // True after Calculate clicked (enables Save for new drafts)

    // Accordion state - controls which sections are expanded
    @track activeSections = [];  // ['settlement-details', 'payment-segments'] when expanded

    // Fee config - loaded on init for Add Row (no dependency on previous rows)
    @track feeConfig = { bankFee: 0, eppsTransactionFee: 0 };

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
        return status === 'Active' || status === 'Suspended' || status === 'Applied' || status === 'Archived';
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

    get hasSegments() {
        return this.segments && this.segments.length > 0;
    }

    /**
     * Get effective settlement amount (revised if set, otherwise original)
     */
    get effectiveSettlementAmount() {
        return this.currentDraft?.Revised_Settlement_Amount__c ||
               this.currentDraft?.Settlement_Offer_Amount__c || 0;
    }

    get fundingDifferenceValue() {
        return this.currentDraft?.Funding_Difference__c || 0;
    }

    get isBalanced() {
        return Math.abs(this.fundingDifferenceValue) <= 0.10;
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
        const balance = this.currentDraft?.Current_Balance__c || 0;
        if (balance < 0) {
            return 'slds-text-heading_medium summary-value-error';
        } else if (balance === 0) {
            return 'slds-text-heading_medium summary-value-success';
        }
        return 'slds-text-heading_medium';
    }

    get formattedTotalPaidAmount() {
        return this.formatCurrency(this.currentDraft?.Total_Paid_Amount__c || 0);
    }

    get formattedTotalScheduledAmount() {
        return this.formatCurrency(this.currentDraft?.Total_Scheduled_Amount__c || 0);
    }

    get formattedCurrentBalance() {
        return this.formatCurrency(this.currentDraft?.Current_Balance__c || 0);
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
        return this.currentDraft?.Number_of_Payments__c || 0;
    }

    get createdByName() {
        return this.currentDraft?.CreatedBy?.Name || '';
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

    get cannotSuspend() {
        return !this.canSuspend;
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
                isApplied: draft.Status__c === 'Applied',
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
                isApplied: false,
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
            case 'Suspended': return 'slds-badge slds-badge_warning'; // Orange/yellow badge
            case 'Applied': return 'slds-badge slds-badge_inverse';
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

        return this.paymentItems.map(item => {
            const status = item.status || 'Scheduled';
            // isLocked reflects DB state only - set in normalizePaymentItems when loading from DB
            // Row should only lock after save, not when user changes status in dropdown
            const isLocked = item.isLocked === true;
            const isProblemStatus = this.problemStatuses.includes(status);

            // Build row class - priority: locked > problem > modified
            let rowClass = 'slds-hint-parent';
            if (isLocked) {
                rowClass += ' locked-row';
            } else if (isProblemStatus) {
                rowClass += ' problem-row';
            } else if (item.isManuallyModified) {
                rowClass += ' modified-row';
            }

            return {
                ...item,
                formattedDate: this.formatDate(item.paymentDate),
                formattedAmount: this.formatCurrency(item.paymentAmount),
                formattedBankFee: this.formatCurrency(item.bankFee),
                formattedCommissionFee: this.formatCurrency(item.commissionFee),
                formattedEppsFee: this.formatCurrency(item.eppsTransactionFee),
                formattedTotalFees: this.formatCurrency(item.totalFees),
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
                showModifiedIcon: item.isManuallyModified && !isLocked
            };
        });
    }

    /**
     * Get badge class for payment item status
     */
    getPaymentStatusBadgeClass(status) {
        const statusValue = (status || '').toLowerCase();
        const cleared = (this.clearedStatusValue || 'Cleared').toLowerCase();
        const processing = (this.processingStatusValue || 'Processing').toLowerCase();

        if (statusValue === cleared) return 'slds-badge slds-badge_success';
        if (statusValue === processing) return 'slds-badge slds-badge_inverse';

        switch (status) {
            case 'Missed': return 'slds-badge slds-badge_error';
            case 'Cancelled': return 'slds-badge slds-badge_warning';
            case 'Skipped': return 'slds-badge slds-badge_warning';
            case 'Suspended': return 'slds-badge slds-badge_warning'; // Orange badge for suspended
            default: return 'slds-badge slds-badge_lightest'; // Scheduled/Other
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
        this.paymentItems = this.normalizePaymentItems(wrapper.paymentItems || []);
        this.isDirty = false;
        this.editingRowId = null;

        // Reset lazy draft creation state when loading an existing draft
        this.isNewUnsavedDraft = false;
        this.hasCalculated = false;
    }

    /**
     * Load fee config values for Add Row
     * Called on init - no dependency on previous rows
     */
    async loadFeeConfig() {
        try {
            const config = await getFeeConfig();
            this.feeConfig = {
                bankFee: config.bankFee || 0,
                eppsTransactionFee: config.eppsTransactionFee || 0
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
        const dateStr = today.toLocaleDateString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        });
        const draftName = `Draft ${dateStr}`;

        // Set lazy draft creation state
        this.isNewUnsavedDraft = true;
        this.currentDraftId = null;
        this.hasCalculated = false;

        // Create local draft object with defaults from CreditorOpportunity
        this.currentDraft = {
            Name: draftName,
            Status__c: 'Draft',
            Balance__c: this.creditorOpportunity?.Amount__c,
            Escrow_Start_Balance__c: this.creditorOpportunity?.Escrow_Start_Balance__c,
            Settlement_Offer_Amount__c: null,
            Revised_Settlement_Amount__c: null,
            Commission_Fee__c: null,
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
            startDate: today.toISOString().split('T')[0]
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
                Start_Date__c: seg.startDate || seg.Start_Date__c
            }));

            const result = await calculateDraftPlan({
                // Pass null draftId for new unsaved drafts (no DB record yet)
                draftId: this.isNewUnsavedDraft ? null : this.currentDraftId,
                segments: segmentsForApex,
                balance: this.currentDraft?.Balance__c,
                settlementOffer: this.effectiveSettlementAmount,
                commissionFee: this.currentDraft?.Commission_Fee__c,
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

        // Check if row is locked (based on DB state, not current in-memory status)
        const item = this.paymentItems.find(i => i.sequenceNumber === rowId);
        if (item && item.isLocked) {
            this.showToast('Warning', 'This payment is locked and cannot be edited', 'warning');
            return;
        }

        this.editingRowId = rowId;
    }

    handleRowSaveClick() {
        this.editingRowId = null;
        this.isDirty = true;
        
        // Sort payment items by date after save
        this.sortPaymentItemsByDate();
    }

    /**
     * Sort payment items by date and renumber sequence
     */
    sortPaymentItemsByDate() {
        const items = [...this.paymentItems];
        
        // Sort by payment date
        items.sort((a, b) => {
            const dateA = a.paymentDate ? new Date(a.paymentDate) : new Date('9999-12-31');
            const dateB = b.paymentDate ? new Date(b.paymentDate) : new Date('9999-12-31');
            return dateA - dateB;
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

    handleRowCancelClick() {
        this.editingRowId = null;
    }

    handleCellEdit(event) {
        const rowId = event.target.dataset.row;
        const field = event.target.dataset.field;
        let value = event.target.value;

        const items = [...this.paymentItems];
        const itemIndex = items.findIndex(item => item.sequenceNumber === rowId);

        if (itemIndex >= 0) {
            items[itemIndex] = {
                ...items[itemIndex],
                [field]: value,
                isManuallyModified: true
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
            if (field === 'paymentAmount' || field === 'commissionFee' || field === 'bankFee') {
                value = parseFloat(value) || 0;
            }

            items[itemIndex] = {
                ...items[itemIndex],
                [field]: value,
                isManuallyModified: true
            };

            // Recalculate totalFees when any fee field changes
            if (field === 'commissionFee' || field === 'bankFee') {
                const item = items[itemIndex];
                items[itemIndex].totalFees =
                    (item.commissionFee || 0) +
                    (item.bankFee || 0) +
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
     * Commission fee comes from draft input, bank/EPPS fees from config (loaded on init)
     * No dependency on previous rows - works for any insertion order
     */
    handleAddPaymentRow() {
        const items = [...this.paymentItems];

        const newSequenceNumber = items.length > 0
            ? Math.max(...items.map(i => parseInt(i.sequenceNumber, 10))) + 1
            : 1;

        // Commission fee from draft input (user-entered value)
        const commissionFee = this.currentDraft?.Commission_Fee__c || 0;

        // Bank and EPPS fees from config (loaded on init)
        // No dependency on previous rows - works for any insertion point
        const bankFee = this.feeConfig.bankFee;
        const eppsTransactionFee = this.feeConfig.eppsTransactionFee;
        const totalFees = commissionFee + bankFee + eppsTransactionFee;

        // Create new row - fees are derived from config + commission
        const newItem = {
            sequenceNumber: String(newSequenceNumber),
            paymentNumber: newSequenceNumber,
            paymentDate: null,
            originalPaymentDate: null,
            paymentAmount: null,
            commissionFee: commissionFee,
            bankFee: bankFee,
            eppsTransactionFee: eppsTransactionFee,
            eppsMonthEndFee: 0,
            payeeFee: 0,
            totalFees: totalFees,
            status: this.scheduledStatusValue || 'Scheduled',
            paymentMethod: null, // User must select explicitly
            isManuallyModified: true,
            isLocked: false, // New rows are never locked - only locks after save/reload
            dbStatus: null
        };

        items.push(newItem);
        this.paymentItems = items;
        this.currentDraft = {
            ...this.currentDraft,
            Is_Manually_Modified__c: true
        };
        this.isDirty = true;

        // Auto-enter edit mode for the new row
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
     * Delete a payment row from the schedule
     */
    handleDeletePaymentRow(event) {
        const rowId = event.currentTarget.dataset.row;

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

        const items = this.paymentItems.filter(item => item.sequenceNumber !== rowId);
        
        // Renumber sequence numbers
        items.forEach((item, index) => {
            item.sequenceNumber = String(index + 1);
            item.paymentNumber = index + 1;
        });

        this.paymentItems = items;
        this.currentDraft = {
            ...this.currentDraft,
            Is_Manually_Modified__c: true
        };
        this.isDirty = true;

        this.showToast('Info', 'Payment row deleted', 'info');
    }

    /**
     * Validate payment items before save
     * @returns {Object} { isValid: boolean, errorMessage: string }
     */
    validatePaymentItems() {
        // Dynamic validation removed per save & fetch architecture.
        return { isValid: true, errorMessage: null };
    }

    // Event handlers - Save
    async handleSaveDraft() {
        this.isLoading = true;
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
                Start_Date__c: seg.startDate || seg.Start_Date__c
            }));

            // Convert payment items to SObject format for recalculation
            // IMPORTANT: Include Id field for historical items so they are
            // recognized and skipped during save (not duplicated)
            let itemsForSave = this.paymentItems.map(item => ({
                // Include Id - critical for locked items to be recognized and preserved
                Id: item.id || item.Id || null,
                Settlement_Segment__c: item.segmentId || item.Settlement_Segment__c || null,
                Payment_Number__c: item.paymentNumber || item.Payment_Number__c,
                Payment_Date__c: item.paymentDate || item.Payment_Date__c,
                Original_Payment_Date__c: item.originalPaymentDate || item.Original_Payment_Date__c,
                Payment_Amount__c: item.paymentAmount || item.Payment_Amount__c,
                Commission_Fee__c: item.commissionFee || item.Commission_Fee__c,
                Bank_Fee__c: item.bankFee || item.Bank_Fee__c,
                EPPS_Transaction_Fee__c: item.eppsTransactionFee || item.EPPS_Transaction_Fee__c,
                EPPS_Month_End_Fee__c: item.eppsMonthEndFee || item.EPPS_Month_End_Fee__c,
                Payee_Fee__c: item.payeeFee || item.Payee_Fee__c || 0,
                Status__c: item.status || item.Status__c || this.scheduledStatusValue || 'Scheduled',
                Payment_Method__c: item.paymentMethod || item.Payment_Method__c || null,
                Has_Override__c: item.isManuallyModified || item.Has_Override__c || false
            }));

            // Recalculate balances before saving (handles manually added/edited rows)
            // Skip for new drafts with no items (Calculate generates fresh items)
            if (itemsForSave.length > 0) {
                const recalcResult = await recalculateBalances({
                    items: itemsForSave,
                    settlementOffer: this.effectiveSettlementAmount
                });

                if (recalcResult.success) {
                    // Use recalculated items for saving
                    itemsForSave = recalcResult.paymentItems;

                    // Update local state with recalculated values
                    this.updateLocalItemsFromRecalc(recalcResult.paymentItems);
                }
            }

            // Build draft fields to save
            const draftFieldsToSave = {
                Name: this.currentDraft?.Name,
                Balance__c: this.currentDraft?.Balance__c,
                Settlement_Offer_Amount__c: this.currentDraft?.Settlement_Offer_Amount__c,
                Revised_Settlement_Amount__c: this.currentDraft?.Revised_Settlement_Amount__c,
                Escrow_Start_Balance__c: this.currentDraft?.Escrow_Start_Balance__c,
                Commission_Fee__c: this.currentDraft?.Commission_Fee__c,
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
            // Also reload items to get their IDs
            this.paymentItems = this.normalizePaymentItems(wrapper.paymentItems || []);

            this.showToast('Success', 'Draft saved', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Event handlers - Update (creates a copy of the draft)
    async handleCloneDraft() {
        const cloneName = this.currentDraft.Name + ' (Updated)';

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
            await this.handleSaveDraft();
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
            startDate: seg.Start_Date__c || seg.startDate
        }));
    }

    /**
     * Normalize payment items from SObject field names to camelCase JS property names
     * Used after calculateDraftPlan to convert Apex response for display.
     * Preserves item IDs (important for locked items that should not be duplicated on save).
     * @param {Array} items - Array of payment items with SObject field names
     * @returns {Array} - Array of payment items with camelCase property names
     */
    normalizePaymentItems(items) {
        if (!items || items.length === 0) return [];

        return items.map((item, index) => {
            const status = item.Status__c || 'Scheduled';
            const dbStatus = item.Id ? status : null;
            const isLocked = dbStatus ? !this.isScheduledStatus(dbStatus) : false;

            return {
                // Preserve ID - critical for locked items that already exist in DB
                id: item.Id || null,
                sequenceNumber: String(index + 1),
                paymentNumber: item.Payment_Number__c || index + 1,
                paymentDate: item.Payment_Date__c,
                originalPaymentDate: item.Original_Payment_Date__c,
                paymentAmount: item.Payment_Amount__c,
                commissionFee: item.Commission_Fee__c,
                bankFee: item.Bank_Fee__c,
                eppsTransactionFee: item.EPPS_Transaction_Fee__c,
                eppsMonthEndFee: item.EPPS_Month_End_Fee__c || 0,
                payeeFee: item.Payee_Fee__c || 0,
                totalFees: (item.Commission_Fee__c || 0) + (item.Bank_Fee__c || 0) +
                           (item.EPPS_Transaction_Fee__c || 0),
                status: status,
                paymentMethod: item.Payment_Method__c || '',
                isManuallyModified: item.Has_Override__c || false,
                segmentId: item.Settlement_Segment__c,
                // Flag for locked items (non-Scheduled) - cannot be edited or deleted
                isLocked: isLocked,
                dbStatus: dbStatus
            };
        });
    }
    
    /**
     * Update local payment items with recalculated values from Apex
     * Maps SObject field names back to JS property names.
     * Preserves item IDs and isLocked flag from original items.
     */
    updateLocalItemsFromRecalc(recalcItems) {
        if (!recalcItems || recalcItems.length === 0) return;

        const updatedItems = recalcItems.map((item, index) => {
            const status = item.Status__c || 'Scheduled';
            // Preserve ID from recalc result or from original item
            const existingItem = this.paymentItems[index];
            const itemId = item.Id || existingItem?.id || null;
            const dbStatus = existingItem?.dbStatus || null;
            const isLocked = dbStatus ? !this.isScheduledStatus(dbStatus) : (existingItem?.isLocked || false);

            return {
                // Preserve ID - critical for locked items
                id: itemId,
                sequenceNumber: String(index + 1),
                paymentNumber: item.Payment_Number__c || index + 1,
                paymentDate: item.Payment_Date__c,
                originalPaymentDate: item.Original_Payment_Date__c,
                paymentAmount: item.Payment_Amount__c,
                commissionFee: item.Commission_Fee__c,
                bankFee: item.Bank_Fee__c,
                eppsTransactionFee: item.EPPS_Transaction_Fee__c,
                eppsMonthEndFee: item.EPPS_Month_End_Fee__c || 0,
                payeeFee: item.Payee_Fee__c || 0,
                totalFees: (item.Commission_Fee__c || 0) + (item.Bank_Fee__c || 0) +
                           (item.EPPS_Transaction_Fee__c || 0),
                status: status,
                paymentMethod: item.Payment_Method__c || existingItem?.paymentMethod || '',
                isManuallyModified: item.Has_Override__c || existingItem?.isManuallyModified || false,
                segmentId: item.Settlement_Segment__c,
                isLocked: isLocked,
                dbStatus: dbStatus
            };
        });

        this.paymentItems = updatedItems;
    }

    formatCurrency(value) {
        if (value === null || value === undefined) return '$0.00';
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