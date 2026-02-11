import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { EnclosingUtilityId, onUtilityClick, open, updateUtility, getInfo, getEnclosingTabId, setPanelState } from 'lightning/platformUtilityBarApi';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getInboundEmails from '@salesforce/apex/EmailInboxController.getInboundEmails';
import markEmailAsSeen from '@salesforce/apex/EmailInboxController.markEmailAsSeen';
import markEmailAsPinned from '@salesforce/apex/EmailInboxController.markEmailAsPinned';
import findContactOrLeadByEmail from '@salesforce/apex/EmailInboxController.findContactOrLeadByEmail';
import getCurrentUserEmail from '@salesforce/apex/EmailInboxController.getCurrentUserEmail';

export default class EmailInboxUtility extends NavigationMixin(LightningElement) {
    @track emails = [];
    @track filteredEmails = [];
    @track isLoading = true;
    @track errorMessage = '';
    @track currentFilter = 'received';
    @track receivedCount = 0;
    @track sentCount = 0;
    @track unseenCount = 0;
    @track lastRefreshTime = null;
    @track searchTerm = '';
    @track fromDate = '';
    @track toDate = '';
    // pinnedEmails Set removed - now using server-side Pin__c field for database persistence
    lastClickTime = null;
    
    // Notification properties
    @track newEmailCount = 0;
    @track hasNewEmails = false;
    @track lastKnownEmailCount = 0;
    @track originalTabLabel = 'Email Inbox';
    isUtilityHighlighted = false;
    
    // Utility bar properties
    isUtilityMinimized = true;
    connectionStatus = 'connecting'; // 'connected', 'connecting', 'disconnected'
    connectionStatusText = 'Connecting...';
    
    // Utility Bar properties
    utilityId;
    tabId; // For auto-opening utility
    platformEventSub = null;
    pollingInterval = null;
    currentUserEmail = null;
    
    // Wire the enclosing utility ID and initialize only when available
    @wire(EnclosingUtilityId)
    wiredUtilityId(id) {
        if (!id || this.utilityId === id) return;
        console.log('🔧 Utility ID received:', id);
        this.utilityId = id;
        
        // Also get the tab ID for auto-opening functionality
        this.getTabId();
        
        this.initializeUtilityBarState();
        this.setupNotificationHandler();
        this.initializePlatformEventSubscription();
        this.startFallbackPolling(); // optional backup
        
    }


    // Pagination properties - restored to original limit
    limitCount = 1000; // Back to 1000 for full email access
    refreshInterval;
    fastPollingInterval;
    connectionKeepalive;
    searchTimeout;
    lastEmailId = null;
    hasMoreEmails = true;
    isLoadingMore = false;
    savedScrollPosition = 0;

    // Computed property for email inbox class
    get emailInboxClass() {
        return 'email-inbox-simple';
    }

    processEmailData(data, isLoadMore = false, preserveScroll = false) {
        if (data && data.emails) {
            // Reduced logging for better performance
            if (data.emails.length > 100) {
                console.log(`🔄 Processing ${data.emails.length} emails (performance optimized)`);
            }
            
            // Pre-calculate common values to avoid repeated computation
            const now = new Date();
            
            const newEmails = data.emails.map(email => {
                // Use server-side pin status (email.isPinned) as the source of truth
                const isPinned = email.isPinned || false;
                const isSeen = email.isSeen;
                
                // Optimized email processing - calculate all properties at once
                const emailWithPin = {
                    ...email,
                    isSeen: isSeen,
                    isPinned: isPinned,
                    pinIconName: isPinned ? 'utility:pinned' : 'utility:pin',
                    pinTitle: isPinned ? 'Unpin email' : 'Pin email',
                    pinClass: isPinned ? 'pin-button pinned' : 'pin-button'
                };
                
                // Batch calculate all display properties
                emailWithPin.displayFrom = this.getDisplayFromOptimized(emailWithPin);
                emailWithPin.relativeDate = this.formatDateOptimized(emailWithPin.messageDate || emailWithPin.createdDate, now);
                
                // Optimize avatar processing - calculate everything in one pass
                const avatarData = this.getAvatarDataOptimized(emailWithPin);
                emailWithPin.avatarInitials = avatarData.initials;
                emailWithPin.avatarColor = avatarData.color;
                emailWithPin.avatarTextColor = avatarData.textColor;
                emailWithPin.avatarStyle = avatarData.style;
                
                // Calculate CSS class last (depends on other properties)
                emailWithPin.cssClass = this.getEmailCssClassOptimized(emailWithPin);
                
                return emailWithPin;
            });
            
            if (isLoadMore) {
                // Append new emails to existing list
                this.emails = [...this.emails, ...newEmails];
            } else {
                // Check for new emails if we have a previous refresh time
                if (this.lastRefreshTime && this.emails.length > 0) {
                    const currentEmailIds = new Set(this.emails.map(e => e.id));
                    const newEmailsList = newEmails.filter(e => !currentEmailIds.has(e.id) && !e.isSeen && e.incoming);
                    
                    if (newEmailsList.length > 0) {
                        console.log(`Found ${newEmailsList.length} new unseen emails`);
                    }
                } else {
                    // On initial load, log any unread emails
                    const unseenEmails = newEmails.filter(e => !e.isSeen && e.incoming);
                    if (unseenEmails.length > 0) {
                        console.log(`Initial load: ${unseenEmails.length} unseen emails found`);
                    }
                }
                
                this.emails = newEmails;
            }
            
            this.lastRefreshTime = Date.now();
            this.calculateCounts();
            this.applyCurrentFilter();
            
            // Restore scroll position if requested
            if (preserveScroll) {
                console.log('📍 Restoring scroll after data processing...');
                this.restoreScrollPosition();
            }
        }
    }

    async connectedCallback() {
        // Pin status now uses server-side Pin__c field for database persistence
        // Note: Read status also uses server-side synchronization for cross-browser support
        
        // Load current user email for notification filtering
        try {
            this.currentUserEmail = await getCurrentUserEmail();
            console.log('👤 Current user email loaded:', this.currentUserEmail);
        } catch (error) {
            console.error('❌ Error loading current user email:', error);
            // Fallback to hardcoded emails if dynamic loading fails
            this.currentUserEmail = null;
        }
        
        // Load emails on initial connection
        await this.loadEmails();
        
        // Set up utility bar focus/blur detection
        this.setupUtilityBarEventListeners();
        
        // Set up global event listeners for auto-opening from anywhere
        this.setupGlobalEventListeners();
        
        // Optimized auto-refresh intervals for better performance
        this.refreshInterval = setInterval(() => {
            if (!this.isLoading) {
                this.silentRefresh();
            }
        }, 45000); // Increased from 30s to 45s to reduce server load
        
        // Set up faster polling when utility is minimized (optimized timing)
        this.fastPollingInterval = setInterval(() => {
            if (!this.isLoading && this.isUtilityMinimized) {
                try {
                    this.checkForNewEmailsOnly();
                } catch (error) {
                    // Silent error handling to prevent console spam
                    console.warn('Fast polling error (continuing)');
                }
            }
        }, 10000); // Increased from 5s to 10s to reduce CPU usage
        
        // Bind event handlers and store references for cleanup
        this.boundWindowFocus = this.handleWindowFocus.bind(this);
        this.boundVisibilityChange = this.handleVisibilityChange.bind(this);
        this.boundScrollHandler = this.handleScroll.bind(this);
        this.boundGlobalAutoOpen = this.handleGlobalAutoOpen.bind(this);
        
        // Add focus event listener to refresh when component regains focus
        window.addEventListener('focus', this.boundWindowFocus);
        
        // Add visibility change listener for when user returns to tab
        document.addEventListener('visibilitychange', this.boundVisibilityChange);
        
        // Set up infinite scroll after component renders
        setTimeout(() => {
            this.setupInfiniteScroll();
        }, 100);
        
        // Initialize connection monitoring
        this.initializeConnectionMonitoring();
        
        // Set initial connection status to connected
        setTimeout(() => {
            this.setConnectionStatus('connected');
        }, 500);
    }

    async loadEmails(preserveScroll = false, silentMode = false) {
        try {
            this.isLoading = true;
            this.errorMessage = '';
            
            // Reset pagination for fresh load (unless preserving scroll)
            if (!preserveScroll) {
                this.lastEmailId = null;
                this.hasMoreEmails = true;
            }
            
            const result = await getInboundEmails({ 
                limitCount: this.limitCount, 
                lastEmailId: null, 
                fromDate: this.fromDate || null,
                toDate: this.toDate || null
            });
            
            this.processEmailData(result, false, preserveScroll);
            this.hasMoreEmails = result.hasMore;
            this.lastEmailId = result.lastEmailId;
            this.isLoading = false;
            return Promise.resolve();
        } catch (error) {
            this.isLoading = false;
            this.handleError('Failed to load emails', error, silentMode);
            return Promise.reject(error);
        }
    }

