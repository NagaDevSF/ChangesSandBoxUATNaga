import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getNegotiations from '@salesforce/apex/NegotiationController.getNegotiations';
import createNegotiation from '@salesforce/apex/NegotiationController.createNegotiation';
import recordPayment from '@salesforce/apex/NegotiationController.recordPayment';
import updateNegotiation from '@salesforce/apex/NegotiationController.updateNegotiation';

const NEGOTIATION_COLUMNS = [
    { 
        label: 'Active', 
        fieldName: 'activeDisplay', 
        type: 'text',
        cellAttributes: { 
            class: { fieldName: 'activeClass' }
        },
        fixedWidth: 120
    },
    { 
        label: 'Negotiation #', 
        fieldName: 'Name', 
        type: 'text',
        sortable: true
    },
    { 
        label: 'Created Date', 
        fieldName: 'CreatedDate', 
        type: 'date',
        sortable: true,
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { 
        label: 'Settlement Offer', 
        fieldName: 'Settlement_Offer_Amount__c', 
        type: 'currency',
        cellAttributes: { alignment: 'left' }
    },
    { 
        label: 'Counter Offer', 
        fieldName: 'Counter_Offer_Amount__c', 
        type: 'currency',
        cellAttributes: { alignment: 'left' }
    },
    { 
        label: 'Final Agreed', 
        fieldName: 'Final_Agreed_Amount__c', 
        type: 'currency',
        cellAttributes: { alignment: 'left' }
    },
    { 
        label: 'Paid Amount', 
        fieldName: 'Actual_Payment_Amount__c', 
        type: 'currency',
        cellAttributes: { alignment: 'left' }
    },
    { 
        label: 'Status', 
        fieldName: 'Negotiation_Status__c', 
        type: 'text',
        cellAttributes: { 
            class: { fieldName: 'statusClass' }
        }
    },
    { 
        label: 'Actions', 
        type: 'action', 
        typeAttributes: { 
            rowActions: [
                { label: 'Set Active', name: 'set_active' },
                { label: 'Record Payment', name: 'record_payment' },
                { label: 'Edit', name: 'edit' },
                { label: 'View Details', name: 'view' }
            ] 
        } 
    }
];

export default class ComprehensiveNegotiationManager extends LightningElement {
    @api recordId;
    @track negotiations = [];
    
    @track showCreateForm = false;
    @track showEditForm = false;
    @track showPaymentModal = false;
    @track showViewModal = false;
    @track selectedNegotiationId = null;
    @track selectedNegotiation = {};
    @track isLoading = false;
    
    columns = NEGOTIATION_COLUMNS;
    wiredNegotiationsResult;

    @track negotiationForm = this.getDefaultFormData();

    @track paymentForm = {
        paymentAmount: 0,
        paymentDate: new Date().toISOString().split('T')[0]
    };


    @wire(getNegotiations, { caseId: '$recordId' })
    wiredNegotiations(result) {
        this.wiredNegotiationsResult = result;
        if (result.data) {
            this.negotiations = result.data.map(neg => ({
                ...neg,
                statusClass: this.getStatusClass(neg.Negotiation_Status__c),
                activeDisplay: neg.Active__c ? '✅ Active' : '○ Inactive',
                activeClass: neg.Active__c ? 'active-indicator active-true' : 'active-indicator active-false'
            }));
        } else if (result.error) {
            this.showToast('Error', 'Failed to load negotiations', 'error');
            console.error('Error loading negotiations:', result.error);
        }
    }

    get negotiationTypeOptions() {
        return [
            { label: 'Type A', value: 'Type A' },
            { label: 'Type B', value: 'Type B' },
            { label: 'Type C', value: 'Type C' }
        ];
    }

    get statusOptions() {
        return [
            { label: 'POA Out', value: 'POA Out' },
            { label: 'POA On File', value: 'POA On File' },
            { label: 'Contact Attempted', value: 'Contact Attempted' },
            { label: 'Negotiation In Process', value: 'Negotiation In Process' },
            { label: 'In Transit', value: 'In Transit' },
            { label: 'Offer Made', value: 'Offer Made' },
            { label: 'Waiting for Letter', value: 'Waiting for Letter' },
            { label: 'Insufficient Funds', value: 'Insufficient Funds' },
            { label: 'Settled', value: 'Settled' },
            { label: 'Lender Drafting The Client\'s Account', value: 'Lender Drafting The Client\'s Account' },
            { label: 'Negotiations Paused', value: 'Negotiations Paused' }
        ];
    }

    get outcomeOptions() {
        return [];
    }



    get hasNegotiations() {
        return this.negotiations && this.negotiations.length > 0;
    }

    get formTitle() {
        return this.showEditForm ? 'Edit Negotiation' : 'New Negotiation';
    }

    get saveButtonLabel() {
        return this.showEditForm ? 'Update Negotiation' : 'Save Negotiation';
    }

    handleNewNegotiation() {
        this.negotiationForm = this.getDefaultFormData();
        this.showCreateForm = true;
        this.showEditForm = false;
    }

    handleCancelForm() {
        this.showCreateForm = false;
        this.showEditForm = false;
        this.selectedNegotiationId = null;
        this.selectedNegotiation = {};
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.negotiationForm[field] = event.target.value;
        
        this.handleStatusLogic();
    }

    handleSaveNegotiation() {
        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;

        const negotiationData = {
            caseId: this.recordId,
            settlementAmount: parseFloat(this.negotiationForm.settlementOffer) || 0,
            counterOffer: parseFloat(this.negotiationForm.counterOffer) || 0,
            finalAmount: parseFloat(this.negotiationForm.finalAmount) || 0,
            paidAmount: parseFloat(this.negotiationForm.paidAmount) || 0,
            status: this.negotiationForm.status,
            active: this.negotiationForm.active
        };

        if (this.showEditForm) {
            negotiationData.id = this.selectedNegotiationId;
        }

        const savePromise = this.showEditForm ? 
            updateNegotiation({ negotiationData: negotiationData }) :
            createNegotiation({ negotiationData: negotiationData });

        savePromise
            .then((result) => {
                const message = this.showEditForm ? 
                    'Negotiation updated successfully' : 
                    'Negotiation created successfully';
                this.showToast('Success', message, 'success');
                this.handleCancelForm();
                return refreshApex(this.wiredNegotiationsResult);
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                console.error('Error saving negotiation:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        switch (actionName) {
            case 'set_active':
                this.setActiveNegotiation(row.Id);
                break;
            case 'record_payment':
                this.selectedNegotiationId = row.Id;
                this.paymentForm.paymentAmount = row.Final_Agreed_Amount__c || 0;
                this.showPaymentModal = true;
                break;
            case 'edit':
                this.editNegotiation(row);
                break;
            case 'view':
                this.viewNegotiation(row.Id);
                break;
        }
    }

    handlePaymentInputChange(event) {
        const field = event.target.dataset.field;
        this.paymentForm[field] = event.target.value;
    }

    handleSavePayment() {
        if (!this.paymentForm.paymentAmount || this.paymentForm.paymentAmount <= 0) {
            this.showToast('Error', 'Please enter a valid payment amount', 'error');
            return;
        }

        this.isLoading = true;

        recordPayment({
            negotiationId: this.selectedNegotiationId,
            paymentAmount: parseFloat(this.paymentForm.paymentAmount),
            paymentDate: this.paymentForm.paymentDate
        })
            .then(() => {
                this.showToast('Success', 'Payment recorded successfully', 'success');
                this.handleCancelPayment();
                return refreshApex(this.wiredNegotiationsResult);
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                console.error('Error recording payment:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancelPayment() {
        this.showPaymentModal = false;
        this.resetPaymentForm();
    }

    getDefaultFormData() {
        return {
            settlementOffer: 0,
            counterOffer: 0,
            finalAmount: 0,
            paidAmount: 0,
            status: 'POA Out',
            active: true
        };
    }

    validateForm() {
        if (!this.negotiationForm.status) {
            this.showToast('Error', 'Status is required', 'error');
            return false;
        }
        return true;
    }

    handleStatusLogic() {
        // Simplified status logic for production fields only
    }

    editNegotiation(row) {
        this.selectedNegotiationId = row.Id;
        this.selectedNegotiation = row;
        
        this.negotiationForm = {
            settlementOffer: row.Settlement_Offer_Amount__c || 0,
            counterOffer: row.Counter_Offer_Amount__c || 0,
            finalAmount: row.Final_Agreed_Amount__c || 0,
            paidAmount: row.Actual_Payment_Amount__c || 0,
            status: row.Negotiation_Status__c || 'POA Out',
            active: row.Active__c || false
        };
        
        this.showEditForm = true;
        this.showCreateForm = true;
    }

    viewNegotiation(negotiationId) {
        // Find the negotiation record from the negotiations array
        const negotiation = this.negotiations.find(neg => neg.Id === negotiationId);
        if (negotiation) {
            this.selectedNegotiation = negotiation;
            this.showViewModal = true;
        }
    }

    handleCancelView() {
        this.showViewModal = false;
        this.selectedNegotiation = {};
    }

    get formattedSelectedNegotiation() {
        if (!this.selectedNegotiation.Id) return {};
        
        return {
            ...this.selectedNegotiation,
            formattedCreatedDate: this.formatDateTime(this.selectedNegotiation.CreatedDate),
            formattedLastModifiedDate: this.formatDateTime(this.selectedNegotiation.LastModifiedDate),
            formattedSettlementAmount: this.formatCurrency(this.selectedNegotiation.Settlement_Offer_Amount__c),
            formattedCounterAmount: this.formatCurrency(this.selectedNegotiation.Counter_Offer_Amount__c),
            formattedFinalAmount: this.formatCurrency(this.selectedNegotiation.Final_Agreed_Amount__c),
            formattedPaidAmount: this.formatCurrency(this.selectedNegotiation.Actual_Payment_Amount__c),
            activeStatus: this.selectedNegotiation.Active__c ? 'Yes' : 'No'
        };
    }

    formatDateTime(dateTimeString) {
        if (!dateTimeString) return 'N/A';
        return new Date(dateTimeString).toLocaleString();
    }

    formatCurrency(amount) {
        if (!amount && amount !== 0) return 'N/A';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(amount);
    }

    setActiveNegotiation(negotiationId) {
        this.isLoading = true;
        
        const negotiationData = {
            id: negotiationId,
            active: true
        };
        
        updateNegotiation({ negotiationData: negotiationData })
            .then(() => {
                this.showToast('Success', 'Negotiation set as active successfully', 'success');
                return refreshApex(this.wiredNegotiationsResult);
            })
            .catch(error => {
                this.showToast('Error', 'Failed to set negotiation as active: ' + error.body.message, 'error');
                console.error('Error setting active negotiation:', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    resetPaymentForm() {
        this.paymentForm = {
            paymentAmount: 0,
            paymentDate: new Date().toISOString().split('T')[0]
        };
        this.selectedNegotiationId = null;
    }

    loadRelatedInfo() {
        
    }

    getStatusClass(status) {
        switch (status) {
            case 'Settled':
                return 'slds-text-color_success slds-text-title_caps';
            case 'Negotiations Paused':
            case 'Insufficient Funds':
                return 'slds-text-color_error slds-text-title_caps';
            case 'Negotiation In Process':
            case 'Offer Made':
            case 'In Transit':
                return 'slds-text-color_warning slds-text-title_caps';
            case 'POA Out':
            case 'POA On File':
            case 'Contact Attempted':
            case 'Waiting for Letter':
            case 'Lender Drafting The Client\'s Account':
                return 'slds-text-color_default slds-text-title_caps';
            default:
                return 'slds-text-color_weak';
        }
    }

    getStatusIcon(status) {
        switch (status) {
            case 'Settled':
                return 'utility:success';
            case 'Negotiations Paused':
            case 'Insufficient Funds':
                return 'utility:error';
            case 'Negotiation In Process':
            case 'Offer Made':
                return 'utility:clock';
            case 'POA Out':
            case 'POA On File':
                return 'utility:file';
            case 'Contact Attempted':
                return 'utility:phone';
            case 'In Transit':
                return 'utility:transport';
            case 'Waiting for Letter':
                return 'utility:email';
            case 'Lender Drafting The Client\'s Account':
                return 'utility:money';
            default:
                return 'utility:info';
        }
    }

    getOutcomeClass(outcome) {
        switch (outcome) {
            case 'Settlement Reached':
                return 'slds-text-color_success slds-text-title_caps';
            case 'Rejected':
                return 'slds-text-color_error';
            case 'Counter Offer':
                return 'slds-text-color_warning';
            case 'No Response':
                return 'slds-text-color_weak';
            default:
                return '';
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissable'
        });
        this.dispatchEvent(event);
    }
}