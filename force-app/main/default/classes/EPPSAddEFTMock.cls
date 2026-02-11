/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSAddEFTMock
 * Author          : Shell Black (Scot Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides mock callout coverage used in EPPSClientPaymentBatchTest
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
global class EPPSAddEFTMock implements HttpCalloutMock {

	private Integer httpStatus = 200;

    public enum Mode {
        SUCCESS,
        FAILURE,
        THROW_EXCEPTION
    }

    private Mode mode;
    private String cardHolderId;
    private String eftTransactionId;
    private String message;
    private String statusCode;
    private String statusDate;

    // === Primary constructor ===
    public EPPSAddEFTMock(
        Mode mode,
        String cardHolderId,
        String eftTransactionId,
        String message,
        String statusCode,
        String statusDate
    ) {
        this.mode = mode;
        this.cardHolderId = cardHolderId;
        this.eftTransactionId = eftTransactionId;
        this.message = message;
        this.statusCode = statusCode;
        this.statusDate = statusDate;

		if (mode == EPPSAddEFTMock.Mode.FAILURE) {
			this.httpStatus = 500; // 👈 force transport failure
		}
    }

    // === Convenience SUCCESS constructor ===
    public EPPSAddEFTMock(String cardHolderId, String eftTransactionId) {
        this(
            EPPSAddEFTMock.Mode.SUCCESS,   // ✅ fully qualified
            cardHolderId,
            eftTransactionId,
            'Success',
            'Create EFT Pending',
            '2026-01-09T00:00:00'
        );
    }

    // === Convenience EXCEPTION constructor ===
    public EPPSAddEFTMock() {
        this.mode = EPPSAddEFTMock.Mode.THROW_EXCEPTION; // ✅ fully qualified
    }

    global HTTPResponse respond(HTTPRequest req) {
        if (mode == EPPSAddEFTMock.Mode.THROW_EXCEPTION) {
            throw new CalloutException('Simulated EPPS outage');
        }

        HttpResponse res = new HttpResponse();
        res.setStatusCode(httpStatus);
        res.setHeader('Content-Type', 'text/xml; charset=utf-8');

        String msg =
            (mode == EPPSAddEFTMock.Mode.FAILURE)
                ? 'Failure'
                : message;

        res.setBody(
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<soap:Envelope ' +
                'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
              '<soap:Body>' +
                '<AddEftResponse xmlns="http://tempuri.org/">' +
                  '<AddEftResult>' +
                    '<CardHolderID>' + cardHolderId + '</CardHolderID>' +
                    '<EftTransactionID>' + eftTransactionId + '</EftTransactionID>' +
                    '<StatusCode>' + statusCode + '</StatusCode>' +
                    '<Message>' + msg + '</Message>' +
                    '<StatusDate>' + statusDate + '</StatusDate>' +
                  '</AddEftResult>' +
                '</AddEftResponse>' +
              '</soap:Body>' +
            '</soap:Envelope>'
        );

        return res;
    }
}