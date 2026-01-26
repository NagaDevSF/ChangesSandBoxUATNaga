import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getEmailAttachments from '@salesforce/apex/OpportunityEmailAttachmentController.getEmailAttachments';

export default class OpportunityEmailAttachments extends NavigationMixin(LightningElement) {
    @api recordId; // Opportunity Id passed from record page
    @track attachments = [];
    @track isLoading = true;
    @track error;
    @track hasAttachments = false;
    @track wiredAttachmentsResult; // Store the wired result for refreshing
    
    // File type icons mapping
    fileTypeIcons = {
        pdf: 'doctype:pdf',
        csv: 'doctype:csv',
        doc: 'doctype:word',
        docx: 'doctype:word',
        xls: 'doctype:excel',
        xlsx: 'doctype:excel',
        ppt: 'doctype:ppt',
        pptx: 'doctype:ppt',
        txt: 'doctype:txt',
        png: 'doctype:image',
        jpg: 'doctype:image',
        jpeg: 'doctype:image',
        gif: 'doctype:image',
        zip: 'doctype:zip'
    };
    
    // Wire the Apex method to get email attachments
    @wire(getEmailAttachments, { opportunityId: '$recordId' })
    wiredAttachments(result) {
        this.wiredAttachmentsResult = result;
        this.isLoading = false;
        const { error, data } = result;
        if (data) {
            this.processAttachments(data);
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceErrors(error);
            this.attachments = [];
            this.hasAttachments = false;
            this.showToast('Error', this.error, 'error');
        }
    }
    
    // Process the attachments returned from Apex
    processAttachments(data) {
        if (data && data.length > 0) {
            this.hasAttachments = true;
            this.attachments = data.map(att => {
                // Determine file extension
                const ext = this.getFileExtension(att.name).toLowerCase();
                
                return {
                    ...att,
                    iconName: this.getFileIcon(ext),
                    url: this.getFileUrl(att)
                };
            });
        } else {
            this.hasAttachments = false;
            this.attachments = [];
        }
    }
    
    // Get file extension from name
    getFileExtension(filename) {
        if (!filename) return '';
        return filename.slice((filename.lastIndexOf('.') - 1 >>> 0) + 2);
    }
    
    // Get the appropriate icon for a file type
    getFileIcon(extension) {
        return this.fileTypeIcons[extension] || 'doctype:attachment';
    }
    
    // Get the URL for the file
    getFileUrl(fileWrapper) {
        if (fileWrapper.fileType === 'ContentDocument') {
            return `/sfc/servlet.shepherd/document/download/${fileWrapper.id}`;
        } else { // Attachment
            return `/servlet/servlet.FileDownload?file=${fileWrapper.id}`;
        }
    }
    
    // Navigate to source record when clicked
    handleSourceClick(event) {
        const sourceId = event.currentTarget.dataset.id;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: sourceId,
                actionName: 'view'
            }
        });
    }
    
    // Download a file when clicked
    handleFileClick(event) {
        const url = event.currentTarget.dataset.url;
        window.open(url, '_blank');
    }
    
    // Handle refresh button click
    handleRefresh() {
        this.isLoading = true;
        return refreshApex(this.wiredAttachmentsResult);
    }
    
    // Show a toast message
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
    
    // Error reduction helper
    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }
        // UI API read errors
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        // UI API DML, Apex and network errors
        else if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        // JS errors
        else if (typeof error.message === 'string') {
            return error.message;
        }
        return String(error);
    }
}