#!/usr/bin/env bash

#depends on jq and AWS CLI
#author jedilover

__SELF="${0##*/}"
ARG_LAMBDA_NAME="${1:?USAGE $__SELF [aws_lambda_f_name] [aws_api_gw_name]}"
ARG_APIGW_NAME="${2:?USAGE $__SELF [aws_lambda_f_name] [aws_api_gw_name]}"

set -eupx
set +x

VAR_LAMBDA_ROLE_ARN=$(aws iam create-role --role-name "$ARG_LAMBDA_NAME"-lambda-execute-role --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' | jq -r '.Role.Arn')

aws iam attach-role-policy --role-name "$ARG_LAMBDA_NAME"-lambda-execute-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

echo "$VAR_LAMBDA_ROLE_ARN"

VAR_APIGW_ROLE_ARN=$(aws iam create-role --role-name "$ARG_APIGW_NAME"-apigw-execute-role --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Sid": "", "Effect": "Allow", "Principal": {"Service": "apigateway.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' | jq -r '.Role.Arn')

aws iam attach-role-policy --role-name "$ARG_APIGW_NAME"-apigw-execute-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole

echo "$VAR_APIGW_ROLE_ARN"

cat > "$ARG_LAMBDA_NAME".py<< EOF
import json

def lambda_handler(event, context):
    print( event )
    result = "BUU"
    try:
        ua=event['requestContext']['identity']['userAgent']
        ip=event['requestContext']['identity']['sourceIp']
        print( ua, ip)
        result=f'{ua} {ip}'
    except Exception as e:
        print( e )
        return {
            'statusCode': 403,
            'body': json.dumps("try again through api gw")
        }
    return {
        'statusCode': 200,
        'body': json.dumps(result)
    }
EOF

zip -9 "$ARG_LAMBDA_NAME".zip "$ARG_LAMBDA_NAME".py

sleep 9.6

VAR_FUNCTION_ARN=$(
aws lambda create-function \
    --function-name "$ARG_LAMBDA_NAME" \
    --runtime python3.7 \
    --zip-file fileb://"$ARG_LAMBDA_NAME".zip \
    --handler "$ARG_LAMBDA_NAME".lambda_handler \
    --role "$VAR_LAMBDA_ROLE_ARN" \
    --timeout 30 \
    --memory-size 128 \
    --description foobar | jq -r '.FunctionArn')

echo "$VAR_FUNCTION_ARN"

VAR_APIGW_ID=$(aws apigateway create-rest-api --name "$ARG_APIGW_NAME" | jq -r '.id')

echo "$VAR_APIGW_ID"

VAR_APIGW_ROOTID=$(aws apigateway get-resources --rest-api-id "$VAR_APIGW_ID" | jq -r '.items[].id') 

echo "$VAR_APIGW_ROOTID"

VAR_APIGW_RESOURCE_ID=$(aws apigateway create-resource --rest-api-id "$VAR_APIGW_ID" --parent-id "$VAR_APIGW_ROOTID" --path-part "{proxy+}"| jq -r '.id' )

echo "$VAR_APIGW_RESOURCE_ID"

aws apigateway put-method --rest-api-id "$VAR_APIGW_ID" \
       --resource-id "$VAR_APIGW_RESOURCE_ID" \
       --http-method ANY \
       --authorization-type "NONE" 
       #--api-key-required 

#todo region
#arn:aws:apigateway:{region}:{service}:{path|action}/{service_api}
aws apigateway put-integration \
        --rest-api-id "$VAR_APIGW_ID" \
        --resource-id "$VAR_APIGW_RESOURCE_ID" \
        --http-method ANY \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/"$VAR_FUNCTION_ARN"/invocations \
        --credentials "$VAR_APIGW_ROLE_ARN"

aws apigateway create-deployment --rest-api-id "$VAR_APIGW_ID" --stage-name test

#test
curl -X GET 'https://'"$VAR_APIGW_ID"'.execute-api.eu-west-1.amazonaws.com/test/'"$ARG_LAMBDA_NAME"'/context_path?foo=bar' 



