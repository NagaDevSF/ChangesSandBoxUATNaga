global class EPPSDailyJobScheduler implements Schedulable {

	global void execute(SchedulableContext sc) {
		EPPSDailyJobScheduler.runNow();
	}

	public static void runNow() {
		System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(null));
	}
}