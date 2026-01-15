const amplifyconfig = '''{
    "UserAgent": "aws-amplify-cli/2.0",
    "Version": "1.0",
    "auth": {
        "plugins": {
            "awsCognitoAuthPlugin": {
                "UserAgent": "aws-amplify-cli/0.1.0",
                "Version": "0.1.0",
                "CognitoUserPool": {
                    "Default": {
                        "PoolId": "us-east-1_i8OdXtL1u",
                        "AppClientId": "2fep4tchr2g6olsbs9nj7nd4u4",
                        "Region": "us-east-1"
                    }
                }
            }
        }
    },
    "api": {
        "plugins": {
            "awsAPIPlugin": {
                "CashSenseAPI": {
                    "endpointType": "REST",
                    "endpoint": "https://0ic4wr3xsc.execute-api.us-east-1.amazonaws.com/prod",
                    "region": "us-east-1",
                    "authorizationType": "AMAZON_COGNITO_USER_POOLS"
                }
            }
        }
    }
}''';