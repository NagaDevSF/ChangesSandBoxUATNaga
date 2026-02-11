import { LightningElement, track, wire } from 'lwc';
import getOpportunityJourneys from '@salesforce/apex/OpportunityJourneyController.getOpportunityJourneys';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class ClientsContractSignedJourney extends NavigationMixin(LightningElement) {
    @track opportunities = [];
    @track filteredOpportunities = [];
    @track searchTerm = '';
    @track currentFilter = 'all';
    @track isLoading = true;
    
    @track expandedOpportunityId = null;
    @track showWelcomePanel = false;
    
    @track currentPage = 1;
    @track pageSize = 25;
    @track totalRecords = 0;

    @track totalOpportunities = 0;
    @track contractSignedOpportunities = 0;
    @track enrolledOpportunities = 0;
    @track nsfOpportunities = 0;
    @track totalDebt = 0;
    
    @track filteredTotalOpportunities = 0;
    @track filteredContractSignedOpportunities = 0;
    @track filteredEnrolledOpportunities = 0;
    @track filteredNsfOpportunities = 0;
    @track filteredTotalDebt = 0;

    wiredOpportunitiesResult;
    allFilteredOpportunities = [];

    @wire(getOpportunityJourneys)
    wiredOpportunities(result) {
        this.wiredOpportunitiesResult = result;
        if (result.data) {
            this.opportunities = result.data.map(opp => this.processOpportunityData(opp));
            this.calculateStats();
            this.loadSettlementData();
            this.applyCurrentFilter();
            this.isLoading = false;
            this.triggerProgressAnimations();
        } else if (result.error) {
            const errorMessage = result.error.body?.message || result.error.message || 'Unknown error occurred';
            this.showToast('Error', 'Error loading opportunity data: ' + errorMessage, 'error');
            this.isLoading = false;
        }
    }
    
    async loadSettlementData() {
        // For now, use placeholder settlement data until the Apex methods can be deployed
        // TODO: Replace with actual getOpportunitySummary call once test coverage is achieved
        this.opportunities = this.opportunities.map(opp => {
            return {
                ...opp,
                settledAmount: 0, // Placeholder value
                settledDisplay: this.formatCurrency(0)
            };
        });
        
        // Re-apply current filter to update the display
        this.applyCurrentFilter();
    }

    processOpportunityData(opportunity) {
        if (!opportunity) return {};
        
        const enrollmentDate = opportunity.First_Draft_Date__c ? new Date(opportunity.First_Draft_Date__c) : new Date();
        const today = new Date();
        const daysDiff = Math.floor((today - enrollmentDate) / (1000 * 60 * 60 * 24));
        
        return {
            ...opportunity,
            
            progressValue: this.getProgressValue(opportunity.Progress__c),
            progressDisplay: this.getProgressValue(opportunity.Progress__c),
            progressStyle: `--progress-width: ${this.getProgressValue(opportunity.Progress__c)}%; width: 0%`,
            progressClass: 'progress-bar-fill animate-progress',
            
            statusDisplay: (opportunity.Status_c__c || opportunity.StageName) ? 
                          (opportunity.Status_c__c || opportunity.StageName).toUpperCase() : 'PENDING',
            tierDisplay: opportunity.Tier__c || 'Tier 1',
            
            tierBadgeClass: this.getTierBadgeClass(opportunity.Tier__c),
            statusBadgeClass: this.getStatusBadgeClass(opportunity.Status_c__c || opportunity.StageName),
            rowClass: this.getRowClass(opportunity, daysDiff),
            dateClass: daysDiff <= 7 ? 'date-recent' : '',
            
            debtFormatted: this.formatCurrency(opportunity.Estimated_Total_Debt__c || opportunity.Amount),
            settledDisplay: 'Loading...', // Will be updated asynchronously
            enrollmentFormatted: this.formatDate(opportunity.First_Draft_Date__c),
            
            isNew: daysDiff <= 7,
            isUrgent: opportunity.Tier__c === 'Tier 3' || opportunity.StageName === 'NSF',
            daysSinceEnrollment: daysDiff,
            showWelcomePanel: false,
            expandedKey: opportunity.Id + '-expanded'
        };
    }

    get allFilterClass() {
        return this.currentFilter === 'all' ? 'brand' : 'neutral';
    }

    get contractSignedFilterClass() {
        return this.currentFilter === 'contractSigned' ? 'brand' : 'neutral';
    }

    get enrolledFilterClass() {
        return this.currentFilter === 'enrolled' ? 'brand' : 'neutral';
    }

    get nsfFilterClass() {
        return this.currentFilter === 'nsf' ? 'brand' : 'neutral';
    }

    get cancelledFilterClass() {
        return this.currentFilter === 'cancelled' ? 'brand' : 'neutral';
    }

    handleFilterAll() {
        this.currentFilter = 'all';
        this.applyCurrentFilter();
    }

    handleFilterContractSigned() {
        this.currentFilter = 'contractSigned';
        this.applyCurrentFilter();
    }

    handleFilterEnrolled() {
        this.currentFilter = 'enrolled';
        this.applyCurrentFilter();
    }

    handleFilterNSF() {
        this.currentFilter = 'nsf';
        this.applyCurrentFilter();
    }

    handleFilterCancelled() {
        this.currentFilter = 'cancelled';
        this.applyCurrentFilter();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.applyCurrentFilter();
    }

    applyCurrentFilter() {
        let filtered = [...this.opportunities];

        switch(this.currentFilter) {
            case 'contractSigned':
                filtered = filtered.filter(o => o.StageName === 'Contract Signed');
                break;
            case 'enrolled':
                filtered = filtered.filter(o => o.StageName === 'Enrolled');
                break;
            case 'nsf':
                filtered = filtered.filter(o => o.StageName === 'NSF');
                break;
            case 'cancelled':
                filtered = filtered.filter(o => o.StageName === 'Cancelled');
                break;
        }

        if (this.searchTerm) {
            filtered = filtered.filter(opportunity => 
                (opportunity.Name && opportunity.Name.toLowerCase().includes(this.searchTerm)) ||
                (opportunity.StageName && opportunity.StageName.toLowerCase().includes(this.searchTerm)) ||
                (opportunity.Tier__c && opportunity.Tier__c.toLowerCase().includes(this.searchTerm))
            );
        }

        this.allFilteredOpportunities = filtered;
        this.totalRecords = filtered.length;
        this.currentPage = 1;
        this.paginateResults();
        
        this.updateStatistics(filtered);
    }

    paginateResults() {
        if (!this.allFilteredOpportunities) {
            this.allFilteredOpportunities = [];
        }
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.filteredOpportunities = this.allFilteredOpportunities.slice(start, end).map(opportunity => ({
            ...opportunity,
            showWelcomePanel: opportunity.Id === this.expandedOpportunityId
        }));
    }

    handleRowClick(event) {
        const opportunityId = event.currentTarget.dataset.id;
        
        if (this.expandedOpportunityId === opportunityId) {
            this.expandedOpportunityId = null;
        } else {
            this.expandedOpportunityId = opportunityId;
        }
        
        this.filteredOpportunities = this.filteredOpportunities.map(opportunity => ({
            ...opportunity,
            showWelcomePanel: opportunity.Id === this.expandedOpportunityId
        }));
        
        this.updateRowStyles(opportunityId);
    }

    handleOpportunityNameClick(event) {
        event.stopPropagation(); // Prevent row click from triggering
        const opportunityId = event.currentTarget.dataset.opportunityId;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: opportunityId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }
    
    updateRowStyles(selectedId) {
        setTimeout(() => {
            const rows = this.template.querySelectorAll('[data-id]');
            rows.forEach(row => {
                const rowId = row.dataset.id;
                if (rowId === selectedId && this.expandedOpportunityId === selectedId) {
                    row.classList.add('expanded-row');
                } else {
                    row.classList.remove('expanded-row');
                }
            });
        }, 0);
    }

    handleViewDetails(event) {
        const opportunityId = event.target.dataset.id;
        this.navigateToRecord(opportunityId);
    }

    handleEdit(event) {
        const opportunityId = event.target.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: opportunityId,
                actionName: 'edit'
            }
        });
    }

    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handlePrevious() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.paginateResults();
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.paginateResults();
        }
    }

    get hasOpportunities() {
        return this.filteredOpportunities && this.filteredOpportunities.length > 0;
    }

    get showPagination() {
        return this.totalRecords > this.pageSize;
    }

    get startRecord() {
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    get endRecord() {
        return Math.min(this.currentPage * this.pageSize, this.totalRecords);
    }

    get totalPages() {
        return Math.ceil(this.totalRecords / this.pageSize);
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage === this.totalPages;
    }

    get totalDebtFormatted() {
        return this.formatCurrency(this.filteredTotalDebt);
    }
    
    get displayTotalOpportunities() {
        return this.filteredTotalOpportunities;
    }
    
    get displayContractSignedOpportunities() {
        return this.filteredContractSignedOpportunities;
    }
    
    get displayEnrolledOpportunities() {
        return this.filteredEnrolledOpportunities;
    }
    
    get displayNsfOpportunities() {
        return this.filteredNsfOpportunities;
    }
    
    get displayCancelledOpportunities() {
        return this.filteredCancelledOpportunities;
    }

    calculateStats() {
        if (!this.opportunities || !Array.isArray(this.opportunities)) {
            this.totalOpportunities = 0;
            this.contractSignedOpportunities = 0;
            this.enrolledOpportunities = 0;
            this.nsfOpportunities = 0;
            this.cancelledOpportunities = 0;
            this.totalDebt = 0;
            return;
        }
        
        this.totalOpportunities = this.opportunities.length;
        this.contractSignedOpportunities = this.opportunities.filter(o => o && o.StageName === 'Contract Signed').length;
        this.enrolledOpportunities = this.opportunities.filter(o => o && o.StageName === 'Enrolled').length;
        this.nsfOpportunities = this.opportunities.filter(o => o && o.StageName === 'NSF').length;
        this.cancelledOpportunities = this.opportunities.filter(o => o && o.StageName === 'Cancelled').length;
        this.totalDebt = this.opportunities.reduce((sum, opportunity) => {
            const debt = opportunity && (opportunity.Estimated_Total_Debt__c || opportunity.Amount) ? 
                        Number(opportunity.Estimated_Total_Debt__c || opportunity.Amount) : 0;
            return sum + (isNaN(debt) ? 0 : debt);
        }, 0);
    }
    
    updateStatistics(filteredOpportunities) {
        if (!filteredOpportunities || !Array.isArray(filteredOpportunities)) {
            this.filteredTotalOpportunities = 0;
            this.filteredContractSignedOpportunities = 0;
            this.filteredEnrolledOpportunities = 0;
            this.filteredNsfOpportunities = 0;
            this.filteredCancelledOpportunities = 0;
            this.filteredTotalDebt = 0;
            return;
        }
        
        this.filteredTotalOpportunities = filteredOpportunities.length;
        this.filteredContractSignedOpportunities = filteredOpportunities.filter(o => o && o.StageName === 'Contract Signed').length;
        this.filteredEnrolledOpportunities = filteredOpportunities.filter(o => o && o.StageName === 'Enrolled').length;
        this.filteredNsfOpportunities = filteredOpportunities.filter(o => o && o.StageName === 'NSF').length;
        this.filteredCancelledOpportunities = filteredOpportunities.filter(o => o && o.StageName === 'Cancelled').length;
        this.filteredTotalDebt = filteredOpportunities.reduce((sum, opportunity) => {
            const debt = opportunity && (opportunity.Estimated_Total_Debt__c || opportunity.Amount) ? 
                        Number(opportunity.Estimated_Total_Debt__c || opportunity.Amount) : 0;
            return sum + (isNaN(debt) ? 0 : debt);
        }, 0);
    }

    getProgressValue(progressText) {
        if (!progressText) return 0;
        
        const numericValue = parseInt(progressText, 10);
        if (!isNaN(numericValue) && numericValue >= 0 && numericValue <= 100) {
            return numericValue;
        }
        
        const progressMap = {
            'Contract Signed': 25,
            'Enrolled': 50,
            'NSF': 75,
            'Completed': 100
        };
        
        return progressMap[progressText] || 0;
    }

    getTierBadgeClass(tier) {
        switch(tier) {
            case 'Tier 1':
                return 'slds-badge tier-1';
            case 'Tier 2':
                return 'slds-badge tier-2';
            case 'Tier 3':
                return 'slds-badge tier-3';
            default:
                return 'slds-badge';
        }
    }

    getStatusBadgeClass(status) {
        switch(status) {
            case 'Contract Signed':
                return 'slds-badge status-active';
            case 'Enrolled':
                return 'slds-badge status-enrolled';
            case 'NSF':
                return 'slds-badge status-nsf';
            case 'Cancelled':
                return 'slds-badge status-cancelled';
            default:
                return 'slds-badge';
        }
    }

    getRowClass(opportunity, daysDiff) {
        let classes = 'slds-hint-parent';
        if (daysDiff <= 7) classes += ' new-client';
        if (opportunity.isUrgent) classes += ' urgent-client';
        return classes;
    }

    formatCurrency(amount) {
        if (!amount || isNaN(amount)) return '$0';
        const numAmount = Number(amount);
        if (numAmount >= 1000000) {
            return '$' + (numAmount / 1000000).toFixed(1) + 'M';
        } else if (numAmount >= 1000) {
            return '$' + (numAmount / 1000).toFixed(1) + 'K';
        }
        return '$' + numAmount.toLocaleString();
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return date.toLocaleDateString('en-US', { 
            month: 'short', 
            day: 'numeric',
            year: 'numeric'
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

    triggerProgressAnimations() {
        setTimeout(() => {
            const progressBars = this.template.querySelectorAll('.progress-bar-fill');
            progressBars.forEach(bar => {
                const progressWidth = bar.style.getPropertyValue('--progress-width');
                bar.style.width = progressWidth;
            });
        }, 100);
    }

    refreshData() {
        this.isLoading = true;
        return refreshApex(this.wiredOpportunitiesResult);
    }
}