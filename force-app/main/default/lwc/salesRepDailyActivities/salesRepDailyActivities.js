import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSalesRepEvents from '@salesforce/apex/SalesRepActivitiesController.getSalesRepEvents';
import getSalesReps from '@salesforce/apex/SalesRepActivitiesController.getSalesReps';
import getEventChecksum from '@salesforce/apex/SalesRepActivitiesController.getEventChecksum';

export default class SalesRepDailyActivities extends NavigationMixin(LightningElement) {
    salesReps = [];
    allEvents = [];
    timeSlots = [];
    calendarGrid = [];
    @track selectedDate;
    isLoading = true;
    @track error;
    repColorMap = {};
    
    // Smart auto-refresh properties for TV display
    quickCheckInterval;     // Dynamic interval based on business hours
    fullRefreshInterval;    // 30-minute safety net interval
    salesRepsWiredResult;
    eventsWiredResult;
    isAutoRefreshEnabled = true; // Always enabled for TV display
    BUSINESS_HOURS_CHECK_INTERVAL = 2 * 60 * 1000;  // 2 minutes during business hours
    OFF_HOURS_CHECK_INTERVAL = 10 * 60 * 1000;      // 10 minutes off-hours
    WEEKEND_CHECK_INTERVAL = 15 * 60 * 1000;        // 15 minutes on weekends
    FULL_REFRESH_INTERVAL = 30 * 60 * 1000;         // 30 minutes safety net
    lastEventChecksum = null;  // Track last known state
    lastFullRefreshTime = null; // Track when we last did full refresh
    isRefreshing = false;      // Prevent overlapping refreshes
    consecutiveCheckErrors = 0; // Track failures for fallback
    visibilityChangeHandler = null; // Track visibility handler
    lastVisibilityState = null; // Track last visibility state
    viewMode = 'day'; // 'day' or 'week'
    @track weekStartDate;
    @track weekEndDate;
    meetingStats = {
        totalMeetings: 0,
        totalHours: 0,
        byRep: []
    };
    
    connectedCallback() {
        // Track all intervals for proper cleanup
        this.activeIntervals = [];
        this.refreshInProgress = false;
        this.initializeDate();
        this.generateTimeSlots();
        this.startAutoRefresh();
        this.setupVisibilityListener();
    }
    
    disconnectedCallback() {
        // Critical: Stop auto-refresh to prevent memory leaks
        this.stopAutoRefresh();
        this.removeVisibilityListener();
        // Clear any pending async operations
        if (this.pendingRefreshPromise) {
            this.pendingRefreshPromise = null;
        }
        // Clean up any remaining intervals
        this.clearAllIntervals();
    }
    
    clearAllIntervals() {
        // Clear all tracked intervals
        if (this.activeIntervals && this.activeIntervals.length > 0) {
            this.activeIntervals.forEach(intervalId => {
                if (intervalId) clearInterval(intervalId);
            });
            this.activeIntervals = [];
        }
        // Also clear any untracked intervals
        if (this.quickCheckInterval) {
            clearInterval(this.quickCheckInterval);
            this.quickCheckInterval = null;
        }
        if (this.fullRefreshInterval) {
            clearInterval(this.fullRefreshInterval);
            this.fullRefreshInterval = null;
        }
    }

    initializeDate() {
        // Use today's date
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        this.selectedDate = today;
    }

    generateTimeSlots() {
        const slots = [];
        
        // Generate time slots from 9 AM to 6 PM with 30-minute intervals
        for (let hour = 9; hour <= 18; hour++) {
            for (let minute = 0; minute < 60; minute += 30) {
                const hour12 = hour === 12 ? 12 : hour % 12;
                const ampm = hour < 12 ? 'AM' : 'PM';
                const displayHour = hour12 === 0 ? 12 : hour12;
                const displayMinute = minute === 0 ? '00' : '30';
                
                slots.push({
                    hour: hour,
                    minute: minute,
                    label: minute === 0 ? `${displayHour}:00 ${ampm}` : '',
                    isHourMark: minute === 0,
                    isHalfHour: minute === 30,
                    time24: `${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}`,
                    slotKey: `${hour}-${minute}`
                });
            }
        }
        
        this.timeSlots = slots;
    }

