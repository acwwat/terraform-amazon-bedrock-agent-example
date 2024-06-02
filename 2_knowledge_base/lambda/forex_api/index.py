import json
import urllib.parse # urllib is available in Lambda runtime w/o needing a layer
import urllib.request

def lambda_handler(event, context):
    agent = event['agent']
    actionGroup = event['actionGroup']
    apiPath = event['apiPath']
    httpMethod =  event['httpMethod']
    parameters = event.get('parameters', [])
    requestBody = event.get('requestBody', {})
    
    # Read and process input parameters
    code = None
    for parameter in parameters:
        if (parameter["name"] == "code"):
            # Just in case, convert to lowercase as expected by the API
            code = parameter["value"].lower()

    # Execute your business logic here. For more information, refer to: https://docs.aws.amazon.com/bedrock/latest/userguide/agents-lambda.html
    apiPathWithParam = apiPath
    # Replace URI path parameters
    if code is not None:
        apiPathWithParam = apiPathWithParam.replace("{code}", urllib.parse.quote(code))

    # TODO: Use a environment variable or Parameter Store to set the URL
    url = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1{apiPathWithParam}.min.json".format(apiPathWithParam = apiPathWithParam)

    # Call the currency exchange rates API based on the provided path and wrap the response
    apiResponse = urllib.request.urlopen(
        urllib.request.Request(
            url=url,
            headers={"Accept": "application/json"},
            method="GET"
        )
    )
    responseBody =  {
        "application/json": {
            "body": apiResponse.read()
        }
    }

    action_response = {
        'actionGroup': actionGroup,
        'apiPath': apiPath,
        'httpMethod': httpMethod,
        'httpStatusCode': 200,
        'responseBody': responseBody

    }

    api_response = {'response': action_response, 'messageVersion': event['messageVersion']}
    print("Response: {}".format(api_response))

    return api_response
