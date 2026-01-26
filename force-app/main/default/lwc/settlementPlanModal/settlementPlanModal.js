/**
 * @description Main modal component for Settlement Plan Builder.
 *              Extends LightningModal and manages draft payment plans.
 * @author Settlement Calculator Team
 * @date January 2026
 */
import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex methods
import initializeModal from '@salesforce/apex/SettlementDraftController.initializeModal';
import getDraftWithDetails from '@salesforce/apex/SettlementDraftController.getDraftWithDetails';
import createDraft from '@salesforce/apex/SettlementDraftController.createDraft';
import saveDraft from '@salesforce/apex/SettlementDraftController.saveDraft';
import cloneDraft from '@salesforce/apex/SettlementDraftController.cloneDraft';
import deleteDraft from '@salesforce/apex/SettlementDraftController.deleteDraft';
import calculateDraftPlan from '@salesforce/apex/SettlementDraftController.calculateDraftPlan';
import recalculateBalances from '@salesforce/apex/SettlementDraftController.recalculateBalances';
import activateDraft from '@salesforce/apex/SettlementDraftController.activateDraft';

export default class SettlementPlanModal extends LightningModal {
    // Public API - received from quick action via open() call
    @api creditorOpportunityId;

    // State management - single state object pattern
    @track state = {
        // Data
        creditorOpportunity: null,
        drafts: [],
        currentDraftId: null,
        currentDraft: null,
        segments: [],
        paymentItems: [],

        // UI state
        isLoading: false,
        isDirty: false,
        showNewDraftInput: false,
        newDraftName: '',
        error: null
    };

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

    // Computed properties
    get isReadOnly() {
        return this.state.currentDraft?.Status__c === 'Active' ||
               this.state.currentDraft?.Status__c === 'Applied';
    }

    get hasDrafts() {
        return this.state.drafts && this.state.drafts.length > 0;
    }

    get hasPaymentItems() {
        return this.state.paymentItems && this.state.paymentItems.length > 0;
    }

    get hasSegments() {
        return this.state.segments && this.state.segments.length > 0;
    }

    get totalScheduled() {
        if (!this.state.paymentItems || this.state.paymentItems.length === 0) {
            return 0;
        }
        return this.state.paymentItems.reduce((sum, item) => sum + (item.paymentAmount || 0), 0);
    }

    get settlementOffer() {
        return this.state.currentDraft?.Settlement_Offer__c || 0;
    }

    get fundingDifference() {
        return (this.totalScheduled - this.settlementOffer).toFixed(2);
    }

    get isBalanced() {
        return Math.abs(this.fundingDifference) <= 0.10;
    }

    get summaryClass() {
        if (this.isBalanced) return 'slds-text-color_success';
        if (this.fundingDifference < 0) return 'slds-text-color_error';
        return 'slds-text-color_warning';
    }

    get balanceStatusText() {
        if (this.isBalanced) return 'Balanced';
        if (this.fundingDifference < 0) return 'Underfunded';
        return 'Overfunded';
    }

    get canSave() {
        return !this.isReadOnly && this.state.isDirty;
    }

    get canActivate() {
        return !this.isReadOnly &&
               this.hasPaymentItems &&
               this.state.currentDraft?.Status__c === 'Draft';
    }

    get canDelete() {
        return this.state.currentDraft?.Status__c === 'Draft' ||
               this.state.currentDraft?.Status__c === 'Archived';
    }

    // Negated getters for template use (LWC templates don't support ! or === operators)
    get hasNoCurrentDraft() {
        return this.state.currentDraft === null || this.state.currentDraft === undefined;
    }

    get cannotDelete() {
        return !this.canDelete;
    }

    get cannotActivate() {
        return !this.canActivate;
    }

    get draftTabs() {
        return this.state.drafts.map(draft => ({
            id: draft.Id,
            label: draft.Name,
            isActive: draft.Status__c === 'Active',
            isApplied: draft.Status__c === 'Applied',
            isArchived: draft.Status__c === 'Archived',
            statusIcon: draft.Status__c === 'Active' ? 'utility:check' : null,
            class: draft.Id === this.state.currentDraftId ? 'slds-is-active' : ''
        }));
    }

    get statusBadgeClass() {
        const status = this.state.currentDraft?.Status__c;
        switch (status) {
            case 'Active': return 'slds-badge slds-badge_success';
            case 'Applied': return 'slds-badge slds-badge_inverse';
            case 'Archived': return 'slds-badge';
            default: return 'slds-badge slds-badge_lightest';
        }
    }

    get formattedPaymentItems() {
        if (!this.state.paymentItems) return [];

        return this.state.paymentItems.map(item => ({
            ...item,
            formattedDate: item.paymentDate,
            formattedAmount: this.formatCurrency(item.paymentAmount),
            formattedFees: this.formatCurrency(item.totalFees),
            formattedBalance: this.formatCurrency(item.runningBalance),
            formattedEscrow: this.formatCurrency(item.escrowBalance),
            rowClass: item.isEscrowShortage ? 'slds-hint-parent escrow-shortage-row' :
                      item.isManuallyModified ? 'slds-hint-parent modified-row' : 'slds-hint-parent',
            escrowClass: item.isEscrowShortage ? 'slds-text-color_error' : ''
        }));
    }