    @wire(getSalesReps)
    wiredSalesReps(result) {
        this.salesRepsWiredResult = result; // Store for refreshApex
        const { error, data } = result;
        
        if (data) {
            // Assign colors to each sales rep
            const colors = [
                '#0078d4', '#00bcf2', '#00a83c', '#ffb900', 
                '#e81123', '#5c2d91', '#00758f', '#ff4b1f',
                '#002050', '#498205', '#d83b01', '#a4262c'
            ];
            
            this.salesReps = data.map((rep, index) => {
                const color = colors[index % colors.length];
                return {
                    ...rep,
                    color: color,
                    initials: this.getInitials(rep.Name),
                    avatarStyle: `background-color: ${color};`,
                    badgeStyle: `background-color: ${color};`,
                    legendStyle: `background-color: ${color};`,
                    columnStyle: index % 2 === 0 ? '' : 'background: #fafbfc;'
                };
            });
            
            // Create color map for quick lookup
            this.salesReps.forEach(rep => {
                this.repColorMap[rep.Id] = rep.color;
            });
            
            // Trigger event loading after sales reps are loaded
            if (this.selectedDate) {
                this.refreshCalendar();
            }
        } else if (error) {
            console.error('Error loading sales reps:', error);
            this.error = error;
            this.isLoading = false;
        }
    }

    getInitials(name) {
        const parts = name.split(' ');
        if (parts.length >= 2) {
            return parts[0][0] + parts[parts.length - 1][0];
        }
        return name.substring(0, 2).toUpperCase();
    }

    @wire(getSalesRepEvents, { activityDate: '$selectedDateString' })
    wiredEvents(result) {
        this.eventsWiredResult = result; // Store for refreshApex
        const { error, data } = result;
        
        this.isLoading = false;
        if (data) {
            this.allEvents = data || [];
            this.processCalendarGrid();
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.allEvents = [];
            this.processCalendarGrid(); // Still process to clear the grid
        }
    }

    get selectedDateString() {
        try {
            if (!this.selectedDate || !(this.selectedDate instanceof Date)) return null;
            const date = new Date(this.selectedDate);
            if (isNaN(date.getTime())) return null;
            const dateStr = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
            return dateStr;
        } catch (error) {
            console.error('Error getting selected date string:', error);
            return null;
        }
    }

