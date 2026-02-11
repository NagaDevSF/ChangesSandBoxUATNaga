import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getNotesForRecord from '@salesforce/apex/UnifiedNotesController.getNotesForRecord';
import createNote from '@salesforce/apex/UnifiedNotesController.createNote';
import updateNote from '@salesforce/apex/UnifiedNotesController.updateNote';
import deleteNote from '@salesforce/apex/UnifiedNotesController.deleteNote';
import LightningConfirm from 'lightning/confirm';

export default class UnifiedNotesManager extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api cardTitle = 'Notes';

    @track notes = [];
    @track isLoading = false;
    @track isModalOpen = false;
    @track isEditMode = false;
    @track isSaving = false;
    @track currentNote = { title: '', content: '' };
    @track expandedNoteIds = new Set();

    wiredNotesResult;
    _textareaInitialized = false;

    // Lifecycle hook to sync native textarea value
    renderedCallback() {
        if (this.isModalOpen && !this._textareaInitialized) {
            const textarea = this.template.querySelector('.note-textarea');
            if (textarea) {
                textarea.value = this.currentNote.content || '';
                this._textareaInitialized = true;
            }
        }
        if (!this.isModalOpen) {
            this._textareaInitialized = false;
        }
    }

    // Wire service to get notes
    @wire(getNotesForRecord, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wiredGetNotes(result) {
        this.wiredNotesResult = result;
        this.isLoading = true;

        if (result.data) {
            this.notes = result.data.map(note => ({
                ...note,
                isExpanded: this.expandedNoteIds.has(note.noteId),
                contentPreview: this.getContentPreview(note.content),
                hasMoreContent: note.content && note.content.length > 200
            }));
            this.isLoading = false;
        } else if (result.error) {
            this.showToast('Error', this.extractErrorMessage(result.error), 'error');
            this.isLoading = false;
        }
    }

    // Computed properties
    get hasNotes() {
        return this.notes && this.notes.length > 0;
    }

    get notesCount() {
        return this.notes ? this.notes.length : 0;
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Note' : 'New Note';
    }

    get saveButtonLabel() {
        return this.isEditMode ? 'Update' : 'Save';
    }

    get cardTitleWithCount() {
        return `${this.cardTitle} (${this.notesCount})`;
    }

    get isSaveDisabled() {
        return !this.currentNote.title || !this.currentNote.title.trim() ||
               !this.currentNote.content || !this.currentNote.content.trim();
    }

    get disableSaveButton() {
        return this.isSaveDisabled || this.isSaving || this.isLoading;
    }

    // Helper to get content preview
    getContentPreview(content) {
        if (!content) return '';
        if (content.length <= 200) return content;
        return content.substring(0, 200) + '...';
    }

    // Modal handlers
    openNewNoteModal() {
        this.isEditMode = false;
        this.currentNote = { title: '', content: '' };
        this.clearFormValidation();
        this.isModalOpen = true;
    }

    openEditNoteModal(event) {
        const noteId = event.currentTarget.dataset.noteId;
        const note = this.notes.find(n => n.noteId === noteId);

        if (note) {
            this.isEditMode = true;
            this.currentNote = {
                noteId: note.noteId,
                title: note.title,
                content: note.content
            };
            this.isModalOpen = true;
        }
    }

    closeModal() {
        this.clearFormValidation();
        this.isModalOpen = false;
        this.currentNote = { title: '', content: '' };
    }

    // Input handlers
    handleTitleChange(event) {
        const value = event.target.value;
        this.currentNote = { ...this.currentNote, title: value };
        // Clear error styling on input
        event.target.classList.remove('slds-has-error');
        if (typeof event.target.setCustomValidity === 'function') {
            event.target.setCustomValidity('');
            event.target.reportValidity();
        }
    }

    handleContentChange(event) {
        const value = event.target.value;
        this.currentNote = { ...this.currentNote, content: value };
        // Clear error styling on input
        event.target.classList.remove('slds-has-error');
    }

    // Save note (create or update)
    async handleSaveNote() {
        if (!this.validateForm() || this.isSaving) {
            return;
        }

        this.isLoading = true;
        this.isSaving = true;

        try {
            if (this.isEditMode) {
                await updateNote({
                    noteId: this.currentNote.noteId,
                    title: this.currentNote.title.trim(),
                    content: this.currentNote.content.trim()
                });
                this.showToast('Success', 'Note updated successfully', 'success');
            } else {
                await createNote({
                    title: this.currentNote.title.trim(),
                    content: this.currentNote.content.trim(),
                    recordId: this.recordId,
                    objectApiName: this.objectApiName
                });
                this.showToast('Success', 'Note created successfully', 'success');
            }

            this.closeModal();
            await this.refreshNotes();

        } catch (error) {
            this.showToast('Error', 'Error saving note: ' + this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
            this.isSaving = false;
        }
    }

    // Delete note
    async handleDeleteNote(event) {
        const noteId = event.currentTarget.dataset.noteId;
        const noteTitle = event.currentTarget.dataset.noteTitle;

        // Confirmation using standard confirm (consider lightning-confirm in newer versions)
        const confirmed = await this.confirmDelete(noteTitle);
        if (!confirmed) return;

        this.isLoading = true;

        try {
            await deleteNote({ noteId: noteId });
            this.showToast('Success', 'Note deleted successfully', 'success');
            await this.refreshNotes();

        } catch (error) {
            this.showToast('Error', 'Error deleting note: ' + this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Toggle note expansion
    toggleNoteExpansion(event) {
        const noteId = event.currentTarget.dataset.noteId;

        if (this.expandedNoteIds.has(noteId)) {
            this.expandedNoteIds.delete(noteId);
        } else {
            this.expandedNoteIds.add(noteId);
        }

        // Update notes array to trigger re-render
        this.notes = this.notes.map(note => ({
            ...note,
            isExpanded: this.expandedNoteIds.has(note.noteId)
        }));
    }

    // Confirm delete dialog
    async confirmDelete(noteTitle) {
        return LightningConfirm.open({
            message: `Are you sure you want to delete "${noteTitle}"? This cannot be undone.`,
            label: 'Delete Note',
            variant: 'destructive'
        });
    }

    // Refresh notes data
    async refreshNotes() {
        await refreshApex(this.wiredNotesResult);
    }

    // Manual refresh button
    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.refreshNotes();
        } finally {
            this.isLoading = false;
        }
    }

    // Show toast notification
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Validate all modal fields and surface inline errors
    validateForm() {
        const inputs = Array.from(this.template.querySelectorAll('[data-field]'));
        let allValid = true;
        let firstInvalid = null;

        inputs.forEach(input => {
            const value = input.value;
            const isValid = value && value.trim();

            if (!isValid) {
                allValid = false;
                if (!firstInvalid) firstInvalid = input;

                // Handle lightning components vs native elements
                if (typeof input.setCustomValidity === 'function') {
                    input.setCustomValidity('This field is required');
                    input.reportValidity();
                } else {
                    input.classList.add('slds-has-error');
                }
            } else {
                if (typeof input.setCustomValidity === 'function') {
                    input.setCustomValidity('');
                    input.reportValidity();
                } else {
                    input.classList.remove('slds-has-error');
                }
            }
        });

        if (firstInvalid) {
            firstInvalid.focus();
        }

        return allValid;
    }

    clearFormValidation() {
        const inputs = this.template.querySelectorAll('[data-field]');
        inputs.forEach(input => {
            if (typeof input.setCustomValidity === 'function') {
                input.setCustomValidity('');
                input.reportValidity();
            } else {
                input.classList.remove('slds-has-error');
            }
        });
    }

    // Extract error message from various error formats
    extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return 'An unknown error occurred';
    }
}