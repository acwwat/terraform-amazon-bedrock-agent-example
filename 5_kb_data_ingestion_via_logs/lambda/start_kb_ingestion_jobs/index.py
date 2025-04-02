import boto3
import json
from botocore.exceptions import ClientError

bedrock_agent = boto3.client('bedrock-agent')
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
