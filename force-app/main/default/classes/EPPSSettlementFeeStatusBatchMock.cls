global class EPPSSettlementFeeStatusBatchMock implements HttpCalloutMock 
{

	 global HttpResponse respond(HttpRequest request) 
	 {
		HttpResponse response = new HttpResponse();

		response.setHeader('Content-Type', 'application/json');
		response.setBody(ResponseBody);
		response.setStatusCode(200);

		return response;
	 }

	 public static string ResponseBody = '';
	 public static integer NumRecords = 10;
	 ///  Replace with Response from findFeeById
	public static string CreateResponseBody()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><FindFeeByIDResponse xmlns="http://tempuri.org/"><FindFeeByIDResult><FeeList><Fee><CardHolderID>12345</CardHolderID><FeeID>11749828</FeeID><EftTransactionID /><Party>Debt Program</Party><FeeAmount>22.00</FeeAmount><Description>Test</Description><Fee_Date>2026-01-09T00:00:00</Fee_Date><FeeType>Commission Fee</FeeType><PaidToName>Test</PaidToName><PaidToPhone>Test</PaidToPhone><PaidToStreet>Test</PaidToStreet><PaidToStreet2>Test</PaidToStreet2><PaidToCity>Test</PaidToCity><PaidToState>CA</PaidToState><PaidToZip>Test</PaidToZip><PaidToContactName>Test</PaidToContactName><BankReferenceID /><StatusCode>Pending</StatusCode><StatusDate>2026-01-08T00:00:00</StatusDate></Fee></FeeList><Message>Success</Message></FindFeeByIDResult></FindFeeByIDResponse></soap:Body></soap:Envelope>';

		string EFTTransactionDetailTemplate = '<EFTTransactionDetail><CardHolderId>12345</CardHolderId><EftTransactionID>***EftTransactionID***</EftTransactionID><EftDate>2025-12-10T20:42:24</EftDate><EftAmount>1500.00</EftAmount><BankName></BankName><BankCity></BankCity><BankState></BankState><AccountNumber>123456</AccountNumber><RoutingNumber>123123123</RoutingNumber><Memo>string</Memo><StatusCode>Create EFT Pending</StatusCode><StatusDate>2026-01-04T00:00:00</StatusDate><CreatedDate>2025-12-09T10:12:16</CreatedDate><SettledDate /><ReturnedDate /><NSFReturnCode /></EFTTransactionDetail>';
		string EFTTransactionDetailSection = '';

		for (Integer i = 0; i < NumRecords; i++) 
		{
			EFTTransactionDetailSection += EFTTransactionDetailTemplate.replace('***EftTransactionID***', String.valueOf(i));
		}

		SoapBody = SoapBody.replace('****EFTTransactionDetail****', EFTTransactionDetailSection);		
		return SoapBody;
	}
}