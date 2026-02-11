import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getOpportunityJourneys from '@salesforce/apex/OpportunityJourneyController.getOpportunityJourneys';

export default class OpportunityCasePanel extends NavigationMixin(LightningElement) {
    
    @api opportunityId;
    @track opportunity = {};
    @track isLoading = false;
    @track error;
    
    // Mock data for case sections until Apex methods can be deployed
    @track welcomeCases = [];
    @track legalCases = [];
    @track supportCases = [];
    @track negotiations = [];
    @track opportunitySummary = {
        totalDebt: 0,
        settledAmount: 0,
        activeNegotiations: 0
    };
    
    // Section expansion state
    @track isWelcomeSectionExpanded = true;
    @track isLegalSectionExpanded = false;
    @track isSupportSectionExpanded = false;
    @track isNegotiationSectionExpanded = false;
    
    wiredOpportunityResult;
    
    @wire(getOpportunityJourneys)
    wiredOpportunities(result) {
        this.wiredOpportunitiesResult = result;
        this.isLoading = true;
        
        if (result.data) {
            // Find our specific opportunity from the list
            this.opportunity = result.data.find(opp => opp.Id === this.opportunityId);
            if (this.opportunity) {
                this.processOpportunityData();
            }
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            console.error('Opportunities error:', result.error);
        }
        
        this.isLoading = false;
    }
    
    processOpportunityData() {
        if (!this.opportunity) return;
        
        // Create mock summary data based on opportunity
        this.opportunitySummary = {
            totalDebt: this.opportunity.Amount || 0,
            settledAmount: 0,
            activeNegotiations: 0,
            opportunityName: this.opportunity.Name || '',
            stage: this.opportunity.StageName || ''
        };
        
        // For demo purposes, create placeholder case data
        this.createMockCaseData();
    }
    
    createMockCaseData() {
        // Create placeholder welcome cases
        this.welcomeCases = [
            {
                id: 'welcome-001',
                caseNumber: 'W-000001',
                subject: 'Client Onboarding - ' + (this.opportunity.Name || 'Unknown'),
                welcomeTeamJourney: 'Documents Received',
                ownerName: 'Welcome Team',
                lastModifiedDisplay: 'Today',
                statusBadgeClass: 'slds-badge slds-theme_info'
            }
        ];
        
        // Create placeholder legal cases
        this.legalCases = [
            {
                id: 'legal-001',
                caseNumber: 'L-000001',
                subject: 'Legal Review - ' + (this.opportunity.Name || 'Unknown'),
                legalStatus: 'Under Review',
                legalRepresentative: 'Legal Team',
                activeNegotiations: 0,
                legalStatusBadgeClass: 'slds-badge slds-theme_warning'
            }
        ];
        
        // Create placeholder support cases
        this.supportCases = [
            {
                id: 'support-001',
                caseNumber: 'S-000001',
                subject: 'Client Support - ' + (this.opportunity.Name || 'Unknown'),
                requestType: 'General Support',
                ownerName: 'Support Team',
                status: 'Open',
                statusBadgeClass: 'slds-badge slds-theme_success'
            }
        ];
        
        // Create placeholder negotiations
        this.negotiations = [];
    }
    
    // Getters for template
    get hasWelcomeCasesData() {
        return this.welcomeCases && this.welcomeCases.length > 0;
    }
    
    get hasLegalCases() {
        return this.legalCases && this.legalCases.length > 0;
    }
    
    get hasSupportCases() {
        return this.supportCases && this.supportCases.length > 0;
    }
    
    get hasNegotiations() {
        return this.negotiations && this.negotiations.length > 0;
    }
    
    get welcomeCaseCount() {
        return this.welcomeCases ? this.welcomeCases.length : 0;
    }
    
    get legalCaseCount() {
        return this.legalCases ? this.legalCases.length : 0;
    }
    
    get supportCaseCount() {
        return this.supportCases ? this.supportCases.length : 0;
    }
    
    get activeNegotiationCount() {
        return this.negotiations ? this.negotiations.length : 0;
    }
    
    get totalCasesCount() {
        return this.welcomeCaseCount + this.legalCaseCount + this.supportCaseCount;
    }
    
    // Section toggle handlers
    handleWelcomeSectionToggle() {
        this.isWelcomeSectionExpanded = !this.isWelcomeSectionExpanded;
    }
    
    handleLegalSectionToggle() {
        this.isLegalSectionExpanded = !this.isLegalSectionExpanded;
    }
    
    handleSupportSectionToggle() {
        this.isSupportSectionExpanded = !this.isSupportSectionExpanded;
    }
    
    handleNegotiationSectionToggle() {
        this.isNegotiationSectionExpanded = !this.isNegotiationSectionExpanded;
    }
    
    // Action handlers
    handleCreateCase() {
        this.showToast('Info', 'Case creation functionality coming soon', 'info');
    }
    
    handleViewAllLegalCases() {
        this.showToast('Info', 'Legal cases view functionality coming soon', 'info');
    }
    
    handleCheckNegotiationStatus() {
        this.showToast('Info', 'Negotiation status check functionality coming soon', 'info');
    }
    
    refreshData() {
        this.isLoading = true;
        return refreshApex(this.wiredOpportunitiesResult)
            .then(() => {
                this.showToast('Success', 'Data refreshed successfully', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Error refreshing data: ' + error.body.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}