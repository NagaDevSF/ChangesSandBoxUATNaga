import { LightningElement, track, api } from 'lwc';
import getCreditorHierarchy from '@salesforce/apex/CreditorHierarchyController.getCreditorHierarchy';
import exportToCSV from '@salesforce/apex/CreditorHierarchyController.exportToCSV';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CreditorHierarchyView extends LightningElement {
    @api title = 'Creditor Hierarchy';
    @track accounts = [];
    @track summary = {};
    @track isLoading = true;
    @track isRefreshing = false;
    @track error = null;
    @track expandedItems = new Set();
    @track searchTerm = '';
    @track lastRefresh = null;
    
    refreshInterval;
    
    // Lifecycle hooks
    connectedCallback() {
        this.loadData();
        this.startAutoRefresh();
    }
    
    disconnectedCallback() {
        this.stopAutoRefresh();
    }
    
    // Auto-refresh functionality
    startAutoRefresh() {
        this.refreshInterval = setInterval(() => {
            this.refreshData();
        }, 15000); // 15 seconds
    }
    
    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }
    
    // Data loading methods
    async loadData() {
        this.isLoading = true;
        this.error = null;
        
        try {
            const result = await getCreditorHierarchy();
            
            if (result.success) {
                this.accounts = result.accounts || [];
                this.summary = result.summary || {};
                this.lastRefresh = new Date().toLocaleTimeString();
                this.error = null;
            } else {
                this.error = result.error || 'Unknown error occurred';
                this.accounts = [];
                this.summary = {};
            }
        } catch (error) {
            console.error('Error loading creditor hierarchy:', error);
            this.error = 'Failed to load data: ' + (error.body?.message || error.message);
            this.accounts = [];
            this.summary = {};
        } finally {
            this.isLoading = false;
        }
    }
    
    async refreshData() {
        this.isRefreshing = true;
        
        try {
            const result = await getCreditorHierarchy();
            
            if (result.success) {
                this.accounts = result.accounts || [];
                this.summary = result.summary || {};
                this.lastRefresh = new Date().toLocaleTimeString();
                this.error = null;
            } else {
                console.warn('Refresh failed:', result.error);
            }
        } catch (error) {
            console.warn('Auto-refresh failed:', error);
            // Don't show error toast for auto-refresh failures
        } finally {
            this.isRefreshing = false;
        }
    }
    
    // Manual refresh
    handleRefresh() {
        this.loadData();
    }
    
    // Expand/Collapse functionality
    toggleAccount(event) {
        const accountId = event.currentTarget.dataset.accountId;
        const key = `account_${accountId}`;
        
        if (this.expandedItems.has(key)) {
            this.expandedItems.delete(key);
        } else {
            this.expandedItems.add(key);
        }
        
        // Force reactivity
        this.expandedItems = new Set(this.expandedItems);
    }
    
    toggleCreditorList(event) {
        const creditorListId = event.currentTarget.dataset.creditorListId;
        const key = `creditorList_${creditorListId}`;
        
        if (this.expandedItems.has(key)) {
            this.expandedItems.delete(key);
        } else {
            this.expandedItems.add(key);
        }
        
        // Force reactivity
        this.expandedItems = new Set(this.expandedItems);
    }
    
    expandAll() {
        const newExpandedItems = new Set();
        
        this.filteredAccounts.forEach(account => {
            newExpandedItems.add(`account_${account.id}`);
            account.creditorsLists.forEach(creditorList => {
                newExpandedItems.add(`creditorList_${creditorList.id}`);
            });
        });
        
        this.expandedItems = newExpandedItems;
    }
    
    collapseAll() {
        this.expandedItems = new Set();
    }
    
    // Search functionality
    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
    }
    
    // Computed properties
    get filteredAccounts() {
        if (!this.searchTerm) {
            return this.accounts;
        }
        
        return this.accounts.filter(account => {
            // Search in account fields
            const accountMatch = account.name?.toLowerCase().includes(this.searchTerm) ||
                                account.accountNumber?.toLowerCase().includes(this.searchTerm) ||
                                account.primaryCreditorPhone?.toLowerCase().includes(this.searchTerm) ||
                                account.ein?.toLowerCase().includes(this.searchTerm);
            
            // Search in creditor opportunities
            const creditorOpportunityMatch = account.creditorOpportunities?.some(credOpp =>
                credOpp.name?.toLowerCase().includes(this.searchTerm) ||
                credOpp.frequency?.toLowerCase().includes(this.searchTerm) ||
                credOpp.opportunityNumber?.toLowerCase().includes(this.searchTerm)
            );
            
            // Search in negotiations
            const negotiationMatch = account.creditorOpportunities?.some(credOpp =>
                credOpp.negotiations?.some(neg =>
                    neg.name?.toLowerCase().includes(this.searchTerm) ||
                    neg.negotiationStatus?.toLowerCase().includes(this.searchTerm)
                )
            );
            
            return accountMatch || creditorOpportunityMatch || negotiationMatch;
        });
    }
    
    get hasData() {
        return this.accounts && this.accounts.length > 0;
    }
    
    get showNoResults() {
        return !this.isLoading && !this.error && this.searchTerm && this.filteredAccounts.length === 0;
    }
    
    get showEmptyState() {
        return !this.isLoading && !this.error && !this.searchTerm && this.accounts.length === 0;
    }
    
    // Helper methods for template
    isAccountExpanded(accountId) {
        return this.expandedItems.has(`account_${accountId}`);
    }
    
    isCreditorListExpanded(creditorListId) {
        return this.expandedItems.has(`creditorList_${creditorListId}`);
    }
    
    getAccountIcon(accountId) {
        return this.isAccountExpanded(accountId) ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    getCreditorListIcon(creditorListId) {
        return this.isCreditorListExpanded(creditorListId) ? 'utility:chevrondown' : 'utility:chevronright';
    }
    
    // Export functionality
    async handleExport() {
        try {
            const csvContent = await exportToCSV();
            
            // Create and download the file
            const element = document.createElement('a');
            element.setAttribute('href', 'data:text/csv;charset=utf-8,' + encodeURIComponent(csvContent));
            element.setAttribute('download', `creditor_hierarchy_${new Date().toISOString().split('T')[0]}.csv`);
            element.style.display = 'none';
            document.body.appendChild(element);
            element.click();
            document.body.removeChild(element);
            
            this.showToast('Success', 'Data exported successfully', 'success');
        } catch (error) {
            console.error('Export error:', error);
            this.showToast('Error', 'Failed to export data: ' + (error.body?.message || error.message), 'error');
        }
    }
    
    // Print functionality
    handlePrint() {
        window.print();
    }
    
    // Utility methods
    formatCurrency(amount) {
        if (amount == null) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(amount);
    }
    
    formatDate(dateValue) {
        if (!dateValue) return '';
        return new Date(dateValue).toLocaleDateString();
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant,
            mode: 'dismissible'
        });
        this.dispatchEvent(event);
    }
    
    // Navigate to record
    navigateToRecord(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const recordType = event.currentTarget.dataset.recordType;
        
        // This would typically use NavigationMixin in a real implementation
        console.log(`Navigate to ${recordType}: ${recordId}`);
        
        // For now, just open in new tab
        const baseUrl = window.location.origin;
        window.open(`${baseUrl}/lightning/r/${recordType}/${recordId}/view`, '_blank');
    }
}