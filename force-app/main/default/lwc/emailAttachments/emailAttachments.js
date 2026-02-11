import { LightningElement, api, wire, track } from 'lwc';
import getEmailAttachments from '@salesforce/apex/LeadEmailAttachmentController.getEmailAttachments';
import { refreshApex } from '@salesforce/apex';

export default class EmailAttachments extends LightningElement {
@api recordId;
@track attachments = [];
@track error;
@track isLoading = true;

wiredAttachmentsResult;

// Define a single column for the datatable
columns = [
{
label: 'File Name',
fieldName: 'downloadUrl',
type: 'url',
typeAttributes: {
label: { fieldName: 'title' },
target: '_blank'
}
}
];

@wire(getEmailAttachments, { leadId: '$recordId' })
wiredAttachments(result) {
this.wiredAttachmentsResult = result;
this.isLoading = false;

if (result.data) {
this.attachments = result.data;
this.error = undefined;
} else if (result.error) {
this.attachments = [];
this.error = result.error;
console.error('Error retrieving attachments:', result.error);
}
}

// Refresh the data
handleRefresh() {
this.isLoading = true;
refreshApex(this.wiredAttachmentsResult)
.then(() => {
this.isLoading = false;
})
.catch(error => {
this.isLoading = false;
this.error = error;
});
}

// Check if we have attachments to display
get hasAttachments() {
return this.attachments && this.attachments.length > 0;
}

// Format the error message
get errorMessage() {
if (!this.error) return '';
return (this.error.body && this.error.body.message)
? this.error.body.message
: this.error.message;
}
}