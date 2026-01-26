public class BankVerificationFileHandler {

    public static void afterInsert(List<ContentDocumentLink> ListContentDocumentLink) {

        Map<Id, Id> mapBvToDoc = new Map<Id, Id>();
        
        for (ContentDocumentLink oContentDocumentLink : ListContentDocumentLink) {
            if (oContentDocumentLink.LinkedEntityId != null && String.valueOf(oContentDocumentLink.LinkedEntityId).startsWith('a0K')) {
                mapBvToDoc.put(oContentDocumentLink.LinkedEntityId, oContentDocumentLink.ContentDocumentId);
            }
        }

        if (mapBvToDoc.isEmpty()) 
            return;

        Map<Id, ContentDocument> mapContentDoc = new Map<Id, ContentDocument>([SELECT Id, Title, FileExtension FROM ContentDocument WHERE Id IN :mapBvToDoc.values()]);

        for (Id BankVerificationId : new List<Id>(mapBvToDoc.keySet())) {
            ContentDocument oContentDoc = mapContentDoc.get(mapBvToDoc.get(BankVerificationId));

            if (oContentDoc == null || !oContentDoc.Title.startsWith('Asset_Report') || oContentDoc.FileExtension != 'pdf') {
                mapBvToDoc.remove(BankVerificationId);
            }
        }

        if (mapBvToDoc.isEmpty()) 
            return;

        Map<Id, bankconnect__Bank_Verification__c> mapBankVerification = new Map<Id, bankconnect__Bank_Verification__c>([SELECT Id, bankconnect__Account__c FROM bankconnect__Bank_Verification__c WHERE Id IN :mapBvToDoc.keySet()]);

        List<ContentDocumentLink> listLinksToInsert = new List<ContentDocumentLink>();

        for (Id BankVerificationId : mapBvToDoc.keySet()) {

            bankconnect__Bank_Verification__c oBankVerification = mapBankVerification.get(BankVerificationId);

            if (oBankVerification == null || oBankVerification.bankconnect__Account__c == null) {
                continue;
            }

            ContentDocumentLink oContentDocLink = new ContentDocumentLink(
                ContentDocumentId = mapBvToDoc.get(BankVerificationId),
                LinkedEntityId    = oBankVerification.bankconnect__Account__c,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            );

            listLinksToInsert.add(oContentDocLink);
        }

        if (!listLinksToInsert.isEmpty()) {
            insert listLinksToInsert;
        }
    }
}