import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import getRecordFiles from '@salesforce/apex/RelatedRecordFileController.getRecordFiles';
import getFileTypeOptions from '@salesforce/apex/RelatedRecordFileController.getFileTypeOptions';
import updateFileType from '@salesforce/apex/RelatedRecordFileController.updateFileType';
import updateFileTypes from '@salesforce/apex/RelatedRecordFileController.updateFileTypes';
import removeFileFromRecord from '@salesforce/apex/RelatedRecordFileController.removeFileFromRecord';
import getRelatedRecords from '@salesforce/apex/RelatedRecordFileController.getRelatedRecords';
import syncFileToRecords from '@salesforce/apex/RelatedRecordFileController.syncFileToRecords';
import inheritFilesFromRelatedRecords from '@salesforce/apex/RelatedRecordFileController.inheritFilesFromRelatedRecords';
import removeFileFromAllRelatedRecords from '@salesforce/apex/RelatedRecordFileController.removeFileFromAllRelatedRecords';

export default class RelatedRecordFileManager extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api enableSync;
    
    @track recordFiles = [];
    @track fileTypeOptions = [];
    @track selectedFileType = '';
    @track isLoading = false;
    @track relatedRecordOptions = [];
    @track autoSyncRecords = [];
    @track objectLabel = '';
    
    wiredRecordFiles;
    wiredFileTypeOptions;
    wiredObjectInfo;

    @wire(getObjectInfo, { objectApiName: '$objectApiName' })
    wiredGetObjectInfo(result) {
        this.wiredObjectInfo = result;
        if (result.data) {
            this.objectLabel = result.data.label;
        }
    }

    @wire(getRecordFiles, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wiredGetRecordFiles(result) {
        this.wiredRecordFiles = result;
        if (result.data) {
            this.recordFiles = result.data;
        } else if (result.error) {
            console.error('Error loading files:', result.error);
            const errorMessage = result.error.body && result.error.body.message ? result.error.body.message : result.error.message || 'Unknown error';
            this.showToast('Error', 'Error loading files: ' + errorMessage, 'error');
        }
    }

    @wire(getFileTypeOptions)
    wiredGetFileTypeOptions(result) {
        this.wiredFileTypeOptions = result;
        if (result.data) {
            this.fileTypeOptions = result.data;
        } else if (result.error) {
            console.error('Error loading file type options:', result.error);
            const errorMessage = result.error.body && result.error.body.message ? result.error.body.message : result.error.message || 'Unknown error';
            this.showToast('Error', 'Error loading file type options: ' + errorMessage, 'error');
        }
    }

    connectedCallback() {
        // Enable sync by default if not explicitly set
        if (this.enableSync === undefined) {
            this.enableSync = true;
        }
        this.loadRelatedRecords();
    }

    async loadRelatedRecords() {
        try {
            const relatedRecords = await getRelatedRecords({ 
                recordId: this.recordId, 
                objectApiName: this.objectApiName 
            });
            this.relatedRecordOptions = relatedRecords.map(record => ({
                label: `${record.objectLabel}: ${record.name}`,
                value: record.recordId
            }));
            // Auto-populate all related records for automatic sync
            this.autoSyncRecords = relatedRecords.map(record => record.recordId);
            
            // Check for file inheritance with minimal delay for Flow-created records
            setTimeout(() => {
                if ((!this.recordFiles || this.recordFiles.length === 0) && this.autoSyncRecords.length > 0) {
                    this.inheritExistingFiles();
                }
            }, 100); // Optimized to 100ms for better user experience
        } catch (error) {
            console.error('Error loading related records:', error);
        }
    }

    async inheritExistingFiles() {
        try {
            await inheritFilesFromRelatedRecords({
                newRecordId: this.recordId,
                objectApiName: this.objectApiName
            });
            // Refresh the file list after inheritance
            await refreshApex(this.wiredRecordFiles);
        } catch (error) {
            console.error('Error inheriting files:', error);
        }
    }

    get hasFiles() {
        return this.recordFiles && this.recordFiles.length > 0;
    }

    get isUploadDisabled() {
        return !this.selectedFileType;
    }

    get showSyncOptions() {
        return false; // Hide manual sync options - auto sync enabled
    }

    handleFileTypeChange(event) {
        this.selectedFileType = event.detail.value;
    }

    // Removed manual sync option handling - auto sync enabled

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles && uploadedFiles.length > 0) {
            this.isLoading = true;
            const versionIds = uploadedFiles.map(file => file.contentVersionId);
            
            try {
                // Only update file types if a type was selected
                if (this.selectedFileType) {
                    await updateFileTypes({ 
                        versionIds: versionIds, 
                        fileType: this.selectedFileType 
                    });
                }

                // Auto-sync to all related records - always enabled
                if (this.autoSyncRecords && this.autoSyncRecords.length > 0) {
                    await syncFileToRecords({
                        contentDocumentIds: uploadedFiles.map(file => file.documentId),
                        targetRecordIds: this.autoSyncRecords
                    });
                }

                this.showToast('Success', `${uploadedFiles.length} file(s) uploaded and categorized successfully`, 'success');
                this.selectedFileType = '';
                // Auto-sync completed - no manual reset needed
                await refreshApex(this.wiredRecordFiles);
            } catch (error) {
                console.error('Error processing uploaded files:', error);
                const errorMessage = error.body && error.body.message ? error.body.message : error.message || 'Unknown error';
                this.showToast('Error', `Error processing uploaded files: ${errorMessage}`, 'error');
            } finally {
                this.isLoading = false;
            }
        }
    }

    // Removed manual sync checkbox handling - auto sync enabled

    async handleFileTypeUpdate(event) {
        const versionId = event.target.dataset.versionId;
        const newFileType = event.detail.value;
        this.isLoading = true;

        try {
            await updateFileType({ versionId: versionId, fileType: newFileType });
            this.showToast('Success', 'Document type updated successfully', 'success');
            await refreshApex(this.wiredRecordFiles);
        } catch (error) {
            const errorMessage = error.body && error.body.message ? error.body.message : error.message || 'Unknown error';
            this.showToast('Error', 'Error updating document type: ' + errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRemoveFile(event) {
        const documentId = event.target.dataset.documentId;
        if (!documentId) return;
        if (!confirm('Are you sure?')) return;
        
        this.isLoading = true;
        try {
            const resultMessage = await removeFileFromAllRelatedRecords({ 
                documentId: documentId, 
                sourceRecordId: this.recordId,
                objectApiName: this.objectApiName
            });
            
            // Always refresh the UI to reflect changes
            await refreshApex(this.wiredRecordFiles);
            
            // Show simple success message
            this.showToast('Success', 'File removed', 'success');
        } catch (error) {
            this.showToast('Error', 'Error removing file: ' + (error.body && error.body.message ? error.body.message : error.message), 'error');
            // Still try to refresh the UI in case some deletions succeeded
            await refreshApex(this.wiredRecordFiles);
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}