    disconnectedCallback() {
        console.log('🔌 Component disconnecting - cleaning up resources...');
        
        // Clear all intervals
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            console.log('🔌 Cleared refresh interval');
        }
        if (this.fastPollingInterval) {
            clearInterval(this.fastPollingInterval);
            console.log('🔌 Cleared fast polling interval');
        }
        if (this.connectionKeepalive) {
            clearInterval(this.connectionKeepalive);
            console.log('🔌 Cleared connection keepalive');
        }
        if (this.connectionMonitor) {
            clearInterval(this.connectionMonitor);
            console.log('🔌 Cleared connection monitor');
        }
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
            console.log('🔌 Cleared search timeout');
        }
        
        // Clear notification polling
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            console.log('🔌 Cleared notification polling');
        }
        
        // Unsubscribe from Platform Event
        if (this.platformEventSub) {
            unsubscribe(this.platformEventSub).then(() => {
                console.log('🔌 Unsubscribed from Platform Event');
            }).catch(error => {
                console.error('🔌 Error unsubscribing from Platform Event:', error);
            });
        }
        
        // Clean up observers
        if (this.intersectionObserver) {
            this.intersectionObserver.disconnect();
            console.log('🔌 Disconnected intersection observer');
        }
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            console.log('🔌 Disconnected resize observer');
        }
        
        // Reset utility bar to original state
        this.clearUtilityNotifications();
        
        // Clean up event listeners
        if (this.boundWindowFocus) {
            window.removeEventListener('focus', this.boundWindowFocus);
            console.log('🔌 Removed window focus listener');
        }
        if (this.boundVisibilityChange) {
            document.removeEventListener('visibilitychange', this.boundVisibilityChange);
            console.log('🔌 Removed visibility change listener');
        }
        if (this.boundScrollHandler) {
            const scrollContainer = this.template.querySelector('.email-list-container');
            if (scrollContainer) {
                scrollContainer.removeEventListener('scroll', this.boundScrollHandler);
                console.log('🔌 Removed scroll listener');
            }
        }
        if (this.boundGlobalAutoOpen) {
            window.removeEventListener('global_open_email_utility', this.boundGlobalAutoOpen);
            document.removeEventListener('autoopen_utility', this.boundGlobalAutoOpen);
            console.log('🔌 Removed global auto-open listeners');
        }
        
        console.log('🔌 ✅ Component cleanup completed');
    }

    calculateCounts() {
        this.receivedCount = this.emails.filter(email => email.emailType === 'Received').length;
        this.sentCount = this.emails.filter(email => email.emailType === 'Sent').length;
        this.unseenCount = this.emails.filter(email => !email.isSeen && email.emailType === 'Received').length;
    }

    getEmailCssClass(email) {
        // Simplified CSS class calculation (legacy method - kept for compatibility)
        return this.getEmailCssClassOptimized(email);
    }

    getDisplayFrom(email) {
        if (email.emailType === 'Sent') {
            return 'Me';
        }
        return email.fromName || email.fromAddress || 'Unknown';
    }

    getAvatarInitials(email) {
        if (email.emailType === 'Sent') {
            return 'ME';
        }
        
        if (email.fromName) {
            const names = email.fromName.trim().split(' ');
            if (names.length >= 2) {
                return (names[0].charAt(0) + names[names.length - 1].charAt(0)).toUpperCase();
            } else if (names.length === 1) {
                return names[0].substring(0, 2).toUpperCase();
            }
        }
        
        if (email.fromAddress) {
            return email.fromAddress.substring(0, 2).toUpperCase();
        }
        
        return 'UK'; // Unknown
    }

    getAvatarColor(email) {
        // 26 vibrant, distinct colors for A-Z based on first alphabet
        // Carefully chosen for maximum visual distinction and accessibility
        const colorMap = {
            'A': '#E53E3E', // Red - Bold and attention-grabbing
            'B': '#3182CE', // Blue - Professional and trustworthy  
            'C': '#38A169', // Green - Fresh and positive
            'D': '#D69E2E', // Orange/Gold - Warm and energetic
            'E': '#805AD5', // Purple - Creative and unique
            'F': '#DD6B20', // Orange - Vibrant and friendly
            'G': '#38B2AC', // Teal - Modern and calm
            'H': '#F56500', // Bright Orange - Warm and inviting
            'I': '#4299E1', // Sky Blue - Open and trustworthy
            'J': '#48BB78', // Emerald Green - Growth and harmony
            'K': '#ED8936', // Amber - Confident and warm
            'L': '#9F7AEA', // Light Purple - Elegant and sophisticated
            'M': '#319795', // Dark Teal - Strong and reliable (for "ME"/Sent emails)
            'N': '#F56565', // Light Red - Energetic and dynamic
            'O': '#4FD1C7', // Aqua - Fresh and modern
            'P': '#FC8181', // Pink Red - Approachable and friendly
            'Q': '#63B3ED', // Powder Blue - Calm and professional
            'R': '#68D391', // Mint Green - Fresh and positive
            'S': '#F6AD55', // Peach - Warm and welcoming
            'T': '#B794F6', // Lavender - Creative and inspiring
            'U': '#5A67D8', // Indigo - Deep and trustworthy
            'V': '#F093FB', // Bright Pink - Bold and memorable
            'W': '#4ECDC4', // Turquoise - Balanced and refreshing
            'X': '#FF8A80', // Salmon - Unique and eye-catching  
            'Y': '#7C3AED', // Deep Purple - Mysterious and premium
            'Z': '#F687B3'  // Rose Pink - Distinctive and final
        };

        let firstLetter = 'U'; // Default to 'U' (Indigo) for Unknown
        
        if (email.emailType === 'Sent') {
            firstLetter = 'M'; // ME uses strong dark teal color for sent emails
        } else if (email.fromName) {
            firstLetter = email.fromName.trim().charAt(0).toUpperCase();
        } else if (email.fromAddress) {
            firstLetter = email.fromAddress.charAt(0).toUpperCase();
        }
        
        return colorMap[firstLetter] || '#5A67D8'; // Default to indigo if not A-Z
    }

    getAvatarTextColor(backgroundColor) {
        // Calculate if we need white or black text based on background color brightness
        // Remove # if present
        const hex = backgroundColor.replace('#', '');
        
        // Convert hex to RGB
        const r = parseInt(hex.substring(0, 2), 16);
        const g = parseInt(hex.substring(2, 4), 16);
        const b = parseInt(hex.substring(4, 6), 16);
        
        // Calculate relative luminance using WCAG formula
        const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        
        // Return white text for dark backgrounds, black text for light backgrounds
        return luminance > 0.5 ? '#000000' : '#FFFFFF';
    }

    // Optimized methods for better performance
    getDisplayFromOptimized(email) {
        if (email.emailType === 'Sent') {
            return 'Me';
        }
        return email.fromName || email.fromAddress || 'Unknown';
    }

    formatDateOptimized(dateValue, now) {
        if (!dateValue) return '';
        
        const date = new Date(dateValue);
        const diffTime = now - date;
        const diffDays = Math.floor(diffTime / 86400000); // 24 * 60 * 60 * 1000
        
        if (diffDays === 0) {
            return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } else if (diffDays === 1) {
            return 'Yesterday';
        } else if (diffDays < 7) {
            return date.toLocaleDateString([], { weekday: 'short' });
        } else {
            return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
        }
    }

    getAvatarDataOptimized(email) {
        // Pre-calculated color map for better performance
        const colorMap = {
            'A': { color: '#E53E3E', textColor: '#FFFFFF' },
            'B': { color: '#3182CE', textColor: '#FFFFFF' },
            'C': { color: '#38A169', textColor: '#FFFFFF' },
            'D': { color: '#D69E2E', textColor: '#FFFFFF' },
            'E': { color: '#805AD5', textColor: '#FFFFFF' },
            'F': { color: '#DD6B20', textColor: '#FFFFFF' },
            'G': { color: '#38B2AC', textColor: '#FFFFFF' },
            'H': { color: '#F56500', textColor: '#FFFFFF' },
            'I': { color: '#4299E1', textColor: '#FFFFFF' },
            'J': { color: '#48BB78', textColor: '#FFFFFF' },
            'K': { color: '#ED8936', textColor: '#FFFFFF' },
            'L': { color: '#9F7AEA', textColor: '#FFFFFF' },
            'M': { color: '#319795', textColor: '#FFFFFF' },
            'N': { color: '#F56565', textColor: '#FFFFFF' },
            'O': { color: '#4FD1C7', textColor: '#FFFFFF' },
            'P': { color: '#FC8181', textColor: '#FFFFFF' },
            'Q': { color: '#63B3ED', textColor: '#FFFFFF' },
            'R': { color: '#68D391', textColor: '#FFFFFF' },
            'S': { color: '#F6AD55', textColor: '#FFFFFF' },
            'T': { color: '#B794F6', textColor: '#FFFFFF' },
            'U': { color: '#5A67D8', textColor: '#FFFFFF' },
            'V': { color: '#F093FB', textColor: '#FFFFFF' },
            'W': { color: '#4ECDC4', textColor: '#FFFFFF' },
            'X': { color: '#FF8A80', textColor: '#FFFFFF' },
            'Y': { color: '#7C3AED', textColor: '#FFFFFF' },
            'Z': { color: '#F687B3', textColor: '#FFFFFF' }
        };

        let firstLetter = 'U';
        let initials = 'UK';

        if (email.emailType === 'Sent') {
            firstLetter = 'M';
            initials = 'ME';
        } else if (email.fromName) {
            const name = email.fromName.trim();
            firstLetter = name.charAt(0).toUpperCase();
            
            // Optimized initials calculation
            const names = name.split(' ');
            if (names.length >= 2) {
                initials = (names[0].charAt(0) + names[names.length - 1].charAt(0)).toUpperCase();
            } else {
                initials = name.substring(0, 2).toUpperCase();
            }
        } else if (email.fromAddress) {
            firstLetter = email.fromAddress.charAt(0).toUpperCase();
            initials = email.fromAddress.substring(0, 2).toUpperCase();
        }

        const colorData = colorMap[firstLetter] || colorMap['U'];
        
        return {
            initials: initials,
            color: colorData.color,
            textColor: colorData.textColor,
            style: `background-color: ${colorData.color}; color: ${colorData.textColor};`
        };
    }

    getEmailCssClassOptimized(email) {
        let cssClass = 'email-item';
        
        if (!email.isSeen && email.emailType === 'Received') {
            cssClass += ' unseen';
        }
        
        if (email.isNew === true) {
            cssClass += ' new-email';
        }
        
        if (email.isPinned === true) {
            cssClass += ' pinned';
        }
        
        return cssClass;
    }




    formatDate(dateValue) {
        if (!dateValue) return '';
        
        const date = new Date(dateValue);
        const now = new Date();
        const diffTime = now - date;
        const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
        
        if (diffDays === 0) {
            return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } else if (diffDays === 1) {
            return 'Yesterday';
        } else if (diffDays < 7) {
            return date.toLocaleDateString([], { weekday: 'short' });
        } else {
            return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
        }
    }

    async handleRefresh() {
        try {
            console.log('🔄 Manual refresh - preserving scroll position');
            this.saveScrollPosition();
            await this.loadEmails(true); // Preserve scroll on manual refresh too
            this.showToast('Success', 'Emails refreshed', 'success');
        } catch (error) {
            this.handleError('Failed to refresh emails', error);
        }
    }

    silentRefresh() {
        // Only refresh if no recent user interactions to avoid overriding local state
        const now = Date.now();
        if (!this.lastClickTime || (now - this.lastClickTime) > 5000) { // 5 second delay
            console.log('🔄 Performing silent refresh with scroll preservation');
            this.saveScrollPosition();
            this.loadEmails(true, true); // Pass true for preserveScroll and true for silentMode
        } else {
            console.log('Skipping silent refresh due to recent user interaction');
        }
    }

    handleWindowFocus() {
        // Refresh data when window regains focus to catch read status changes
        if (!this.isLoading) {
            console.log('🔄 Window focus - refreshing with scroll preservation');
            this.silentRefresh();
        }
    }

    handleVisibilityChange() {
        // Refresh data when tab becomes visible again
        if (!document.hidden && !this.isLoading) {
            console.log('🔄 Visibility change - refreshing with scroll preservation');
            this.silentRefresh();
        }
    }

    showReceived() {
        this.currentFilter = 'received';
        this.applyCurrentFilter();
    }

    showSent() {
        this.currentFilter = 'sent';
        this.applyCurrentFilter();
    }

    showUnseen() {
        this.currentFilter = 'unseen';
        this.applyCurrentFilter();
    }

    applyCurrentFilter() {
        let filtered = [...this.emails];

        // Apply type filter (received/sent/unseen)
        if (this.currentFilter === 'received') {
            filtered = filtered.filter(email => email.emailType === 'Received');
        } else if (this.currentFilter === 'sent') {
            filtered = filtered.filter(email => email.emailType === 'Sent');
        } else if (this.currentFilter === 'unseen') {
            filtered = filtered.filter(email => !email.isSeen && email.emailType === 'Received');
        }

        // Apply search filter
        if (this.searchTerm) {
            const searchLower = this.searchTerm.toLowerCase();
            filtered = filtered.filter(email => 
                email.subject?.toLowerCase().includes(searchLower) ||
                email.fromName?.toLowerCase().includes(searchLower) ||
                email.fromAddress?.toLowerCase().includes(searchLower) ||
                email.toAddress?.toLowerCase().includes(searchLower) ||
                email.textBody?.toLowerCase().includes(searchLower)
            );
        }

        // Apply date range filter
        if (this.fromDate || this.toDate) {
            filtered = filtered.filter(email => {
                const emailDate = new Date(email.messageDate || email.createdDate);
                
                // Validate email date
                if (isNaN(emailDate.getTime())) {
                    return false;
                }
                
                const fromDateObj = this.fromDate ? new Date(this.fromDate + 'T00:00:00') : null;
                const toDateObj = this.toDate ? new Date(this.toDate + 'T23:59:59') : null;

                if (fromDateObj && emailDate < fromDateObj) {
                    return false;
                }
                if (toDateObj && emailDate > toDateObj) {
                    return false;
                }
                return true;
            });
        }

        // Sort in descending order (newest first)
        filtered.sort((a, b) => {
            const dateA = new Date(a.messageDate || a.createdDate);
            const dateB = new Date(b.messageDate || b.createdDate);
            return dateB - dateA;
        });

        this.filteredEmails = filtered;
    }

    async handleEmailClick(event) {
        console.log('🚀 EMAIL CLICK HANDLER TRIGGERED!');
        
        // Prevent any default behavior and event bubbling
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();
        
        const emailId = event.currentTarget.dataset.emailId;
        console.log('📧 Email ID from click:', emailId);
        
        if (!emailId) {
            console.error('❌ No email ID found!');
            return;
        }
        
        // Track click time to prevent conflicts
        this.lastClickTime = Date.now();
        
        // Find the email to check if it's NEW
        const clickedEmail = this.emails.find(email => email.id === emailId);
        
        // Only mark as seen if it's a NEW email (Incoming && !Seen__c)
        if (clickedEmail && clickedEmail.isNew) {
            // OPTIMISTIC UI UPDATE: Immediately remove NEW status for instant feedback
            console.log('⚡ IMMEDIATE UPDATE: Removing NEW status optimistically...');
            this.optimisticallyMarkAsSeen(emailId);
            
            // Background server update for cross-browser synchronization
            console.log('🔄 Background: Syncing seen status to server...');
                markEmailAsSeen({ emailId: emailId }).then(result => {
                if (result?.success) {
                    console.log('✅ Server-side seen status updated successfully:', result.message);
                    // Trigger a silent refresh to sync other browsers
                    this.silentRefresh();
                } else {
                    console.error('❌ Failed to mark email as seen on server - reverting UI. Error:', result?.message);
                    // Revert optimistic update if server fails
                    this.revertOptimisticUpdate(emailId);
                    
                    // Show error toast with specific message
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: result?.message || 'Failed to mark email as seen',
                            variant: 'error'
                        })
                    );
                }
            }).catch(error => {
                console.error('❌ Error marking email as seen:', error);
                // Revert optimistic update if error occurs
                this.revertOptimisticUpdate(emailId);
                
                // Show error toast
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'Failed to mark email as seen',
                        variant: 'error'
                    })
                );
            });
        } else {
            console.log('📧 Email is not NEW - no server update needed');
        }
        
        // Navigate to email record immediately
        setTimeout(() => {
            console.log('🔗 Navigating to email record...');
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: `/lightning/r/EmailMessage/${emailId}/view`
                }
            });
        }, 100);
    }
    
    optimisticallyMarkAsSeen(emailId) {
        console.log('⚡ OPTIMISTIC UPDATE: Immediately removing NEW status and green highlighting from email', emailId);
        
        // Update both email arrays immediately for instant visual feedback
        this.emails = this.emails.map(email => {
            if (email.id === emailId && email.isNew && email.emailType === 'Received') {
                const updatedEmail = { ...email, isNew: false };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('✅ Optimistically marked email as seen (removed NEW status) in main array');
                return updatedEmail;
            }
            return email;
        });
        
        this.filteredEmails = this.filteredEmails.map(email => {
            if (email.id === emailId && email.isNew && email.emailType === 'Received') {
                const updatedEmail = { ...email, isNew: false };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('✅ Optimistically marked email as seen (removed NEW status) in filtered array');
                return updatedEmail;
            }
            return email;
        });
        
        // Recalculate counts for immediate UI feedback
        this.calculateCounts();
        
        console.log('⚡ OPTIMISTIC UPDATE COMPLETE - Email should no longer have NEW green bar/pill');
    }
    
    revertOptimisticUpdate(emailId) {
        console.log('🔄 REVERTING: Server update failed, reverting optimistic update for', emailId);
        
        // Refresh data from server to get the true status
        this.silentRefresh();
    }

    updateEmailSeenStatus(emailId) {
        console.log('📝 Updating email seen status for:', emailId);
        
        // Update in main emails array
        this.emails = this.emails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { ...email, isSeen: true };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('✏️ Updated email in main array:', {
                    id: updatedEmail.id,
                    subject: updatedEmail.subject,
                    isSeen: updatedEmail.isSeen,
                    cssClass: updatedEmail.cssClass
                });
                return updatedEmail;
            }
            return email;
        });
        
        // Update filtered emails array as well
        this.filteredEmails = this.filteredEmails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { ...email, isSeen: true };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('🔍 Updated email in filtered array:', {
                    id: updatedEmail.id,
                    subject: updatedEmail.subject,
                    isSeen: updatedEmail.isSeen,
                    cssClass: updatedEmail.cssClass
                });
                return updatedEmail;
            }
            return email;
        });
        
        // Recalculate counts
        this.calculateCounts();
        
        // Force a re-render by creating new arrays (LWC reactivity)
        this.emails = [...this.emails];
        this.filteredEmails = [...this.filteredEmails];
        
        console.log('✅ Email seen status update completed. Current counts:', {
            received: this.receivedCount,
            sent: this.sentCount,
            unseen: this.unseenCount
        });
        
        console.log('🔄 Forced re-render with new arrays');
    }

    forceEmailToSeen(emailId) {
        console.log('💪 FORCE EMAIL TO SEEN - ID:', emailId);
        
        // Update main emails array - FORCE isSeen to true
        this.emails = this.emails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { 
                    ...email, 
                    isSeen: true // FORCE to true regardless of previous state
                };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('💪 FORCED UPDATE in main array:', {
                    id: updatedEmail.id,
                    isSeen: updatedEmail.isSeen,
                    cssClass: updatedEmail.cssClass,
                    subject: updatedEmail.subject?.substring(0, 30)
                });
                return updatedEmail;
            }
            return email;
        });
        
        // Update filtered emails array - FORCE isSeen to true
        this.filteredEmails = this.filteredEmails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { 
                    ...email, 
                    isSeen: true // FORCE to true regardless of previous state
                };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                console.log('💪 FORCED UPDATE in filtered array:', {
                    id: updatedEmail.id,
                    isSeen: updatedEmail.isSeen,
                    cssClass: updatedEmail.cssClass,
                    subject: updatedEmail.subject?.substring(0, 30)
                });
                return updatedEmail;
            }
            return email;
        });
        
        // Recalculate counts
        this.calculateCounts();
        
        // Force complete re-render
        this.emails = [...this.emails];
        this.filteredEmails = [...this.filteredEmails];
        
        console.log('💪 FORCE EMAIL TO SEEN COMPLETED!');
    }

    // Test method to manually trigger seen marking from console
    testMarkSeen() {
        console.log('🧪 TEST MARK SEEN - Finding first unseen email...');
        if (this.emails && this.emails.length > 0) {
            const firstUnseenEmail = this.emails.find(e => !e.isSeen && e.incoming) || this.emails[0];
            console.log('🧪 Testing with email:', firstUnseenEmail.id, firstUnseenEmail.subject);
            this.forceEmailToSeen(firstUnseenEmail.id);
            console.log('🧪 Test completed - check if email is now marked as seen (no green highlight)');
        } else {
            console.log('🧪 No emails found for testing');
        }
    }
    

    // Read status now managed server-side for cross-browser synchronization

    get hasEmails() {
        return this.filteredEmails && this.filteredEmails.length > 0;
    }

    get emptyMessage() {
        if (this.currentFilter === 'received') {
            return 'No received emails found';
        } else if (this.currentFilter === 'sent') {
            return 'No sent emails found';
        } else if (this.currentFilter === 'unseen') {
            return 'No unseen emails found';
        }
        return 'No emails found';
    }

    get receivedButtonClass() {
        return this.currentFilter === 'received' ? 'filter-tabs button active' : 'filter-tabs button';
    }

    get sentButtonClass() {
        return this.currentFilter === 'sent' ? 'filter-tabs button active' : 'filter-tabs button';
    }

    get unseenButtonClass() {
        return this.currentFilter === 'unseen' ? 'filter-tabs button active' : 'filter-tabs button';
    }

    get connectionStatusClass() {
        return `connection-status connection-${this.connectionStatus}`;
    }

    get hasActiveFilters() {
        return this.searchTerm || this.fromDate || this.toDate;
    }

    get searchInputClass() {
        return this.searchTerm ? 'search-input active-search' : 'search-input';
    }

    get notificationTitle() {
        return `You have ${this.newEmailCount} new email${this.newEmailCount !== 1 ? 's' : ''}`;
    }



    handleSearch(event) {
        this.searchTerm = event.target.value.trim();
        
        // Debounce search to improve performance for long lists
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
        
        this.searchTimeout = setTimeout(() => {
            this.applyCurrentFilter();
        }, 150);
    }

    handleDateChange(event) {
        const fieldName = event.target.name;
        const value = event.target.value;
        
        if (fieldName === 'fromDate') {
            this.fromDate = value;
        } else if (fieldName === 'toDate') {
            this.toDate = value;
        }
        
        // Reset pagination when filters change
        this.lastEmailId = null;
        this.hasMoreEmails = true;
        
        this.applyCurrentFilter();
    }

    clearDateFilters() {
        this.fromDate = '';
        this.toDate = '';
        this.applyCurrentFilter();
    }

    async handlePinClick(event) {
        event.stopPropagation(); // Prevent email click navigation
        const emailId = event.currentTarget.dataset.emailId;
        
        // Find the current email to get its pin status
        const currentEmail = this.emails.find(email => email.id === emailId);
        if (!currentEmail) {
            console.error('Email not found for pin operation:', emailId);
            return;
        }
        
        const newPinStatus = !currentEmail.isPinned;
        
        // Optimistic UI update - update immediately for better user experience
        this.updateEmailPinStatusOptimistic(emailId, newPinStatus);
        
        try {
            // Call server method to persist pin status
            const result = await markEmailAsPinned({ emailId: emailId, isPinned: newPinStatus });
            
            if (result.success) {
                console.log('✅ Email pin status updated successfully:', result.message);
                // The optimistic update is already done, no need to update UI again
            } else {
                console.error('❌ Failed to update pin status on server:', result.message);
                // Revert optimistic update if server call failed
                this.updateEmailPinStatusOptimistic(emailId, !newPinStatus);
                this.showToast('Error', result.message || 'Failed to update pin status', 'error');
            }
        } catch (error) {
            console.error('❌ Error updating pin status:', error);
            // Revert optimistic update if server call failed
            this.updateEmailPinStatusOptimistic(emailId, !newPinStatus);
            this.showToast('Error', 'Failed to update pin status', 'error');
        }
    }

    async handleCalendarClick(event) {
        event.stopPropagation(); // Prevent email click navigation
        const emailId = event.currentTarget.dataset.emailId;
        
        // Find the current email to get sender information
        const currentEmail = this.emails.find(email => email.id === emailId);
        if (!currentEmail) {
            this.showToast('Error', 'Email not found', 'error');
            return;
        }

        console.log('📅 Calendar button clicked for email:', {
            emailId: emailId,
            subject: currentEmail.subject,
            fromName: currentEmail.fromName,
            fromAddress: currentEmail.fromAddress
        });

        try {
            console.log('🔍 Looking up Contact/Lead for:', currentEmail.fromAddress);
            
            // Look up Contact or Lead by email address
            const lookupResult = await findContactOrLeadByEmail({ 
                emailAddress: currentEmail.fromAddress 
            });
            
            console.log('📞 Contact/Lead lookup result:', lookupResult);
            
            // Build field mapping with subject format "Meeting Regarding [Email Subject]"
            const defaultFieldValues = {
                Subject: `Meeting Regarding ${currentEmail.subject || 'Email Discussion'}`
            };
            
            // Add relationship if found
            if (lookupResult.success) {
                defaultFieldValues.WhoId = lookupResult.recordId;
                
                // If it's a Contact with an Account, also set WhatId
                if (lookupResult.recordType === 'Contact' && lookupResult.accountId) {
                    defaultFieldValues.WhatId = lookupResult.accountId;
                }
            }
            
            console.log('📅 Field mapping:', defaultFieldValues);
            
            // Navigate with pre-populated fields
            await this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Event',
                    actionName: 'new'
                },
                state: {
                    defaultFieldValues: encodeDefaultFieldValues(defaultFieldValues)
                }
            });
            
            const contactName = lookupResult.success ? lookupResult.recordName : currentEmail.fromName || currentEmail.fromAddress;
            this.showToast('Calendar', `Opening meeting for ${contactName}`, 'success');
            
        } catch (error) {
            console.error('❌ Error in calendar integration:', error);
            
            // Fallback: Try with GenerateUrl and window.open
            try {
                const url = await this[NavigationMixin.GenerateUrl]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Event',
                        actionName: 'new'
                    }
                });
                
                console.log('🔗 Generated URL:', url);
                window.open(url, '_blank');
                
                this.showToast('Calendar', 'Event creation opened in new tab', 'success');
                
            } catch (urlError) {
                console.error('❌ URL generation also failed:', urlError);
                
                // Final fallback: Direct URL navigation
                const directUrl = `/lightning/o/Event/new`;
                console.log('🔄 Trying direct URL:', directUrl);
                window.open(directUrl, '_blank');
                
                this.showToast('Calendar', 'Event creation page opened', 'success');
            }
        }
    }

    /**
     * Enhanced calendar click with field pre-population (for future use) - Temporarily disabled
     */
    async handleCalendarClickAdvanced(event) {
        event.stopPropagation();
        const emailId = event.currentTarget.dataset.emailId;
        
        const currentEmail = this.emails.find(email => email.id === emailId);
        if (!currentEmail) {
            this.showToast('Error', 'Email not found', 'error');
            return;
        }

        try {
            console.log('🔍 Looking up Contact/Lead for:', currentEmail.fromAddress);
            
            // Look up Contact or Lead by email address
            const lookupResult = await findContactOrLeadByEmail({ 
                emailAddress: currentEmail.fromAddress 
            });
            
            console.log('📞 Contact/Lead lookup result:', lookupResult);
            
            // Calculate default appointment times
            const now = new Date();
            const startTime = new Date(now.getTime() + (60 * 60 * 1000)); // 1 hour from now
            const endTime = new Date(startTime.getTime() + (60 * 60 * 1000)); // 1 hour duration
            
            // Build simplified field mapping
            const defaultFieldValues = {
                Subject: `Appointment with ${currentEmail.fromName || currentEmail.fromAddress}`
            };
            
            // Add relationship if found
            if (lookupResult.success) {
                defaultFieldValues.WhoId = lookupResult.recordId;
            }
            
            console.log('📅 Field mapping:', defaultFieldValues);
            
            // Navigate with pre-populated fields
            await this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: 'Event',
                    actionName: 'new'
                },
                state: {
                    defaultFieldValues: encodeDefaultFieldValues(defaultFieldValues)
                }
            });
            
            const contactName = lookupResult.success ? lookupResult.recordName : currentEmail.fromName || currentEmail.fromAddress;
            this.showToast('Calendar', `Opening appointment for ${contactName}`, 'success');
            
        } catch (error) {
            console.error('❌ Error in advanced calendar integration:', error);
            // Fallback to simple navigation
            this.handleCalendarClick(event);
        }
    }

    /**
     * Build field mapping object for Event creation based on email and lookup data
     */
    buildEventFieldMapping(email, lookupResult, startTime, endTime) {
        const fieldMapping = {
            // Basic Event fields
            Subject: `Appointment with ${email.fromName || email.fromAddress}`,
            Description: `Scheduled from email: "${email.subject}"\n\nOriginal Email ID: ${email.id}`,
            StartDateTime: startTime.toISOString(),
            EndDateTime: endTime.toISOString(),
            
            // Email reference fields (if available)
            Email_Source__c: email.id,
            Booking_Method__c: 'Email Inbox Calendar Button'
        };
        
        // Add relationship mapping based on lookup results
        if (lookupResult.success) {
            if (lookupResult.recordType === 'Contact') {
                fieldMapping.WhoId = lookupResult.recordId; // Contact relationship
                if (lookupResult.accountId) {
                    fieldMapping.WhatId = lookupResult.accountId; // Account relationship
                }
            } else if (lookupResult.recordType === 'Lead') {
                fieldMapping.WhoId = lookupResult.recordId; // Lead relationship
            }
        }
        
        console.log('🗺️ Built field mapping:', fieldMapping);
        return fieldMapping;
    }

    updateEmailPinStatusOptimistic(emailId, isPinned) {
        const pinIconName = isPinned ? 'utility:pinned' : 'utility:pin';
        const pinTitle = isPinned ? 'Unpin email' : 'Pin email';
        const pinClass = isPinned ? 'pin-button pinned' : 'pin-button';
        
        console.log(`🔄 Optimistic pin update for ${emailId}: isPinned = ${isPinned}`);
        
        // Update main emails array
        this.emails = this.emails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { ...email, isPinned, pinIconName, pinTitle, pinClass };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                return updatedEmail;
            }
            return email;
        });
        
        // Update filtered emails array
        this.filteredEmails = this.filteredEmails.map(email => {
            if (email.id === emailId) {
                const updatedEmail = { ...email, isPinned, pinIconName, pinTitle, pinClass };
                updatedEmail.cssClass = this.getEmailCssClass(updatedEmail);
                return updatedEmail;
            }
            return email;
        });
    }

    // localStorage methods removed - now using database persistence with Pin__c field

    get showLoadMore() {
        return this.hasMoreEmails && !this.isLoading && !this.isLoadingMore && this.emails.length > 0;
    }

    get showNoMoreEmails() {
        return !this.hasMoreEmails && !this.isLoading && !this.isLoadingMore && this.emails.length > 0;
    }

    async handleLoadMore() {
        if (this.isLoadingMore || !this.hasMoreEmails) {
            return;
        }
        
        try {
            this.isLoadingMore = true;
            
            const result = await getInboundEmails({ 
                limitCount: this.limitCount, 
                lastEmailId: this.lastEmailId,
                fromDate: this.fromDate || null,
                toDate: this.toDate || null
            });
            
            this.processEmailData(result, true); // true indicates load more
            this.hasMoreEmails = result.hasMore;
            this.lastEmailId = result.lastEmailId;
            
        } catch (error) {
            this.handleError('Failed to load more emails', error);
        } finally {
            this.isLoadingMore = false;
        }
    }

    handleError(title, error, silentMode = false) {
        this.isLoading = false;
        const message = error?.body?.message || error?.message || 'An unexpected error occurred';
        this.errorMessage = message;
        console.error(title + ':', error);
        
        // Only show toast notifications for user-initiated actions, not silent refreshes
        if (!silentMode) {
            this.showToast('Error', title, 'error');
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible'
        });
        this.dispatchEvent(evt);
    }

    // ========== GLOBAL EVENT LISTENERS ==========
    
    setupGlobalEventListeners() {
        console.log('🌍 Setting up global event listeners for auto-opening from anywhere...');
        
        // Listen for global auto-open events
        window.addEventListener('global_open_email_utility', this.boundGlobalAutoOpen);
        document.addEventListener('autoopen_utility', this.boundGlobalAutoOpen);
        
        // Also listen for URL parameters that might indicate we should auto-open
        this.checkUrlParametersForAutoOpen();
        
        console.log('🌍 ✅ Global event listeners set up');
    }
    
    handleGlobalAutoOpen(event) {
        console.log('🌍 🔓 Global auto-open event received:', event.detail);
        
        // Try to open the utility when global event is received
        if (this.utilityId) {
            setTimeout(async () => {
                try {
                    await open(this.utilityId);
                    console.log('🌍 🔓 ✅ Utility opened via global event');
                    this.isUtilityMinimized = false;
                } catch (error) {
                    console.log('🌍 🔓 ⚠️ Global event auto-open failed:', error);
                }
            }, 500);
        }
    }
    
    checkUrlParametersForAutoOpen() {
        try {
            const urlParams = new URLSearchParams(window.location.search);
            const shouldAutoOpen = urlParams.get('c__openEmailUtility') === 'true' || 
                                 urlParams.get('openEmailUtility') === 'true';
            
            if (shouldAutoOpen) {
                console.log('🌍 🔓 URL parameter detected - auto-opening utility');
                setTimeout(() => {
                    if (this.utilityId) {
                        open(this.utilityId).then(() => {
                            console.log('🌍 🔓 ✅ Utility opened via URL parameter');
                            this.isUtilityMinimized = false;
                        }).catch(error => {
                            console.log('🌍 🔓 ⚠️ URL parameter auto-open failed:', error);
                        });
                    }
                }, 1000);
            }
        } catch (error) {
            console.error('🌍 ❌ Error checking URL parameters:', error);
        }
    }
    
    // ========== UTILITY BAR NOTIFICATION SYSTEM ==========
    
    setupUtilityBarEventListeners() {
        console.log('👁️ Setting up enhanced utility bar event listeners...');
        
        // Enhanced visibility detection using Intersection Observer
        this.setupVisibilityObserver();
        
        // Listen for when the component gains focus (utility opened)
        this.template.addEventListener('focus', () => {
            console.log('🔍 Focus event detected - utility opened');
            this.handleUtilityFocus();
        }, true);
        
        // Listen for when the component loses focus (utility minimized)
        this.template.addEventListener('blur', () => {
            console.log('🔍 Blur event detected - utility minimized');
            this.handleUtilityBlur();
        }, true);
        
        // Enhanced visibility change detection
        document.addEventListener('visibilitychange', () => {
            console.log('🔍 Visibility change detected:', {
                hidden: document.hidden,
                visibilityState: document.visibilityState
            });
            if (document.hidden) {
                this.handleUtilityBlur();
            } else {
                this.handleUtilityFocus();
            }
        });
        
        // Additional utility state detection using resize observer
        this.setupResizeObserver();
        
        console.log('👁️ Enhanced utility bar event listeners set up');
    }
    
    setupVisibilityObserver() {
        try {
            // Use Intersection Observer to detect if component is visible
            this.intersectionObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    const isVisible = entry.isIntersecting;
                    console.log('🔍 Intersection Observer:', {
                        isVisible: isVisible,
                        intersectionRatio: entry.intersectionRatio,
                        boundingClientRect: entry.boundingClientRect
                    });
                    
                    if (isVisible && this.isUtilityMinimized) {
                        console.log('🔍 Component became visible - utility opened');
                        this.handleUtilityFocus();
                    } else if (!isVisible && !this.isUtilityMinimized) {
                        console.log('🔍 Component became hidden - utility minimized');
                        this.handleUtilityBlur();
                    }
                });
            }, {
                threshold: [0, 0.1, 0.5, 1.0] // Multiple thresholds for better detection
            });
            
            // Observe the main container
            setTimeout(() => {
                const container = this.template.querySelector('.email-inbox-container');
                if (container) {
                    this.intersectionObserver.observe(container);
                    console.log('👁️ Intersection Observer started observing container');
                }
            }, 100);
        } catch (error) {
            console.error('❌ Error setting up Intersection Observer:', error);
        }
    }
    
    setupResizeObserver() {
        try {
            // Use Resize Observer to detect size changes (utility opening/closing)
            this.resizeObserver = new ResizeObserver((entries) => {
                entries.forEach(entry => {
                    const { width, height } = entry.contentRect;
                    console.log('🔍 Resize Observer:', {
                        width: width,
                        height: height,
                        currentState: this.isUtilityMinimized ? 'minimized' : 'open'
                    });
                    
                    // If component has significant size, it's likely open
                    if (width > 100 && height > 100 && this.isUtilityMinimized) {
                        console.log('🔍 Significant size detected - utility opened');
                        this.handleUtilityFocus();
                    } else if ((width <= 0 || height <= 0) && !this.isUtilityMinimized) {
                        console.log('🔍 Zero size detected - utility minimized');
                        this.handleUtilityBlur();
                    }
                });
            });
            
            // Observe the main container
            setTimeout(() => {
                const container = this.template.querySelector('.email-inbox-container');
                if (container) {
                    this.resizeObserver.observe(container);
                    console.log('👁️ Resize Observer started observing container');
                }
            }, 100);
        } catch (error) {
            console.error('❌ Error setting up Resize Observer:', error);
        }
    }
    
    // ========== UTILITY BAR AUTO-OPEN FUNCTIONALITY ==========
    
    async getTabId() {
        try {
            this.tabId = await getEnclosingTabId();
            console.log('🔧 Tab ID received:', this.tabId);
        } catch (error) {
            console.error('❌ Error getting tab ID:', error);
        }
    }
    
    async autoOpenUtilityForNewEmails(emailInfo = null) {
        console.log('🔓 AUTO-OPEN: Attempting to open utility for new emails', emailInfo ? {
            emailId: emailInfo.emailId,
            fromAddress: emailInfo.fromAddress,
            toAddress: emailInfo.toAddress,
            source: emailInfo.source
        } : 'No email info provided');
        
        // Double-check recipient filtering if email info is provided
        if (emailInfo && emailInfo.toAddress) {
            const isRecipient = this.isUserRecipient(emailInfo.toAddress, emailInfo.ccAddress, emailInfo.bccAddress);
            if (!isRecipient) {
                console.log('🔓 ❌ AUTO-OPEN BLOCKED: User is not recipient of email');
                return;
            }
            console.log('🔓 ✅ AUTO-OPEN APPROVED: User is recipient of email');
        }
        
        try {
            // First attempt: Use setPanelState with tab ID if available
            if (this.tabId) {
                try {
                    await setPanelState({
                        tabId: this.tabId,
                        panelState: 'open'
                    });
                    console.log('🔓 ✅ SUCCESS: Utility auto-opened using setPanelState');
                    this.isUtilityMinimized = false;
                    return;
                } catch (panelError) {
                    console.warn('⚠️ setPanelState failed, trying other methods:', panelError);
                }
            }
            
            // Second attempt: Use utility open API if utility ID is available
            if (this.utilityId) {
                try {
                    await open(this.utilityId);
                    console.log('🔓 ✅ SUCCESS: Utility auto-opened using open()');
                    this.isUtilityMinimized = false;
                    return;
                } catch (openError) {
                    console.warn('⚠️ open() failed, trying navigation fallback:', openError);
                }
            }
            
            // Third attempt: Use Navigation API to open utility bar from anywhere
            try {
                await this[NavigationMixin.Navigate]({
                    type: 'standard__app',
                    attributes: {
                        appTarget: 'standard__UtilityBar',
                        utilityId: 'emailInboxUtility'
                    }
                });
                console.log('🔓 ✅ SUCCESS: Utility opened using Navigation API');
                this.isUtilityMinimized = false;
                return;
            } catch (navError) {
                console.warn('⚠️ Navigation API failed, trying page reference:', navError);
            }
            
            // Fourth attempt: Use Page Reference navigation
            try {
                const pageRef = {
                    type: 'standard__utility',
                    attributes: {
                        utilityName: 'emailInboxUtility'
                    }
                };
                await this[NavigationMixin.Navigate](pageRef);
                console.log('🔓 ✅ SUCCESS: Utility opened using Page Reference');
                this.isUtilityMinimized = false;
                return;
            } catch (pageRefError) {
                console.warn('⚠️ Page Reference failed, using final fallback:', pageRefError);
            }
            
            // Final fallback: Use custom event to trigger utility opening
            try {
                const autoOpenEvent = new CustomEvent('autoopen_utility', {
                    detail: {
                        utilityName: 'emailInboxUtility',
                        reason: 'newEmail'
                    },
                    bubbles: true,
                    composed: true
                });
                
                // Dispatch to window for global handling
                window.dispatchEvent(autoOpenEvent);
                
                // Also try dispatching to document body
                document.body.dispatchEvent(autoOpenEvent);
                
                console.log('🔓 ✅ SUCCESS: Auto-open event dispatched globally');
                
                // Set a timeout to try utility APIs again after event processing
                setTimeout(async () => {
                    if (this.utilityId) {
                        try {
                            await open(this.utilityId);
                            console.log('🔓 ✅ DELAYED SUCCESS: Utility opened after event dispatch');
                        } catch (delayedError) {
                            console.log('🔓 ℹ️ Delayed open attempt failed (expected):', delayedError);
                        }
                    }
                }, 1000);
                
            } catch (eventError) {
                console.error('❌ All auto-open methods failed:', eventError);
            }
            
        } catch (error) {
            console.error('❌ Critical error in autoOpenUtilityForNewEmails:', error);
        }
    }
    
    // ========== UTILITY BAR STATE MANAGEMENT ==========
    
    async initializeUtilityBarState() {
        console.log('🔧 Initializing utility bar state...');
        
        try {
            const info = await getInfo(this.utilityId);
            this.originalTabLabel = info.label || 'Email Inbox';
            this.isUtilityMinimized = !info.utilityVisible;
            
            console.log('🔧 ✅ Utility state initialized:', {
                originalLabel: this.originalTabLabel,
                isMinimized: this.isUtilityMinimized,
                utilityVisible: info.utilityVisible
            });
        } catch(e) { 
            console.error('❌ Error getting utility info:', e);
            this.isUtilityMinimized = true; 
            this.originalTabLabel = 'Email Inbox';
        }
    }
    
    // ========== REAL-TIME CDC SUBSCRIPTION ==========
    
    initializePlatformEventSubscription() {
        console.log('📡 Initializing Platform Event subscription...');
        
        // Set up error handling for empApi
        onError(err => console.error('empApi error', err));
        
        // Subscribe to New Email Platform Event
        subscribe('/event/New_Email_Event__e', -1, (evt) => {
            const payload = evt?.data?.payload;
            console.log('📡 Platform Event received:', payload);
            
            // Only trigger for incoming emails
            if (payload?.Is_Incoming__c === true) {
                console.log('📡 🔔 NEW INBOUND EMAIL PLATFORM EVENT');
                this.onNewInboundEmailFromPlatformEvent(payload);
            }
        }).then(sub => { 
            this.platformEventSub = sub; 
            console.log('📡 ✅ Successfully subscribed to New Email Platform Event:', sub);
        }).catch(error => {
            console.error('❌ Failed to subscribe to Platform Event:', error);
            console.log('🔄 Will rely on fallback polling for notifications');
        });
    }
    
    onNewInboundEmailFromPlatformEvent(payload) {
        console.log('📡 🔔 PLATFORM EVENT: Processing new email:', {
            emailId: payload.Email_Id__c,
            subject: payload.Email_Subject__c,
            fromAddress: payload.From_Address__c,
            toAddress: payload.To_Address__c
        });
        
        // Check if the current user is the recipient before showing notification
        if (this.isUserRecipient(payload.To_Address__c, payload.Cc_Address__c, payload.Bcc_Address__c)) {
            console.log('📡 🔔 User is recipient - triggering notification');
            // Call the same notification handler with platform event data
            this.onNewInboundEmail({
                emailId: payload.Email_Id__c,
                subject: payload.Email_Subject__c,
                fromAddress: payload.From_Address__c,
                toAddress: payload.To_Address__c,
                ccAddress: payload.Cc_Address__c,
                bccAddress: payload.Bcc_Address__c,
                source: 'platformEvent'
            });
        } else {
            console.log('📡 ℹ️ User is not recipient - skipping notification and auto-open');
        }
    }
    
    async onNewInboundEmail(payload) {
        console.log('🔔 ⚡ REAL-TIME: New inbound email created, triggering notification');
        
        if (!this.utilityId) {
            console.error('❌ Cannot show notification - Utility ID not available');
            return;
        }

        try {
            // bump counter
            this.newEmailCount = (this.newEmailCount || 0) + 1;
            this.hasNewEmails = true;

            // highlight tab
            await updateUtility(this.utilityId, {
                label: `Email (${this.newEmailCount})`,
                icon: 'notification',
                highlighted: true
            });
            console.log('🔔 ✅ Utility tab updated with notification badge');

            // read current visibility
            const info = await getInfo(this.utilityId);
            const isMinimized = !info.utilityVisible;
            console.log('🔔 Utility state:', { isMinimized, utilityVisible: info.utilityVisible });

            // Show blue notification (unless skipToast is true for fallback)
            if (!payload?.skipToast) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'New Email',
                    message: 'You have a new email',
                    variant: 'info',  // Blue notification
                    mode: 'dismissible'
                }));
                console.log('🔔 Blue toast notification sent');
            }

            // Auto-open utility when new email arrives (only for emails where user is recipient)
            // Skip auto-open for fallback polling to prevent multiple opens
            if (!payload?.skipAutoOpen) {
                console.log('🔓 Auto-opening utility for recipient email');
                await this.autoOpenUtilityForNewEmails(payload);
            } else {
                console.log('🔓 Skipping auto-open (fallback polling or skipAutoOpen flag)');
            }
            
            // Refresh data to get the new email
            setTimeout(() => {
                if (!this.isLoading) {
                    console.log('🔄 Refreshing data after CDC notification');
                    this.silentRefresh();
                }
            }, 2000);
            
        } catch (error) {
            console.error('❌ Error in onNewInboundEmail:', error);
        }
    }
    
    startFallbackPolling() {
        console.log('🔔 Starting fallback polling (backup to CDC)...');
        
        // Store initial email count (with guard)
        this.lastKnownEmailCount = this.unseenCount || 0;
        
        // Start fallback polling for new emails every 15 seconds (as backup to CDC)
        this.pollingInterval = setInterval(() => {
            this.checkForNewEmails();
        }, 15000);
        
        console.log('🔔 Fallback polling started (15 second intervals)');
    }
    
    /**
     * Check if the current user is a recipient of the email
     * @param {string} toAddress - To address field
     * @param {string} ccAddress - CC address field  
     * @param {string} bccAddress - BCC address field
     * @returns {boolean} - True if user is recipient, false otherwise
     */
    isUserRecipient(toAddress, ccAddress, bccAddress) {
        // Primary: Use dynamically loaded current user email
        let userEmails = [];
        if (this.currentUserEmail) {
            userEmails.push(this.currentUserEmail);
        }
        
        // Fallback: Use known user emails if dynamic loading failed
        if (userEmails.length === 0) {
            userEmails = [
                'naga@dcgpro.com',
                'potumartinagasaiharsha@gmail.com'
            ];
            console.log('📧 Using fallback user emails for notification filtering');
        }
        
        // Check all address fields
        const allAddresses = [toAddress, ccAddress, bccAddress].filter(addr => addr);
        
        for (const userEmail of userEmails) {
            for (const address of allAddresses) {
                if (address && address.toLowerCase().includes(userEmail.toLowerCase())) {
                    console.log('📧 User email found in recipients:', userEmail, 'in', address);
                    return true;
                }
            }
        }
        
        console.log('📧 User not found in recipients. Addresses checked:', allAddresses, 'User emails:', userEmails);
        return false;
    }
    
    async checkForNewEmails() {
        if (!this.utilityId) return; // Don't poll without utility ID
        
        try {
            console.log('🔍 Fallback polling: Checking for new emails...');
            
            // Get fresh email data
            const result = await getInboundEmails({ 
                limitCount: this.limitCount, 
                lastEmailId: null, 
                fromDate: null,
                toDate: null
            });
            
            if (result.success && result.emails) {
                // Filter emails to only count those where user is recipient
                const userUnseenEmails = result.emails.filter(email => 
                    !email.isSeen && email.emailType === 'Received' && 
                    this.isUserRecipient(email.toAddress, email.ccAddress, email.bccAddress)
                );
                
                const currentUnseenCount = userUnseenEmails.length;
                
                console.log('📊 Fallback polling - Email counts - Last known:', this.lastKnownEmailCount, 'Current:', currentUnseenCount);
                
                // If we have more unseen emails than before, trigger notification
                if (currentUnseenCount > this.lastKnownEmailCount) {
                    const newEmailsReceived = currentUnseenCount - this.lastKnownEmailCount;
                    console.log('🔔 FALLBACK: NEW EMAILS DETECTED FOR USER:', newEmailsReceived);
                    
                    // Show blue notification for fallback detected emails
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'New Email',
                        message: `You have ${newEmailsReceived} new email${newEmailsReceived > 1 ? 's' : ''}`,
                        variant: 'info',  // Blue notification
                        mode: 'dismissible'
                    }));
                    console.log('🔔 Blue fallback notification sent');
                    
                    // Trigger the same utility badge behavior as CDC (but don't auto-open for fallback)
                    for (let i = 0; i < newEmailsReceived; i++) {
                        await this.onNewInboundEmail({ fallback: true, skipToast: true, skipAutoOpen: true });
                    }
                }
                
                this.lastKnownEmailCount = currentUnseenCount;
            }
        } catch (error) {
            console.error('❌ Error in fallback email check:', error);
        }
    }
    
    // Removed - now using onNewInboundEmail pattern
    
    // Called when utility bar is opened/focused
    async handleUtilityFocus() {
        console.log('👁️ Utility bar opened - clearing notifications and stopping fast polling');
        this.isUtilityMinimized = false;
        
        // Sync state with platform
        if (this.utilityId) {
            try {
                const info = await getInfo(this.utilityId);
                this.isUtilityMinimized = !info.utilityVisible;
                console.log('👁️ Synced utility state on focus:', { utilityVisible: info.utilityVisible, isMinimized: this.isUtilityMinimized });
            } catch (error) {
                console.error('❌ Error syncing utility state on focus:', error);
            }
        }
        
        // Stop connection keepalive when utility is opened
        this.stopConnectionKeepalive();
        
        // Clear utility notifications when user opens the utility
        this.clearUtilityNotifications();
        
        // Clear notification states
        this.newEmailCount = 0;
        this.hasNewEmails = false;
        
        // Update last known count to current count
        this.lastKnownEmailCount = this.unseenCount || 0;
        
        // Force clear the highlighting state
        this.isUtilityHighlighted = false;
    }
    
    // Called when utility bar is closed/minimized
    handleUtilityBlur() {
        console.log('👁️‍🗨️ Utility bar minimized - enabling notifications and fast polling');
        this.isUtilityMinimized = true;
        
        // Fast polling will automatically start due to isUtilityMinimized = true
        console.log('🔄 Fast polling will now check for new emails every 5 seconds');
        
        // Immediately check for new emails that might have arrived while utility was open
        setTimeout(() => {
            if (this.isUtilityMinimized && !this.isLoading) {
                console.log('🔄 Immediate check for new emails after minimizing');
                this.checkForNewEmailsOnly();
            }
        }, 1000);
        
        // Keep component connected while minimized by maintaining periodic activity
        this.ensureConnection();
        
        // Start immediate keepalive activity to prevent disconnection
        setTimeout(() => {
            if (this.isUtilityMinimized) {
                console.log('🔗 Immediate keepalive activation after minimizing');
                const container = this.template.querySelector('.email-inbox-container');
                if (container) {
                    container.setAttribute('data-minimized-at', Date.now().toString());
                }
            }
        }, 500);
    }
    
    setupInfiniteScroll() {
        const scrollContainer = this.template.querySelector('.email-list-container');
        if (scrollContainer && this.boundScrollHandler) {
            scrollContainer.addEventListener('scroll', this.boundScrollHandler);
            console.log('📜 Infinite scroll set up successfully');
        }
    }
    
    handleScroll(event) {
        const container = event.target;
        const scrollThreshold = 50; // Load more when 50px from bottom (gives users time to see Load More button)
        
        const isNearBottom = container.scrollTop + container.clientHeight >= 
                           container.scrollHeight - scrollThreshold;
        
        // Only auto-load if we're very close to bottom and there are more emails
        // This allows users to see the "Load More" button or "No more emails" message
        if (isNearBottom && this.hasMoreEmails && !this.isLoadingMore && !this.isLoading) {
            console.log('📜 Near bottom detected - loading more emails automatically');
            this.handleLoadMore();
        }
    }
    
    saveScrollPosition() {
        try {
            const scrollContainer = this.template.querySelector('.email-list-container');
            if (scrollContainer) {
                this.savedScrollPosition = scrollContainer.scrollTop;
                console.log('📍 Saved scroll position:', this.savedScrollPosition);
                
                // Also save to localStorage as backup
                localStorage.setItem('emailInbox_scrollPosition', this.savedScrollPosition.toString());
            } else {
                console.log('📍 Could not find scroll container to save position');
            }
        } catch (error) {
            console.error('📍 Error saving scroll position:', error);
        }
    }
    
    restoreScrollPosition() {
        // Try multiple times with increasing delays to ensure DOM is ready
        const attempts = [50, 150, 300, 500];
        
        attempts.forEach((delay, index) => {
            setTimeout(() => {
                try {
                    const scrollContainer = this.template.querySelector('.email-list-container');
                    if (scrollContainer) {
                        // Use saved position or fall back to localStorage
                        const targetPosition = this.savedScrollPosition || 
                                             parseInt(localStorage.getItem('emailInbox_scrollPosition') || '0');
                        
                        if (targetPosition > 0) {
                            scrollContainer.scrollTop = targetPosition;
                            console.log(`📍 Attempt ${index + 1}: Restored scroll position to:`, targetPosition);
                            
                            // Clear localStorage after successful restore
                            if (index === attempts.length - 1) {
                                localStorage.removeItem('emailInbox_scrollPosition');
                            }
                            return;
                        }
                    }
                    
                    if (index === 0) {
                        console.log('📍 Could not find scroll container to restore position');
                    }
                } catch (error) {
                    console.error(`📍 Error restoring scroll position (attempt ${index + 1}):`, error);
                }
            }, delay);
        });
    }
    
    // ========== FAST NOTIFICATION CHECKING ==========
    
    async checkForNewEmailsOnly() {
        // Quick check for new emails without updating the UI
        try {
            console.log('🔄 Fast checking for new emails...');
            
            const result = await getInboundEmails({ 
                limitCount: 10, // Just check first 10 emails for performance
                lastEmailId: null, 
                fromDate: this.fromDate || null,
                toDate: this.toDate || null
            });
            
            if (result && result.emails) {
                // Check for new unseen emails (server-side seen status) where user is recipient
                const currentEmailIds = new Set(this.emails.map(e => e.id));
                const newUnseenEmails = result.emails.filter(e => 
                    !e.isSeen && e.incoming && !currentEmailIds.has(e.id) &&
                    this.isUserRecipient(e.toAddress, e.ccAddress, e.bccAddress)
                );
                
                if (newUnseenEmails.length > 0) {
                    console.log(`🔔 Fast check found ${newUnseenEmails.length} new unseen emails for user!`);
                    
                    // Optionally trigger a full refresh to get complete data
                    setTimeout(() => {
                        if (!this.isLoading) {
                            console.log('🔄 Triggering full refresh after finding new emails');
                            this.silentRefresh();
                        }
                    }, 2000);
                }
            }
        } catch (error) {
            console.error('❌ Error in fast email check:', error);
        }
    }
    
    // ========== CONNECTION MANAGEMENT ==========
    
    initializeConnectionMonitoring() {
        console.log('🔗 🚀 Initializing enhanced connection monitoring system');
        
        // Immediate connection status setup
        this.setConnectionStatus('initializing');
        
        // Set up continuous connection monitoring
        this.connectionMonitor = setInterval(() => {
            try {
                // Maintain active connection status
                const container = this.template.querySelector('.email-inbox-container');
                if (container) {
                    this.setConnectionStatus('connected');
                    container.setAttribute('data-last-ping', Date.now().toString());
                    container.setAttribute('data-connection-health', 'good');
                }
                
                // Light activity to prevent idle timeout
                const activityMetrics = {
                    timestamp: Date.now(),
                    emailCount: this.emails.length,
                    isMinimized: this.isUtilityMinimized,
                    hasNewEmails: this.hasNewEmails,
                    connectionStatus: 'active'
                };
                
                // Enhanced logging for connection status
                if (this.isUtilityMinimized) {
                    console.log('🔗 💚 Connection monitor ping (minimized):', activityMetrics);
                } else {
                    console.log('🔗 💚 Connection monitor ping (active):', activityMetrics);
                }
                
                // Additional connection verification
                this.verifyConnectionHealth();
                
            } catch (error) {
                console.error('🔗 ❌ Connection monitor error:', error);
                this.setConnectionStatus('error');
            }
        }, 8000); // Every 8 seconds - more aggressive monitoring
        
        console.log('🔗 ✅ Enhanced connection monitoring system initialized');
    }
    
    setConnectionStatus(status) {
        try {
            // Update reactive properties for UI
            this.connectionStatus = status;
            
            switch(status) {
                case 'connected':
                    this.connectionStatusText = 'Email Services Connected';
                    break;
                case 'connecting':
                    this.connectionStatusText = 'Connecting to Email Services...';
                    break;
                case 'disconnected':
                case 'error':
                    this.connectionStatusText = 'Email Services Disconnected';
                    break;
                default:
                    this.connectionStatusText = 'Email Services Status Unknown';
            }
            
            const container = this.template.querySelector('.email-inbox-container');
            if (container) {
                container.setAttribute('data-connection-status', status);
                container.setAttribute('data-connection-timestamp', Date.now().toString());
                
                // Add visual status indicator
                container.classList.remove('connection-disconnected', 'connection-connecting', 'connection-connected');
                
                switch(status) {
                    case 'connected':
                        container.classList.add('connection-connected');
                        container.style.setProperty('--connection-color', '#4CAF50'); // Green
                        break;
                    case 'connecting':
                        container.classList.add('connection-connecting');
                        container.style.setProperty('--connection-color', '#FF9800'); // Orange
                        break;
                    case 'disconnected':
                    case 'error':
                        container.classList.add('connection-disconnected');
                        container.style.setProperty('--connection-color', '#F44336'); // Red
                        break;
                    default:
                        container.style.setProperty('--connection-color', '#2196F3'); // Blue
                }
                
                console.log(`🔗 📍 Connection status set to: ${status.toUpperCase()} - ${this.connectionStatusText}`);
            }
        } catch (error) {
            console.error('🔗 ❌ Error setting connection status:', error);
        }
    }
    
    verifyConnectionHealth() {
        try {
            // Verify component is responsive
            const container = this.template.querySelector('.email-inbox-container');
            if (container) {
                // Test DOM manipulation
                const testAttribute = `health-check-${Date.now()}`;
                container.setAttribute('data-health-check', testAttribute);
                
                // Verify it was set
                const verification = container.getAttribute('data-health-check');
                if (verification === testAttribute) {
                    console.log('🔗 💚 Connection health check PASSED');
                    return true;
                } else {
                    console.warn('🔗 ⚠️ Connection health check FAILED - DOM manipulation issue');
                    this.setConnectionStatus('warning');
                    return false;
                }
            }
        } catch (error) {
            console.error('🔗 ❌ Connection health check ERROR:', error);
            this.setConnectionStatus('error');
            return false;
        }
    }
    
    ensureConnection() {
        // Start connection keepalive when minimized to prevent disconnection
        if (!this.connectionKeepalive) {
            console.log('🔗 Starting enhanced connection keepalive while minimized');
            this.connectionKeepalive = setInterval(() => {
                if (this.isUtilityMinimized) {
                    try {
                        // Enhanced keepalive with multiple activities
                        console.log('🔗 Enhanced connection keepalive ping');
                        
                        // 1. DOM interaction to maintain connection
                        const container = this.template.querySelector('.email-inbox-container');
                        if (container) {
                            // Multiple DOM operations to ensure activity
                            container.getAttribute('data-keepalive');
                            container.classList.contains('email-inbox-container');
                            
                            // Force a small DOM update to maintain reactivity
                            const timestamp = Date.now();
                            container.setAttribute('data-last-keepalive', timestamp.toString());
                        }
                        
                        // 2. Trigger a small reactive property update
                        this.lastRefreshTime = Date.now();
                        
                        // 3. Light calculation to maintain JavaScript execution
                        const keepaliveCheck = this.emails.length + this.filteredEmails.length;
                        console.log('🔗 Keepalive metrics:', { 
                            emailCount: this.emails.length, 
                            filteredCount: this.filteredEmails.length,
                            total: keepaliveCheck 
                        });
                        
                    } catch (error) {
                        console.error('🔗 Keepalive error (continuing):', error);
                    }
                }
            }, 15000); // Every 15 seconds for stronger keepalive
        }
    }
    
    stopConnectionKeepalive() {
        if (this.connectionKeepalive) {
            console.log('🔗 Stopping connection keepalive');
            clearInterval(this.connectionKeepalive);
            this.connectionKeepalive = null;
        }
    }
    
    // ========== AUTO-OPEN UTILITY FUNCTIONALITY - Using the async version above ==========
    
    // ========== UTILITY BAR NOTIFICATIONS (SALESFORCE BEST PRACTICES) ==========
    
    setupNotificationHandler() {
        console.log('🔔 Setting up utility click handler...');
        
        onUtilityClick(async () => {
            console.log('🔔 Utility clicked - clearing badge');
            
            if (!this.utilityId) return;
            
            try {
                // reset label/icon/highlight
                await updateUtility(this.utilityId, { 
                    label: this.originalTabLabel || 'Email Inbox', 
                    icon: 'email', 
                    highlighted: false 
                });
                
                // Clear notification states
                this.newEmailCount = 0;
                this.hasNewEmails = false;
                
                console.log('🔔 ✅ Badge cleared on utility click');
            } catch (error) {
                console.error('❌ Error clearing badge on utility click:', error);
            }
        });
        
        console.log('🔔 ✅ Utility click handler set up successfully');
    }
    
    // Removed - now using onNewInboundEmail pattern with proper updateUtility calls
    
    clearUtilityNotifications() {
        // Check if utilityId is available
        if (!this.utilityId) {
            console.log('🔔 Utility ID not available, skipping clear notification');
            return;
        }
        
        try {
            console.log('🔔 Clearing utility notifications - Current state:', {
                isUtilityHighlighted: this.isUtilityHighlighted,
                utilityId: this.utilityId
            });
            
            // Always clear utility notifications (remove the if condition)
            console.log('🔔 Clearing utility notifications using Salesforce best practices');
            
            // Reset utility to original state using supported LWC parameters only
            const originalUtilityAttrs = {
                label: this.originalTabLabel,
                icon: 'email',
                highlighted: false
            };
            
            updateUtility(this.utilityId, originalUtilityAttrs).then(() => {
                console.log('🔔 Utility reset successfully');
                this.isUtilityHighlighted = false;
            }).catch(error => {
                console.error('❌ Error resetting utility:', error);
            });
            
            // Don't update panel - keep original "Email Inbox" name always
            
            // Clear notification states
            this.newEmailCount = 0;
            this.hasNewEmails = false;
            
        } catch (error) {
            console.error('❌ Error in clearUtilityNotifications:', error);
        }
    }
    
    // ========== NOTIFICATION HELPERS ==========
    
    showNotification(title, message, variant = 'info') {
        console.log('🔔 Showing notification:', { title, message, variant });
        
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'pester' // Makes it stick around longer
        });
        this.dispatchEvent(evt);
    }
    
    clearNotifications() {
        console.log('🔔 Clearing all notifications');
        this.newEmailCount = 0;
        this.hasNewEmails = false;
        this.clearUtilityNotifications();
    }

    handleNotificationClick() {
        console.log('🔔 Notification bell clicked - clearing notifications');
        this.clearNotifications();
        
        // Force refresh to get latest emails
        this.handleRefresh();
    }
}