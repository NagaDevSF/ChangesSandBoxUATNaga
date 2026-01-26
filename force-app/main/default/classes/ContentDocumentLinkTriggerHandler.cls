public class ContentDocumentLinkTriggerHandler {
    
    public static void handleAfterInsert(List<ContentDocumentLink> newLinks) {
        ContentDocumentLinkHandler.handleDocumentChanges(newLinks, null);
    }
    
    public static void handleAfterDelete(List<ContentDocumentLink> oldLinks) {
        ContentDocumentLinkHandler.handleDocumentChanges(null, oldLinks);
    }
}