    processCalendarGrid() {
        const grid = [];
        this.calculateMeetingStats();
        
        // PERFORMANCE: Cache all Date objects and calculations upfront
        const eventDateCache = new Map();
        const eventsByRep = new Map();
        
        // Single pass to cache dates and group by rep
        this.allEvents.forEach(event => {
            const startDate = new Date(event.StartDateTime);
            const endDate = new Date(event.EndDateTime);
            eventDateCache.set(event.Id, {
                start: startDate,
                end: endDate,
                startHour: startDate.getHours(),
                startMinute: startDate.getMinutes(),
                endHour: endDate.getHours(),
                endMinute: endDate.getMinutes(),
                startMinutes: startDate.getHours() * 60 + startDate.getMinutes(),
                endMinutes: endDate.getHours() * 60 + endDate.getMinutes(),
                duration: (endDate - startDate) / (1000 * 60)
            });
            
            // Group by rep in same pass
            if (!eventsByRep.has(event.OwnerId)) {
                eventsByRep.set(event.OwnerId, []);
            }
            eventsByRep.get(event.OwnerId).push(event);
        });
        
        // Use shared filtering logic to ensure consistency with activeSalesReps getter
        const repsWithEvents = this.getRepsWithDisplayableEvents();
        const activeReps = this.salesReps.filter(rep => repsWithEvents.has(rep.Id));
        
        // Process overlaps with cached data
        const repEventMap = {};
        activeReps.forEach(rep => {
            const repEvents = eventsByRep.get(rep.Id) || [];
            repEventMap[rep.Id] = this.processRepEvents(repEvents);
        });
        
        // Process each time slot
        this.timeSlots.forEach(slot => {
            const row = {
                hour: slot.hour,
                minute: slot.minute,
                label: slot.label,
                isHourMark: slot.isHourMark,
                isHalfHour: slot.isHalfHour,
                time24: slot.time24,
                slotKey: slot.slotKey,
                rowClass: slot.isHourMark ? 'time-row hour-mark' : 'time-row half-hour-mark',
                cells: []
            };
            
            // Process each active sales rep
            activeReps.forEach(rep => {
                const cell = {
                    repId: rep.Id,
                    repName: rep.Name,
                    hour: slot.hour,
                    minute: slot.minute,
                    events: [],
                    cellClass: 'time-cell time-cell-optimized',
                    slotKey: `${rep.Id}-${slot.slotKey}`
                };
                
                // Get events for this time slot with overlap info
                const repEvents = repEventMap[rep.Id] || [];
                
                // Pre-calculate slot minutes once
                const slotStartMinutes = slot.hour * 60 + slot.minute;
                const slotEndMinutes = slotStartMinutes + 30;
                
                repEvents.forEach(eventInfo => {
                    // Use cached date data instead of creating new Date objects
                    const cachedData = eventDateCache.get(eventInfo.event.Id);
                    if (!cachedData) return;
                    
                    // Use cached check instead of calling eventOccursInSlot
                    if (this.eventOccursInSlotCached(eventInfo.event, slot.hour, slot.minute, cachedData)) {
                        const eventStartMinutes = cachedData.startMinutes;
                        const duration = cachedData.duration;
                        
                        
                        // Event should be added to a cell if it starts within this 30-minute slot
                        const shouldAddEvent = eventStartMinutes >= slotStartMinutes && eventStartMinutes < slotEndMinutes;
                        
                        if (shouldAddEvent) {
                            // Avoid spread operator for performance
                            cell.events.push({
                                Id: eventInfo.event.Id,
                                Subject: eventInfo.event.Subject,
                                StartDateTime: eventInfo.event.StartDateTime,
                                EndDateTime: eventInfo.event.EndDateTime,
                                OwnerId: eventInfo.event.OwnerId,
                                ContactName: eventInfo.event.ContactName,
                                LeadName: eventInfo.event.LeadName,
                                id: eventInfo.event.Id,
                                title: eventInfo.event.Subject || 'No Subject',
                                clientName: eventInfo.event.ContactName || eventInfo.event.LeadName || '',
                                startTime: this.formatTimeCached(cachedData.start),
                                endTime: this.formatTimeCached(cachedData.end),
                                duration: duration,
                                durationHours: (duration / 60).toFixed(1),
                                repColor: this.repColorMap[eventInfo.event.OwnerId],
                                overlapColumn: eventInfo.column,
                                totalColumns: eventInfo.totalColumns,
                                isStart: true,
                                eventStyle: this.getEventStyleOptimized(
                                    eventInfo.event,
                                    cachedData,
                                    slot.hour,
                                    slot.minute,
                                    rep.color,
                                    eventInfo.column,
                                    eventInfo.totalColumns
                                )
                            });
                        }
                    }
                });
                
                row.cells.push(cell);
            });
            
            grid.push(row);
        });
        
        this.calendarGrid = grid;
    }

    processRepEvents(events) {
        // Sort events by start time
        const sortedEvents = [...events].sort((a, b) => 
            new Date(a.StartDateTime) - new Date(b.StartDateTime)
        );
        
        // Detect overlapping events and assign columns
        const processedEvents = [];
        sortedEvents.forEach(event => {
            const eventStart = new Date(event.StartDateTime);
            const eventEnd = new Date(event.EndDateTime);
            
            // Find overlapping events
            const overlappingEvents = processedEvents.filter(pe => {
                const peStart = new Date(pe.event.StartDateTime);
                const peEnd = new Date(pe.event.EndDateTime);
                return peStart < eventEnd && peEnd > eventStart;
            });
            
            // Assign column based on overlaps
            let column = 0;
            const usedColumns = overlappingEvents.map(oe => oe.column);
            while (usedColumns.includes(column)) {
                column++;
            }
            
            processedEvents.push({
                event: event,
                column: column,
                totalColumns: Math.max(...overlappingEvents.map(oe => oe.totalColumns || 1), column + 1)
            });
            
            // Update total columns for overlapping events
            overlappingEvents.forEach(oe => {
                oe.totalColumns = Math.max(oe.totalColumns || 1, column + 1);
            });
        });
        
        return processedEvents;
    }

    eventOccursInSlotCached(event, hour, minute, cachedData) {
        // PERFORMANCE: Use pre-cached date data instead of creating new Date objects
        const eventYear = cachedData.start.getFullYear();
        const eventMonth = cachedData.start.getMonth();
        const eventDay = cachedData.start.getDate();
        
        // Get selected date components
        const selectedYear = this.selectedDate.getFullYear();
        const selectedMonth = this.selectedDate.getMonth();
        const selectedDay = this.selectedDate.getDate();
        
        // Check if event is on the selected date
        if (eventYear !== selectedYear || eventMonth !== selectedMonth || eventDay !== selectedDay) {
            return false;
        }
        
        // Use pre-calculated minutes
        const slotStartMinutes = hour * 60 + minute;
        const slotEndMinutes = slotStartMinutes + 30;
        
        // Check overlap using cached values
        const overlaps = (cachedData.startMinutes >= slotStartMinutes && cachedData.startMinutes < slotEndMinutes) ||
                        (cachedData.endMinutes > slotStartMinutes && cachedData.endMinutes <= slotEndMinutes) ||
                        (cachedData.startMinutes <= slotStartMinutes && cachedData.endMinutes >= slotEndMinutes);
        
        return overlaps;
    }
    
