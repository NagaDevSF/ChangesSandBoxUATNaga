import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord, refreshApex } from 'lightning/uiRecordApi';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import LEAD_OBJECT from '@salesforce/schema/Lead';
import LEAD_TRANSFER_STATUS from '@salesforce/schema/Lead.Transfer_Quality_Status__c';
import OPP_TRANSFER_STATUS from '@salesforce/schema/Opportunity.Transfer_Quality_Status__c';

const FIELDS = {
    Lead: LEAD_TRANSFER_STATUS,
    Opportunity: OPP_TRANSFER_STATUS
};

export default class QualityTransferButtons extends LightningElement {
    @api recordId;
    @api objectApiName;

    transferStatus = null;
    isLoading = false;
    isDataLoaded = false;
    error = null;
    statusMessage = '';
    showStatus = false;

    picklistValues = [];
    qualifiedValue = null;
    unqualifiedValue = null;
    defaultRecordTypeId;

    wiredRecordResult;

    get fieldToQuery() {
        return this.objectApiName && FIELDS[this.objectApiName] ? [FIELDS[this.objectApiName]] : [];
    }

    // Get object info to retrieve the default record type ID
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredObjectInfo({ error, data }) {
        if (data) {
            this.defaultRecordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Error getting object info:', error);
        }
    }

    // Get picklist values for the Transfer_Quality_Status__c field
    @wire(getPicklistValues, { recordTypeId: '$defaultRecordTypeId', fieldApiName: LEAD_TRANSFER_STATUS })
    wiredPicklistValues({ error, data }) {
        if (data) {
            this.picklistValues = data.values;
            // Find Qualified and Unqualified values
            this.picklistValues.forEach(item => {
                if (item.value.toLowerCase() === 'qualified') {
                    this.qualifiedValue = item.value;
                } else if (item.value.toLowerCase() === 'unqualified') {
                    this.unqualifiedValue = item.value;
                }
            });
        } else if (error) {
            console.error('Error getting picklist values:', error);
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldToQuery' })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        const { error, data } = result;

        if (data) {
            this.transferStatus = getFieldValue(data, FIELDS[this.objectApiName]);
            this.isDataLoaded = true;
            this.error = null;
            this.updateStatusMessage();
        } else if (error) {
            this.error = error;
            this.isDataLoaded = true;
            console.error('Error loading record:', error);
        }
    }

    get isQualified() {
        return this.transferStatus && this.transferStatus.toLowerCase() === 'qualified';
    }

    get isUnqualified() {
        return this.transferStatus && this.transferStatus.toLowerCase() === 'unqualified';
    }

    get qualifiedClass() {
        let base = 'transfer-btn qualified-btn';
        if (this.isQualified) base += ' active';
        if (this.isLoading) base += ' disabled';
        return base;
    }

    get unqualifiedClass() {
        let base = 'transfer-btn unqualified-btn';
        if (this.isUnqualified) base += ' active';
        if (this.isLoading) base += ' disabled';
        return base;
    }

    get statusMessageClass() {
        let base = 'status-message';
        if (this.showStatus) {
            base += ' show';
            if (this.isQualified) {
                base += ' qualified';
            } else if (this.isUnqualified) {
                base += ' unqualified';
            }
        }
        return base;
    }

    updateStatusMessage() {
        if (this.isQualified) {
            this.statusMessage = '✓ Qualified Transfer Selected';
            this.showStatus = true;
        } else if (this.isUnqualified) {
            this.statusMessage = '✗ Unqualified Transfer Selected';
            this.showStatus = true;
        } else {
            this.statusMessage = '';
            this.showStatus = false;
        }
    }

    handleQualifiedClick() {
        if (this.isLoading || this.isQualified) return;
        this.updateTransferStatus(this.qualifiedValue || 'Qualified');
    }

    handleUnqualifiedClick() {
        if (this.isLoading || this.isUnqualified) return;
        this.updateTransferStatus(this.unqualifiedValue || 'Unqualified');
    }

    async updateTransferStatus(newValue) {
        this.isLoading = true;

        const fields = {
            Id: this.recordId,
            Transfer_Quality_Status__c: newValue
        };

        try {
            await updateRecord({ fields });

            // Update local state for immediate UI feedback
            this.transferStatus = newValue;
            this.updateStatusMessage();

            // Refresh wire to ensure sync with server
            await refreshApex(this.wiredRecordResult);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `Marked as ${newValue}`,
                    variant: 'success'
                })
            );
        } catch (error) {
            console.error('Error updating record:', error);

            // Refresh to get correct state from server on error
            await refreshApex(this.wiredRecordResult);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || 'Failed to update record',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}