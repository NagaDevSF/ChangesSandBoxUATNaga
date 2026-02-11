import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAccountOpportunitiesWithCreditors from '@salesforce/apex/AccountOpportunityCreditorController.getAccountOpportunitiesWithCreditors';

export default class AccountOpportunityCreditorView extends NavigationMixin(LightningElement) {
    _recordId;
    @track expandedOpportunities = new Set();
    @track isLoading = true;
    @track error;
    @track data;

    @api 
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadData();
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadData();
        }
    }

    async loadData() {
        if (!this.recordId) return;
        
        this.isLoading = true;
        try {
            this.data = await getAccountOpportunitiesWithCreditors({ accountId: this.recordId });
            this.error = undefined;
            console.log('Loaded data:', this.data);
            console.log('Negotiations:', this.data?.creditorNegotiations);
        } catch (error) {
            this.error = error;
            this.data = undefined;
            console.error('Error loading data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasOpportunities() {
        return this.data && this.data.opportunities && this.data.opportunities.length > 0;
    }

    get formattedTotalAmount() {
        return this.data?.totalAmount ? this.formatCurrency(this.data.totalAmount) : '$0.00';
    }

    get formattedTotalEstimatedDebt() {
        return this.data?.totalEstimatedDebt ? this.formatCurrency(this.data.totalEstimatedDebt) : '$0.00';
    }

    get opportunitiesWithFormatting() {
        if (!this.data?.opportunities) return [];
        
        return this.data.opportunities.map(opp => {
            const isExpanded = this.expandedOpportunities.has(opp.Id);
            
            return {
                ...opp,
                isExpanded,
                expandIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                formattedAmount: opp.Amount ? this.formatCurrency(opp.Amount) : '$0.00',
                formattedEstimatedDebt: opp.Estimated_Total_Debt__c ? this.formatCurrency(opp.Estimated_Total_Debt__c) : '$0.00',
                formattedWeeklyPayment: opp.Est_weekly_payment__c ? this.formatCurrency(opp.Est_weekly_payment__c) : '$0.00',
                formattedCurrentPayment: opp.Estimated_Current_Payment__c ? this.formatCurrency(opp.Estimated_Current_Payment__c) : '$0.00',
                formattedDesiredPayment: opp.Desired_Weekly_Payment__c ? this.formatCurrency(opp.Desired_Weekly_Payment__c) : '$0.00',
                paymentFrequency: opp.Payment_Frequency__c || 'Not Set',
                quizQuote: opp.Quiz_Quote__c || 'Not Set',
                creditorCount: opp.CreditorOpportunitys__r ? opp.CreditorOpportunitys__r.length : 0,
                formattedCreditors: this.formatCreditors(opp.CreditorOpportunitys__r)
            };
        });
    }

    formatCreditors(creditors) {
        if (!creditors || creditors.length === 0) return [];
        
        return creditors.map(creditor => {
            // Get related negotiations for this creditor
            const relatedNegotiations = this.data?.creditorNegotiations?.[creditor.Id] || [];
            const formattedNegotiations = relatedNegotiations.map(neg => this.formatNegotiation(neg));
            
            return {
                ...creditor,
                formattedAmount: creditor.Amount__c ? this.formatCurrency(creditor.Amount__c) : '$0.00',
                formattedWeeklyPayment: creditor.Weekly_Payment__c ? this.formatCurrency(creditor.Weekly_Payment__c) : '$0.00',
                formattedCurrentPayment: creditor.Estimated_Current_Weekly_Payment__c ? this.formatCurrency(creditor.Estimated_Current_Weekly_Payment__c) : '$0.00',
                creditorName: creditor.CreditorAccount__r?.Name || creditor.Creditor__c || 'Unknown Creditor',
                frequency: creditor.Frequency__c || 'Not Set',
                creditorNumber: creditor.Number__c || 'N/A',
                // Related negotiations
                negotiations: formattedNegotiations,
                hasNegotiations: formattedNegotiations.length > 0,
                negotiationCount: formattedNegotiations.length
            };
        });
    }

    formatNegotiation(negotiation) {
        return {
            ...negotiation,
            formattedPaymentDueDate: negotiation.Payment_Due_Date__c ? this.formatDateTime(negotiation.Payment_Due_Date__c) : 'Not Set',
            formattedNegotiationDate: negotiation.Negotiation_Date__c ? this.formatDateTime(negotiation.Negotiation_Date__c) : 'Not Set',
            formattedNextFollowUp: negotiation.Next_Follow_Up_Date__c ? this.formatDate(negotiation.Next_Follow_Up_Date__c) : 'Not Set',
            formattedPaymentDate: negotiation.Payment_Date__c ? this.formatDate(negotiation.Payment_Date__c) : 'Not Set',
            formattedSettlementOffer: negotiation.Settlement_Offer_Amount__c ? this.formatCurrency(negotiation.Settlement_Offer_Amount__c) : '$0.00',
            formattedCounterOffer: negotiation.Counter_Offer_Amount__c ? this.formatCurrency(negotiation.Counter_Offer_Amount__c) : '$0.00',
            formattedFinalAgreed: negotiation.Final_Agreed_Amount__c ? this.formatCurrency(negotiation.Final_Agreed_Amount__c) : '$0.00',
            formattedActualPayment: negotiation.Actual_Payment_Amount__c ? this.formatCurrency(negotiation.Actual_Payment_Amount__c) : '$0.00',
            negotiationStatus: negotiation.Negotiation_Status__c || 'Not Started',
            negotiationType: negotiation.Negotiation_Type__c || 'Not Set',
            outcome: negotiation.Outcome__c || 'Pending',
            numberOfPayments: negotiation.Number_of_Payments__c || 0,
            creditorRep: negotiation.Creditor_Representative__c || 'Not Assigned',
            notes: negotiation.Negotiation_Notes__c || 'No notes available'
        };
    }

    formatCurrency(amount) {
        if (amount == null || amount == undefined) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(amount);
    }

    formatDateTime(dateTimeValue) {
        if (!dateTimeValue) return 'Not Set';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'numeric',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        }).format(new Date(dateTimeValue));
    }

    formatDate(dateValue) {
        if (!dateValue) return 'Not Set';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'numeric',
            day: 'numeric'
        }).format(new Date(dateValue));
    }

    handleToggleExpand(event) {
        const opportunityId = event.currentTarget.dataset.id;
        
        if (this.expandedOpportunities.has(opportunityId)) {
            this.expandedOpportunities.delete(opportunityId);
        } else {
            this.expandedOpportunities.add(opportunityId);
        }
        
        // Force reactivity
        this.expandedOpportunities = new Set(this.expandedOpportunities);
    }

    handleNavigateToRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const objectType = event.currentTarget.dataset.type;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectType,
                actionName: 'view'
            }
        });
    }

    async handleRefresh() {
        await this.loadData();
    }

    handleExpandAll() {
        if (this.data?.opportunities) {
            this.expandedOpportunities = new Set(this.data.opportunities.map(opp => opp.Id));
        }
    }

    handleCollapseAll() {
        this.expandedOpportunities = new Set();
    }
}