import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

export default class GlobalEmailNotifier extends NavigationMixin(LightningElement) {
    platformEventSub = null;
    
    connectedCallback() {
        console.log('🌍 Global Email Notifier: Initializing...');
        this.initializePlatformEventSubscription();
    }
    
    disconnectedCallback() {
        console.log('🌍 Global Email Notifier: Disconnecting...');
        if (this.platformEventSub) {
            unsubscribe(this.platformEventSub);
        }
    }
    
    initializePlatformEventSubscription() {
        console.log('🌍 📡 Global: Initializing Platform Event subscription...');
        
        // Set up error handling for empApi
        onError(err => console.error('🌍 empApi error', err));
        
        // Subscribe to New Email Platform Event
        subscribe('/event/New_Email_Event__e', -1, (evt) => {
            const payload = evt?.data?.payload;
            console.log('🌍 📡 Global: Platform Event received:', payload);
            
            // Only trigger for incoming emails
            if (payload?.Is_Incoming__c === true) {
                console.log('🌍 📡 🔔 Global: NEW INBOUND EMAIL PLATFORM EVENT');
                this.handleNewEmailGlobally(payload);
            }
        }).then(sub => { 
            this.platformEventSub = sub; 
            console.log('🌍 📡 ✅ Global: Successfully subscribed to New Email Platform Event:', sub);
        }).catch(error => {
            console.error('🌍 ❌ Global: Failed to subscribe to Platform Event:', error);
        });
    }
    
    async handleNewEmailGlobally(payload) {
        console.log('🌍 🔔 Global: Handling new email notification globally');
        
        try {
            // Show global toast notification
            this.dispatchEvent(new ShowToastEvent({
                title: 'New Email Received',
                message: `From: ${payload.From_Address__c || 'Unknown'} - ${payload.Email_Subject__c || 'No Subject'}`,
                variant: 'info',
                mode: 'sticky'
            }));
            
            console.log('🌍 🔔 Global toast notification dispatched');
            
            // Try multiple methods to open the utility bar
            await this.attemptUtilityAutoOpen();
            
        } catch (error) {
            console.error('🌍 ❌ Error in global email handler:', error);
        }
    }
    
    async attemptUtilityAutoOpen() {
        console.log('🌍 🔓 Global: Attempting to auto-open Email Inbox utility...');
        
        // Method 1: Try Navigation API to open utility
        try {
            await this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: {
                    componentName: 'c__emailInboxUtility'
                },
                state: {
                    c__autoOpen: 'true'
                }
            });
            console.log('🌍 🔓 ✅ Global: Utility opened via Navigation API');
            return;
        } catch (navError) {
            console.log('🌍 🔓 ⚠️ Global: Navigation API failed:', navError);
        }
        
        // Method 2: Try to navigate to Lightning App with utility open
        try {
            await this[NavigationMixin.Navigate]({
                type: 'standard__app',
                attributes: {
                    appTarget: 'standard__LightningConsole'
                },
                state: {
                    ws: '/lightning/page/home',
                    c__openEmailUtility: 'true'
                }
            });
            console.log('🌍 🔓 ✅ Global: Console app opened with utility parameter');
            return;
        } catch (appError) {
            console.log('🌍 🔓 ⚠️ Global: App navigation failed:', appError);
        }
        
        // Method 3: Dispatch global custom event for any listening components
        try {
            const globalOpenEvent = new CustomEvent('global_open_email_utility', {
                detail: {
                    source: 'globalNotifier',
                    timestamp: Date.now()
                },
                bubbles: true,
                composed: true
            });
            
            // Dispatch to multiple targets
            window.dispatchEvent(globalOpenEvent);
            document.dispatchEvent(globalOpenEvent);
            this.dispatchEvent(globalOpenEvent);
            
            console.log('🌍 🔓 ✅ Global: Auto-open events dispatched globally');
            
        } catch (eventError) {
            console.error('🌍 🔓 ❌ Global: Event dispatch failed:', eventError);
        }
        
        // Method 4: Try URL navigation as final fallback
        try {
            const currentUrl = window.location.href;
            const baseUrl = currentUrl.split('/lightning/')[0];
            const utilityUrl = `${baseUrl}/lightning/page/home?c__openEmailUtility=true`;
            
            // Small delay to let other methods complete first
            setTimeout(() => {
                if (window.location.href === currentUrl) { // Only navigate if still on same page
                    console.log('🌍 🔓 Final fallback: Navigating to URL with utility parameter');
                    window.location.href = utilityUrl;
                }
            }, 2000);
            
        } catch (urlError) {
            console.error('🌍 🔓 ❌ Global: URL navigation failed:', urlError);
        }
    }
}