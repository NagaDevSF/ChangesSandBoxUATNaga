import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getWelcomeTeamEvents from '@salesforce/apex/WelcomeTeamEventsController.getWelcomeTeamEvents';
import getWelcomeTeamEventsCount from '@salesforce/apex/WelcomeTeamEventsController.getWelcomeTeamEventsCount';

export default class WelcomeTeamEvents extends NavigationMixin(LightningElement) {
    @track events = [];
    @track totalEventsCount = 0;
    @track isLoading = true;
    @track error;

    connectedCallback() {
        this.loadEvents();
    }

    loadEvents() {
        this.isLoading = true;
        this.error = undefined;

        Promise.all([
            getWelcomeTeamEvents(),
            getWelcomeTeamEventsCount()
        ])
        .then(([eventsResult, countResult]) => {
            this.events = this.enhanceEventsWithFormatting(eventsResult || []);
            this.totalEventsCount = countResult || 0;
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error loading Welcome Team events:', error);
            this.error = {
                message: 'Unable to load Welcome Team events',
                details: error.body?.message || error.message || 'Unknown error'
            };
            this.isLoading = false;
            this.events = [];
            this.totalEventsCount = 0;
        });
    }

    enhanceEventsWithFormatting(events) {
        // Get current time in EST/EDT for date comparisons
        const now = new Date();
        const estNow = new Date(now.toLocaleString('en-US', { timeZone: 'America/New_York' }));
        const today = new Date(estNow.getFullYear(), estNow.getMonth(), estNow.getDate());
        const tomorrow = new Date(today);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const nextWeek = new Date(today);
        nextWeek.setDate(nextWeek.getDate() + 7);

        return events.map(event => {
            // Convert UTC times to EST/EDT
            const startTime = event.Calendly__EventStartTime__c ? new Date(event.Calendly__EventStartTime__c) : null;
            const endTime = event.Calendly__EventEndTime__c ? new Date(event.Calendly__EventEndTime__c) : null;

            // Get EST date for comparison
            const eventDate = startTime ? new Date(startTime.toLocaleString('en-US', { timeZone: 'America/New_York' })) : null;
            const eventDateOnly = eventDate ? new Date(eventDate.getFullYear(), eventDate.getMonth(), eventDate.getDate()) : null;

            // Calculate duration
            let duration = '';
            if (startTime && endTime) {
                const durationMinutes = Math.round((endTime - startTime) / 60000);
                duration = `${durationMinutes} min`;
            }

            // Determine date badge info
            let dateBadge = '';
            let dateVariant = 'default';
            if (eventDateOnly) {
                if (eventDateOnly.getTime() === today.getTime()) {
                    dateBadge = 'Today';
                    dateVariant = 'success';
                } else if (eventDateOnly.getTime() === tomorrow.getTime()) {
                    dateBadge = 'Tomorrow';
                    dateVariant = 'warning';
                } else if (eventDateOnly < nextWeek) {
                    dateBadge = this.getWeekdayName(eventDateOnly);
                    dateVariant = 'default';
                } else {
                    dateBadge = this.formatShortDate(eventDateOnly);
                    dateVariant = 'default';
                }
            }

            return {
                ...event,
                inviteeName: event.Calendly__InviteeName__c || 'Unknown Invitee',
                startTimeFormatted: startTime ? this.formatTime(startTime) : 'N/A',
                endTimeFormatted: endTime ? this.formatTime(endTime) : 'N/A',
                duration: duration,
                dateBadge: dateBadge,
                dateVariant: dateVariant,
                isToday: eventDateOnly && eventDateOnly.getTime() === today.getTime(),
                isTomorrow: eventDateOnly && eventDateOnly.getTime() === tomorrow.getTime()
            };
        });
    }

    formatTime(date) {
        // Format time in EST/EDT timezone
        return date.toLocaleTimeString('en-US', {
            timeZone: 'America/New_York',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    }

    formatShortDate(date) {
        return date.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric'
        });
    }

    getWeekdayName(date) {
        return date.toLocaleDateString('en-US', {
            weekday: 'long'
        });
    }

    get hasEvents() {
        return this.events && this.events.length > 0;
    }

    get showPreviewNote() {
        return this.totalEventsCount > 10;
    }

    handleEventClick(event) {
        const eventId = event.currentTarget.dataset.recordId;
        this.navigateToRecord(eventId);
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

    handleRefresh() {
        this.loadEvents();
    }
}