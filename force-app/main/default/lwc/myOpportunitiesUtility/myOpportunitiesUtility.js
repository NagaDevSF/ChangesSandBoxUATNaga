import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyOpportunities from '@salesforce/apex/MyRecordsController.getMyOpportunities';
import getMyOpportunitiesCount from '@salesforce/apex/MyRecordsController.getMyOpportunitiesCount';
import Id from '@salesforce/user/Id';

export default class MyOpportunitiesUtility extends NavigationMixin(LightningElement) {
    @track opportunities = [];
    @track totalOpportunitiesCount = 0;
    @track isLoading = true;
    @track error;
    currentUserId = Id;
    
    connectedCallback() {
        this.loadMyOpportunities();
    }
    
    loadMyOpportunities() {
        this.isLoading = true;
        this.error = undefined;
        
        // Load both the opportunities list and the total count
        Promise.all([
            getMyOpportunities(),
            getMyOpportunitiesCount()
        ])
        .then(([opportunitiesResult, countResult]) => {
            this.opportunities = opportunitiesResult || [];
            this.totalOpportunitiesCount = countResult || 0;
            this.isLoading = false;
            console.log('Opportunities loaded successfully:', opportunitiesResult);
            console.log('Total opportunities count:', countResult);
        })
        .catch(error => {
            console.error('Error loading opportunities:', error);
            this.error = {
                message: 'Unable to load opportunities. Please check your permissions.',
                details: error.body?.message || error.message || 'Unknown error'
            };
            this.isLoading = false;
            this.opportunities = [];
            this.totalOpportunitiesCount = 0;
        });
    }

    get hasOpportunities() {
        return this.opportunities && this.opportunities.length > 0;
    }

    handleOpportunityClick(event) {
        const opportunityId = event.currentTarget.dataset.recordId;
        this.navigateToRecord(opportunityId);
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

    handleViewAllOpportunities() {
        // Navigate to Opportunity list view - works for every user
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'list'
            },
            state: {
                filterName: 'MyOpportunities'
            }
        });
    }
}