    // Lifecycle
    async connectedCallback() {
        await this.loadInitialData();
    }

    // Data loading methods
    async loadInitialData() {
        this.state.isLoading = true;
        this.state.error = null;

        try {
            const result = await initializeModal({
                creditorOpportunityId: this.creditorOpportunityId
            });

            this.state.creditorOpportunity = result.creditorOpportunity;
            this.state.drafts = result.drafts || [];

            if (result.defaultDraftDetails) {
                this.loadDraftDetails(result.defaultDraftDetails);
            } else if (this.state.drafts.length > 0) {
                await this.selectDraft(this.state.drafts[0].Id);
            }
            // If no drafts exist, user can create new one via tab

        } catch (error) {
            this.state.error = error;
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    loadDraftDetails(wrapper) {
        this.state.currentDraftId = wrapper.draft?.Id;
        this.state.currentDraft = wrapper.draft;
        this.state.segments = wrapper.segments || [];
        this.state.paymentItems = wrapper.paymentItems || [];
        this.state.isDirty = false;
    }

    async selectDraft(draftId) {
        if (this.state.isDirty) {
            const confirmSwitch = await this.confirmAction(
                'Unsaved Changes',
                'You have unsaved changes. Switch drafts anyway?'
            );
            if (!confirmSwitch) return;
        }

        this.state.isLoading = true;
        try {
            const wrapper = await getDraftWithDetails({ draftId });
            this.loadDraftDetails(wrapper);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Draft management
    handleDraftTabClick(event) {
        const draftId = event.currentTarget.dataset.id;
        if (draftId !== this.state.currentDraftId) {
            this.selectDraft(draftId);
        }
    }

    handleNewDraftClick() {
        this.state.showNewDraftInput = true;
        this.state.newDraftName = 'Draft ' + new Date().toLocaleDateString();
    }

    handleNewDraftNameChange(event) {
        this.state.newDraftName = event.target.value;
    }

    async handleCreateDraft() {
        if (!this.state.newDraftName) {
            this.showToast('Error', 'Please enter a draft name', 'error');
            return;
        }

        this.state.isLoading = true;
        try {
            const newDraft = await createDraft({
                creditorOpportunityId: this.creditorOpportunityId,
                draftName: this.state.newDraftName
            });

            // Refresh drafts list
            this.state.drafts = [...this.state.drafts, newDraft];
            this.state.showNewDraftInput = false;
            this.state.newDraftName = '';

            // Select the new draft
            await this.selectDraft(newDraft.Id);

            this.showToast('Success', 'Draft created', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    handleCancelNewDraft() {
        this.state.showNewDraftInput = false;
        this.state.newDraftName = '';
    }

    // Event handlers - Input changes
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'number' ? parseFloat(event.target.value) : event.target.value;

        this.state.currentDraft = {
            ...this.state.currentDraft,
            [field]: value
        };
        this.state.isDirty = true;
    }

    handleNameChange(event) {
        this.state.currentDraft = {
            ...this.state.currentDraft,
            Name: event.target.value
        };
        this.state.isDirty = true;
    }

    // Event handlers - Segments
    handleSegmentChange(event) {
        this.state.segments = event.detail.segments;
        this.state.isDirty = true;
    }

    // Event handlers - Calculate
    async handleCalculate() {
        if (this.state.segments.length === 0) {
            this.showToast('Error', 'Please add at least one segment', 'error');
            return;
        }

        this.state.isLoading = true;
        try {
            const result = await calculateDraftPlan({
                draftId: this.state.currentDraftId,
                segmentsJson: JSON.stringify(this.state.segments),
                balance: this.state.currentDraft?.Balance__c,
                settlementOffer: this.state.currentDraft?.Settlement_Offer__c,
                escrowStart: this.state.currentDraft?.Escrow_Start_Balance__c
            });

            if (result.success) {
                this.state.paymentItems = result.paymentItems;
                this.state.isDirty = true;
                this.showToast('Success', `Generated ${result.numberOfPayments} payments`, 'success');
            } else {
                this.showToast('Calculation Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Payment table edits
    async handleCellEdit(event) {
        const rowId = event.target.dataset.row;
        const field = event.target.dataset.field;
        let value = event.target.value;

        // Find and update the item
        const items = [...this.state.paymentItems];
        const itemIndex = items.findIndex(item => item.sequenceNumber === rowId);

        if (itemIndex >= 0) {
            if (field === 'paymentAmount') {
                value = parseFloat(value) || 0;
            }

            items[itemIndex] = {
                ...items[itemIndex],
                [field]: value,
                isManuallyModified: true
            };

            this.state.paymentItems = items;
            this.state.currentDraft = {
                ...this.state.currentDraft,
                Is_Manually_Modified__c: true
            };
            this.state.isDirty = true;

            // Recalculate balances
            await this.recalculateBalances();
        }
    }

    async recalculateBalances() {
        try {
            const result = await recalculateBalances({
                paymentItemsJson: JSON.stringify(this.state.paymentItems),
                settlementOffer: this.state.currentDraft?.Settlement_Offer__c,
                escrowStart: this.state.currentDraft?.Escrow_Start_Balance__c
            });

            if (result.success) {
                this.state.paymentItems = result.paymentItems;
            }
        } catch (error) {
            console.error('Recalculation error:', error);
        }
    }

    // Event handlers - Save
    async handleSaveDraft() {
        this.state.isLoading = true;
        try {
            const draftToSave = {
                Id: this.state.currentDraftId,
                Name: this.state.currentDraft.Name,
                Creditors_List__c: this.creditorOpportunityId,
                Balance__c: this.state.currentDraft.Balance__c,
                Settlement_Offer__c: this.state.currentDraft.Settlement_Offer__c,
                Escrow_Start_Balance__c: this.state.currentDraft.Escrow_Start_Balance__c,
                Segments_JSON__c: JSON.stringify(this.state.segments),
                Payment_Items_JSON__c: JSON.stringify(this.state.paymentItems),
                Is_Manually_Modified__c: this.state.currentDraft.Is_Manually_Modified__c || false
            };

            const savedDraft = await saveDraft({
                draftJson: JSON.stringify(draftToSave)
            });

            this.state.currentDraft = savedDraft;
            this.state.isDirty = false;

            // Update draft in list
            const drafts = [...this.state.drafts];
            const index = drafts.findIndex(d => d.Id === savedDraft.Id);
            if (index >= 0) {
                drafts[index] = savedDraft;
                this.state.drafts = drafts;
            }

            this.showToast('Success', 'Draft saved', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Clone
    async handleCloneDraft() {
        const cloneName = this.state.currentDraft.Name + ' (Copy)';

        this.state.isLoading = true;
        try {
            const clonedDraft = await cloneDraft({
                sourceDraftId: this.state.currentDraftId,
                newName: cloneName
            });

            // Add to drafts list
            this.state.drafts = [...this.state.drafts, clonedDraft];

            // Select the cloned draft
            await this.selectDraft(clonedDraft.Id);

            this.showToast('Success', 'Draft cloned', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Delete
    async handleDeleteDraft() {
        const confirmDelete = await this.confirmAction(
            'Delete Draft',
            'Are you sure you want to delete this draft? This cannot be undone.'
        );
        if (!confirmDelete) return;

        this.state.isLoading = true;
        try {
            await deleteDraft({ draftId: this.state.currentDraftId });

            // Remove from drafts list
            this.state.drafts = this.state.drafts.filter(d => d.Id !== this.state.currentDraftId);

            // Select another draft or clear
            if (this.state.drafts.length > 0) {
                await this.selectDraft(this.state.drafts[0].Id);
            } else {
                this.state.currentDraftId = null;
                this.state.currentDraft = null;
                this.state.segments = [];
                this.state.paymentItems = [];
            }

            this.showToast('Success', 'Draft deleted', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Activate
    async handleActivate() {
        // Warn if not balanced
        if (!this.isBalanced) {
            const proceed = await this.confirmAction(
                'Plan Not Balanced',
                `The plan is ${this.balanceStatusText.toLowerCase()} by $${Math.abs(this.fundingDifference).toFixed(2)}. Activate anyway?`
            );
            if (!proceed) return;
        }

        // Confirm activation
        const confirmActivate = await this.confirmAction(
            'Activate Plan',
            'This will create real payment records and replace any existing plan. Continue?'
        );
        if (!confirmActivate) return;

        // Save first if dirty
        if (this.state.isDirty) {
            await this.handleSaveDraft();
        }

        this.state.isLoading = true;
        try {
            const result = await activateDraft({ draftId: this.state.currentDraftId });

            if (result.success) {
                this.showToast(
                    'Success',
                    `Created ${result.paymentItemsCreated} payment items`,
                    'success'
                );
                this.close('activated');
            } else {
                this.showToast('Activation Error', result.errorMessage, 'error');
            }
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.state.isLoading = false;
        }
    }

    // Event handlers - Cancel
    async handleCancel() {
        if (this.state.isDirty) {
            const confirmClose = await this.confirmAction(
                'Unsaved Changes',
                'You have unsaved changes. Close anyway?'
            );
            if (!confirmClose) return;
        }
        this.close('cancelled');
    }

    // Utility methods
    formatCurrency(value) {
        if (value === null || value === undefined) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }

    async confirmAction(title, message) {
        // Simple confirm for now - could be replaced with LightningConfirm
        return confirm(message);
    }
}