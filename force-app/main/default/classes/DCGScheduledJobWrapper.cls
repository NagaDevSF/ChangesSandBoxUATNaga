global class DCGScheduledJobWrapper implements Schedulable {
    global void execute(SchedulableContext sc) {
        // Schedule your specific job here
        DCGScheduledJob actualJob = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        actualJob.execute(sc);
    }
}