    eventOccursInSlot(event, hour, minute) {
        // Parse the UTC datetime from Salesforce
        const eventStart = new Date(event.StartDateTime);
        const eventEnd = new Date(event.EndDateTime);
        
        // Get the event date in local timezone
        const eventYear = eventStart.getFullYear();
        const eventMonth = eventStart.getMonth();
        const eventDay = eventStart.getDate();
        
        // Get selected date components
        const selectedYear = this.selectedDate.getFullYear();
        const selectedMonth = this.selectedDate.getMonth();
        const selectedDay = this.selectedDate.getDate();
        
        
        // Check if event is on the selected date
        if (eventYear !== selectedYear || eventMonth !== selectedMonth || eventDay !== selectedDay) {
            return false;
        }
        
        // Check if event overlaps with this time slot
        const eventStartHour = eventStart.getHours();
        const eventStartMinute = eventStart.getMinutes();
        const eventEndHour = eventEnd.getHours();
        const eventEndMinute = eventEnd.getMinutes();
        
        // Check if this 30-minute time slot overlaps with the event
        const slotStartMinutes = hour * 60 + minute;
        const slotEndMinutes = slotStartMinutes + 30; // Each slot is 30 minutes
        const eventStartInMinutes = eventStartHour * 60 + eventStartMinute;
        const eventEndInMinutes = eventEndHour * 60 + eventEndMinute;
        
        // A slot overlaps with an event if:
        // - The event starts during this slot, OR
        // - The event ends during this slot, OR  
        // - The event spans across this entire slot
        const overlaps = (eventStartInMinutes >= slotStartMinutes && eventStartInMinutes < slotEndMinutes) || // Event starts in this slot
                        (eventEndInMinutes > slotStartMinutes && eventEndInMinutes <= slotEndMinutes) || // Event ends in this slot
                        (eventStartInMinutes <= slotStartMinutes && eventEndInMinutes >= slotEndMinutes); // Event spans entire slot
        
        
        return overlaps;
    }

    getEventStyle(event, eventStart, slotHour, slotMinute, repColor, column, totalColumns) {
        const eventEnd = new Date(event.EndDateTime);
        const startHour = eventStart.getHours();
        const startMinute = eventStart.getMinutes();
        const duration = (eventEnd - eventStart) / (1000 * 60); // Duration in minutes
        
        // Check if event starts within this 30-minute slot
        const slotStartMinutes = slotHour * 60 + slotMinute;
        const slotEndMinutes = slotStartMinutes + 30;
        const eventStartMinutes = startHour * 60 + startMinute;
        
        if (eventStartMinutes < slotStartMinutes || eventStartMinutes >= slotEndMinutes) {
            return 'display: none;';
        }
        
        // Calculate offset within the slot for events that don't start at slot boundary
        const minuteOffset = startMinute % 30;
        const pixelOffset = (minuteOffset / 30) * 30; // Convert minute offset to pixels
        
        // Calculate height based on duration (30px per 30-minute slot)
        // For short events (< 30 min), use proportional height to avoid overflow
        const baseHeight = (duration / 30) * 30;
        // Only use minimum height if event is longer than 30 minutes
        const height = duration >= 30 ? Math.max(baseHeight, 45) : Math.max(baseHeight, 20);
        
        // Calculate width and position for overlapping events
        const widthPercent = totalColumns > 1 ? (100 / totalColumns) : 100;
        const leftPercent = column * widthPercent;
        
        // Position within the cell, accounting for events that don't start at slot boundary
        const topOffset = 1 + pixelOffset;
        
        return `
            position: absolute;
            top: ${topOffset}px;
            left: ${leftPercent}%;
            width: calc(${widthPercent}% - 4px);
            height: ${height}px;
            background: linear-gradient(135deg, ${repColor}f5, ${repColor}e5);
            color: white;
            padding: 3px 5px;
            border-radius: 4px;
            font-size: 10px;
            overflow: hidden;
            cursor: pointer;
            z-index: ${10 + column};
            border-left: 3px solid ${repColor};
            box-shadow: 0 1px 3px rgba(0,0,0,0.2);
            transition: all 0.2s ease;
        `;
    }

