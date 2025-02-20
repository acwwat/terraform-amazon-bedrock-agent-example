import boto3
import json
from botocore.exceptions import ClientError

bedrock_agent = boto3.client('bedrock-agent')
sqs = boto3.client('sqs')
ssm = boto3.client('ssm')


def lambda_handler(event, context):
    try:
        # Retrieve the JSON config from Parameter Store
        response = ssm.get_parameter(Name='/start-kb-ingestion-jobs/config-json')
        config_json = response['Parameter']['Value']
        config = json.loads(config_json)

        for record in config:
            knowledge_base_id = record.get('knowledge_base_id')
            for data_source_id in record.get('data_source_ids'):
                # Start the ingestion job
                print(f'Starting ingestion job for data source {data_source_id} of knowledge base {knowledge_base_id}')
                response = bedrock_agent.start_ingestion_job(
                    knowledgeBaseId=knowledge_base_id,
                    dataSourceId=data_source_id
                )
                ingestion_job_id = response['ingestionJob']['ingestionJobId']

                # Send a message to the SQS queue
                response = ssm.get_parameter(Name='/start-kb-ingestion-jobs/sqs-queue-url')
                sqs_queue_url = response['Parameter']['Value']
                message = {
                    'knowledge_base_id': knowledge_base_id,
                    'data_source_id': data_source_id,
                    'ingestion_job_id': ingestion_job_id
                }
                sqs.send_message(
                    QueueUrl=sqs_queue_url,
                    MessageBody=json.dumps(message)
                )
        return {
            'statusCode': 200,
            'body': 'Success'
        }
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': f'Client error: {str(e)}'
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': f'Unexpected error: {str(e)}'
        }
