import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyLeads from '@salesforce/apex/MyRecordsController.getMyLeads';
import getMyLeadsCount from '@salesforce/apex/MyRecordsController.getMyLeadsCount';
import Id from '@salesforce/user/Id';

export default class MyLeadsUtility extends NavigationMixin(LightningElement) {
    @track leads = [];
    @track totalLeadsCount = 0;
    @track isLoading = true;
    @track error;
    currentUserId = Id;
    
    connectedCallback() {
        this.loadMyLeads();
    }
    
    loadMyLeads() {
        this.isLoading = true;
        this.error = undefined;
        
        // Load both the leads list and the total count
        Promise.all([
            getMyLeads(),
            getMyLeadsCount()
        ])
        .then(([leadsResult, countResult]) => {
            this.leads = leadsResult || [];
            this.totalLeadsCount = countResult || 0;
            this.isLoading = false;
            console.log('Leads loaded successfully:', leadsResult);
            console.log('Total leads count:', countResult);
        })
        .catch(error => {
            console.error('Error loading leads:', error);
            this.error = {
                message: 'Unable to load leads. Please check your permissions.',
                details: error.body?.message || error.message || 'Unknown error'
            };
            this.isLoading = false;
            this.leads = [];
            this.totalLeadsCount = 0;
        });
    }

    get hasLeads() {
        return this.leads && this.leads.length > 0;
    }

    handleLeadClick(event) {
        const leadId = event.currentTarget.dataset.recordId;
        this.navigateToRecord(leadId);
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

    handleViewAllLeads() {
        // Navigate to Lead list view - works for every user
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead',
                actionName: 'list'
            },
            state: {
                filterName: 'My_Leads'
            }
        });
    }
}