    formatTimeCached(date) {
        // PERFORMANCE: Cache formatted times to avoid repeated formatting
        const hour = date.getHours();
        const minute = date.getMinutes();
        const hour12 = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
        const ampm = hour < 12 ? 'AM' : 'PM';
        const minuteStr = minute.toString().padStart(2, '0');
        return `${hour12}:${minuteStr} ${ampm}`;
    }
    
    formatTime(date) {
        return date.toLocaleTimeString('en-US', { 
            hour: 'numeric', 
            minute: '2-digit',
            hour12: true 
        });
    }
    
    getEventStyleOptimized(event, cachedData, slotHour, slotMinute, repColor, column, totalColumns) {
        // PERFORMANCE: Optimized style generation with cached data
        const slotStartMinutes = slotHour * 60 + slotMinute;
        const slotEndMinutes = slotStartMinutes + 30;
        
        if (cachedData.startMinutes < slotStartMinutes || cachedData.startMinutes >= slotEndMinutes) {
            return 'display: none;';
        }
        
        // Calculate position and dimensions
        const minuteOffset = cachedData.startMinute % 30;
        const pixelOffset = (minuteOffset / 30) * 30;
        const baseHeight = (cachedData.duration / 30) * 30;
        const height = cachedData.duration >= 30 ? Math.max(baseHeight, 45) : Math.max(baseHeight, 20);
        const widthPercent = totalColumns > 1 ? (100 / totalColumns) : 100;
        const leftPercent = column * widthPercent;
        const topOffset = 1 + pixelOffset;
        
        // Use data attributes and CSS classes instead of inline styles where possible
        return `
            position: absolute;
            top: ${topOffset}px;
            left: ${leftPercent}%;
            width: calc(${widthPercent}% - 4px);
            height: ${height}px;
            background: linear-gradient(135deg, ${repColor}f5, ${repColor}e5);
            border-left: 3px solid ${repColor};
            z-index: ${10 + column};
        `;
    }

    // Navigation methods
    handleDateChange(event) {
        try {
            const dateValue = event.target.value;
            if (dateValue) {
                const newDate = new Date(dateValue + 'T00:00:00');
                // Validate the date is valid
                if (isNaN(newDate.getTime())) {
                    console.error('Invalid date selected:', dateValue);
                    return;
                }
                this.selectedDate = newDate;
                this.refreshCalendar();
            }
        } catch (error) {
            console.error('Error handling date change:', error);
            // Keep current date if error occurs
        }
    }

    get selectedDateValue() {
        if (!this.selectedDate) return '';
        const year = this.selectedDate.getFullYear();
        const month = String(this.selectedDate.getMonth() + 1).padStart(2, '0');
        const day = String(this.selectedDate.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    refreshCalendar() {
        // Prevent overlapping refreshes
        if (this.refreshInProgress) {
            console.log('Refresh already in progress, skipping...');
            return;
        }
        
        this.refreshInProgress = true; // Set flag to prevent overlap
        this.isLoading = true;
        
        // Trigger wire service refresh
        this.selectedDate = new Date(this.selectedDate);
        
        // Reset flag after a short delay to allow refresh to complete
        setTimeout(() => {
            this.refreshInProgress = false;
        }, 1000);
        
        // Restart auto-refresh timers (fixes memory leak)
        this.restartAutoRefresh();
    }
    
    // Smart auto-refresh methods for TV display with business hours optimization
    startAutoRefresh() {
        if (this.isAutoRefreshEnabled) {
            // Clear ALL existing intervals to prevent memory leaks
            this.stopAutoRefresh();
            
            // Add safety check to prevent interval stacking
            if (this.quickCheckInterval || this.fullRefreshInterval) {
                console.log('Warning: Intervals still active, clearing...');
                this.clearAllIntervals();
            }
            
            // Determine check interval based on business hours
            const checkInterval = this.getOptimalCheckInterval();
            
            // Start dynamic check interval
            this.quickCheckInterval = setInterval(() => {
                this.performSmartCheck();
            }, checkInterval);
            
            // Start safety net full refresh (30 minutes)
            this.fullRefreshInterval = setInterval(() => {
                this.performSafetyNetRefresh();
            }, this.FULL_REFRESH_INTERVAL);
            
            console.log(`Auto-refresh started: ${checkInterval/60000} min interval at`, new Date().toLocaleTimeString());
        }
    }
    
    getOptimalCheckInterval() {
        const now = new Date();
        const hour = now.getHours();
        const day = now.getDay(); // 0 = Sunday, 6 = Saturday
        
        // Weekend: Use longest interval
        if (day === 0 || day === 6) {
            return this.WEEKEND_CHECK_INTERVAL;
        }
        
        // Weekday business hours (8 AM - 6 PM EST)
        if (hour >= 8 && hour < 18) {
            return this.BUSINESS_HOURS_CHECK_INTERVAL;
        }
        
        // Off-hours on weekdays
        return this.OFF_HOURS_CHECK_INTERVAL;
    }
    
    performSmartCheck() {
        // Skip if tab is hidden to save resources
        if (document.hidden) {
            console.log('Tab hidden, skipping refresh check');
            return;
        }
        
        // Perform the regular quick check
        this.performQuickCheck();
        
        // Adjust interval if needed based on current time
        const newInterval = this.getOptimalCheckInterval();
        const currentInterval = this.quickCheckInterval ? 
            this.quickCheckInterval._idleTimeout || this.BUSINESS_HOURS_CHECK_INTERVAL : 
            this.BUSINESS_HOURS_CHECK_INTERVAL;
            
        if (Math.abs(newInterval - currentInterval) > 60000) { // If difference > 1 minute
            console.log(`Adjusting check interval from ${currentInterval/60000} to ${newInterval/60000} minutes`);
            this.restartAutoRefresh();
        }
    }
    
    stopAutoRefresh() {
        // Clear quick check interval
        if (this.quickCheckInterval) {
            clearInterval(this.quickCheckInterval);
            this.quickCheckInterval = null;
        }
        
        // Clear full refresh interval  
        if (this.fullRefreshInterval) {
            clearInterval(this.fullRefreshInterval);
            this.fullRefreshInterval = null;
        }
        
        console.log('Auto-refresh stopped');
    }
    
    restartAutoRefresh() {
        // Stop then start to ensure clean state
        this.stopAutoRefresh();
        this.startAutoRefresh();
    }
    
    async performQuickCheck() {
        try {
            // Don't check if already refreshing or tab is hidden
            if (this.refreshInProgress || document.hidden) return;
            
            // Get current event checksum
            const selectedDateValue = this.selectedDateString;
            if (!selectedDateValue) return;
            
            const currentChecksum = await getEventChecksum({ 
                activityDate: selectedDateValue 
            });
            
            // Compare with last known checksum
            const hasChanges = this.detectChanges(currentChecksum);
            
            if (hasChanges) {
                console.log('Changes detected! Performing full refresh...');
                await this.performFullRefresh();
            } else {
                console.log('No changes detected at', new Date().toLocaleTimeString());
            }
            
            // Update last checksum
            this.lastEventChecksum = currentChecksum;
            this.consecutiveCheckErrors = 0; // Reset error counter
            
        } catch (error) {
            console.error('Quick check error:', error);
            this.consecutiveCheckErrors++;
            
            // If quick checks fail 3 times, do a full refresh as fallback
            if (this.consecutiveCheckErrors >= 3) {
                console.log('Quick check failed 3 times, forcing full refresh...');
                await this.performFullRefresh();
                this.consecutiveCheckErrors = 0;
            }
        }
    }
    
    detectChanges(newChecksum) {
        // First check - no previous checksum
        if (!this.lastEventChecksum) {
            return false; // Don't refresh on first check
        }
        
        // Compare checksums
        if (newChecksum.eventCount !== this.lastEventChecksum.eventCount) {
            console.log('Event count changed:', this.lastEventChecksum.eventCount, '→', newChecksum.eventCount);
            return true;
        }
        
        if (newChecksum.eventHash !== this.lastEventChecksum.eventHash) {
            console.log('Event data changed (hash mismatch)');
            return true;
        }
        
        if (newChecksum.lastModified > this.lastEventChecksum.lastModified) {
            console.log('Events modified since last check');
            return true;
        }
        
        return false;
    }
    
    async performFullRefresh() {
        // Prevent overlapping refreshes with better lock
        if (this.refreshInProgress) {
            console.log('Refresh already in progress, skipping...');
            return;
        }
        
        try {
            this.refreshInProgress = true;
            this.showRefreshIndicator();
            
            // Refresh both sales reps and events
            const promises = [];
            
            if (this.salesRepsWiredResult) {
                promises.push(refreshApex(this.salesRepsWiredResult));
            }
            if (this.eventsWiredResult) {
                promises.push(refreshApex(this.eventsWiredResult));
            }
            
            await Promise.all(promises);
            
            this.lastFullRefreshTime = new Date();
            console.log('Full refresh completed at', this.lastFullRefreshTime.toLocaleTimeString());
            
        } catch (error) {
            console.error('Full refresh error:', error);
            // For TV display, don't show error toasts
        } finally {
            this.refreshInProgress = false;
            this.hideRefreshIndicator();
        }
    }
    
    async performSafetyNetRefresh() {
        // Safety net: Force refresh if we haven't refreshed in 30 minutes
        const now = new Date();
        const timeSinceLastRefresh = this.lastFullRefreshTime 
            ? (now - this.lastFullRefreshTime) / 1000 / 60 
            : 999;
            
        if (timeSinceLastRefresh >= 29) {
            console.log('Safety net: Forcing refresh after', Math.round(timeSinceLastRefresh), 'minutes');
            await this.performFullRefresh();
        }
    }
    
    showRefreshIndicator() {
        // Add a subtle visual indicator that refresh is happening
        const element = this.template.querySelector('.calendar-header');
        if (element) {
            element.classList.add('refreshing');
        }
    }
    
    hideRefreshIndicator() {
        const element = this.template.querySelector('.calendar-header');
        if (element) {
            element.classList.remove('refreshing');
        }
    }

    handleEventClick(event) {
        const eventId = event.currentTarget.dataset.eventId;
        if (eventId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: eventId,
                    objectApiName: 'Event',
                    actionName: 'view'
                }
            });
        }
    }

    // Getters
    get formattedDate() {
        if (!this.selectedDate) return '';
        return this.selectedDate.toLocaleDateString('en-US', { 
            weekday: 'long',
            month: 'long', 
            day: 'numeric',
            year: 'numeric' 
        });
    }

    get hasEvents() {
        return this.allEvents && this.allEvents.length > 0;
    }

    get hasSalesReps() {
        return this.salesReps && this.salesReps.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && (!this.hasSalesReps || !this.hasEvents);
    }
    
    getRepsWithDisplayableEvents() {
        // Extract shared logic to identify reps with events in the 9 AM - 6 PM display window
        // This ensures consistency between UI display and calendar grid processing
        const repsWithEvents = new Set();
        
        if (!this.allEvents || this.allEvents.length === 0) {
            return repsWithEvents;
        }
        
        this.allEvents.forEach(event => {
            try {
                const eventDate = new Date(event.StartDateTime);
                const eventEnd = new Date(event.EndDateTime);
                
                // Validate dates to handle edge cases
                if (!this.isValidDate(eventDate) || !this.isValidDate(eventEnd)) {
                    console.warn('Invalid event dates detected:', event.Id, event.StartDateTime, event.EndDateTime);
                    return;
                }
                
                // Check if event is on the selected date (handle timezone boundaries)
                if (!this.isEventOnSelectedDate(eventDate, eventEnd)) {
                    return;
                }
                
                const eventStartHour = eventDate.getHours();
                const eventEndHour = eventEnd.getHours();
                const eventEndMinute = eventEnd.getMinutes();
                
                // Include rep if event overlaps with display window (9 AM - 6 PM) in any way
                // Event starts before 6 PM OR ends after 9 AM OR ends exactly at 9 AM with minutes > 0
                const overlapsDisplayWindow = (eventStartHour < 18) || 
                                             (eventEndHour > 9) || 
                                             (eventEndHour === 9 && eventEndMinute > 0);
                
                if (overlapsDisplayWindow) {
                    repsWithEvents.add(event.OwnerId);
                }
            } catch (error) {
                console.error('Error processing event for rep filtering:', event.Id, error);
            }
        });
        
        return repsWithEvents;
    }
    
    isValidDate(date) {
        return date instanceof Date && !isNaN(date.getTime());
    }
    
    isEventOnSelectedDate(eventStart, eventEnd) {
        if (!this.selectedDate) return false;
        
        // Get event date in local timezone
        const eventYear = eventStart.getFullYear();
        const eventMonth = eventStart.getMonth();
        const eventDay = eventStart.getDate();
        
        // Get selected date components
        const selectedYear = this.selectedDate.getFullYear();
        const selectedMonth = this.selectedDate.getMonth();
        const selectedDay = this.selectedDate.getDate();
        
        // Check if event starts on the selected date
        const startsOnSelectedDate = (eventYear === selectedYear && 
                                     eventMonth === selectedMonth && 
                                     eventDay === selectedDay);
        
        // Also check if event spans across the selected date (starts before, ends on selected date)
        const endYear = eventEnd.getFullYear();
        const endMonth = eventEnd.getMonth();
        const endDay = eventEnd.getDate();
        
        const endsOnSelectedDate = (endYear === selectedYear && 
                                   endMonth === selectedMonth && 
                                   endDay === selectedDay);
        
        return startsOnSelectedDate || endsOnSelectedDate;
    }
    
    get activeSalesReps() {
        // Return only sales reps who have events for the selected day within display window (9 AM - 6 PM)
        if (!this.allEvents || this.allEvents.length === 0) {
            return [];
        }
        
        const repsWithEvents = this.getRepsWithDisplayableEvents();
        const activeReps = this.salesReps.filter(rep => repsWithEvents.has(rep.Id));
        return activeReps;
    }
    
    calculateMeetingStats() {
        const stats = {
            totalMeetings: 0,
            totalHours: 0,
            byRep: []
        };
        
        const repStats = {};
        
        this.allEvents.forEach(event => {
            const duration = (new Date(event.EndDateTime) - new Date(event.StartDateTime)) / (1000 * 60 * 60); // Hours
            stats.totalMeetings++;
            stats.totalHours += duration;
            
            if (!repStats[event.OwnerId]) {
                const rep = this.salesReps.find(r => r.Id === event.OwnerId);
                repStats[event.OwnerId] = {
                    repName: rep ? rep.Name : 'Unknown',
                    repColor: rep ? rep.color : '#888',
                    colorStyle: `background-color: ${rep ? rep.color : '#888'};`,
                    meetings: 0,
                    hours: 0
                };
            }
            
            repStats[event.OwnerId].meetings++;
            repStats[event.OwnerId].hours += duration;
        });
        
        stats.byRep = Object.values(repStats).map(rep => ({
            ...rep,
            hours: rep.hours.toFixed(1)
        })).sort((a, b) => b.meetings - a.meetings);
        stats.totalHours = stats.totalHours.toFixed(1);
        
        this.meetingStats = stats;
    }
    
    toggleViewMode() {
        this.viewMode = this.viewMode === 'day' ? 'week' : 'day';
        this.refreshCalendar();
    }
    
    get isWeekView() {
        return this.viewMode === 'week';
    }
    
    get isDayView() {
        return this.viewMode === 'day';
    }
    
    exportToCSV() {
        let csv = 'Sales Rep,Date,Time,Subject,Duration (hours)\n';
        
        this.allEvents.forEach(event => {
            const rep = this.salesReps.find(r => r.Id === event.OwnerId);
            const startDate = new Date(event.StartDateTime);
            const duration = ((new Date(event.EndDateTime) - startDate) / (1000 * 60 * 60)).toFixed(1);
            
            csv += `"${rep ? rep.Name : 'Unknown'}",`;
            csv += `"${startDate.toLocaleDateString()}",`;
            csv += `"${this.formatTime(startDate)}",`;
            csv += `"${event.Subject || 'No Subject'}",`;
            csv += `${duration}\n`;
        });
        
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `sales-activities-${this.selectedDateString}.csv`;
        a.click();
        window.URL.revokeObjectURL(url);
    }
    
    // Visibility change handling for optimized refresh
    setupVisibilityListener() {
        this.visibilityChangeHandler = () => {
            const isHidden = document.hidden;
            
            // Tab became visible after being hidden
            if (!isHidden && this.lastVisibilityState === true) {
                console.log('Tab became visible, checking for updates...');
                // Perform immediate check when tab becomes visible
                this.performQuickCheck();
            }
            
            this.lastVisibilityState = isHidden;
            
            if (isHidden) {
                console.log('Tab hidden, pausing active refreshes');
            } else {
                console.log('Tab visible, resuming active refreshes');
            }
        };
        
        document.addEventListener('visibilitychange', this.visibilityChangeHandler);
    }
    
    removeVisibilityListener() {
        if (this.visibilityChangeHandler) {
            document.removeEventListener('visibilitychange', this.visibilityChangeHandler);
            this.visibilityChangeHandler = null;
        }
    }
}