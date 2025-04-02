import base64
import boto3
import gzip
import json
from botocore.exceptions import ClientError

bedrock_agent = boto3.client('bedrock-agent')
ssm = boto3.client('ssm')
sns = boto3.client('sns')


def get_ssm_parameter(name):
    response = ssm.get_parameter(Name=name, WithDecryption=True)
    return response['Parameter']['Value']


def get_ingestion_job(knowledge_base_id, data_source_id, ingestion_job_id):
    response = bedrock_agent.get_ingestion_job(
        knowledgeBaseId=knowledge_base_id,
        dataSourceId=data_source_id,
        ingestionJobId=ingestion_job_id
    )
    return response['ingestionJob']


def lambda_handler(event, context):
    try:
        success_sns_topic_arn = get_ssm_parameter('/check-kb-ingestion-job-statuses/success-sns-topic-arn')
        failure_sns_topic_arn = get_ssm_parameter('/check-kb-ingestion-job-statuses/failure-sns-topic-arn')

        encoded_zipped_data = event['awslogs']['data']
        zipped_data = base64.b64decode(encoded_zipped_data)
        data = json.loads(gzip.decompress(zipped_data))
        log_events = data['logEvents']
        for log_event in log_events:
            message = json.loads(log_event['message'])
            knowledge_base_arn = message['event']['knowledge_base_arn']
            knowledge_base_id = knowledge_base_arn.split('/')[-1]
            data_source_id = message['event']['data_source_id']
            ingestion_job_id = message['event']['ingestion_job_id']

            print(
                f'Checking ingestion job status for knowledge base {knowledge_base_id} data source {data_source_id} job {ingestion_job_id}')
            ingestion_job = get_ingestion_job(knowledge_base_id, data_source_id, ingestion_job_id)
            print(
                f'Ingestion job summary: \n\n{json.dumps(ingestion_job, indent=2, sort_keys=True, default=str)}')
            job_status = ingestion_job['status']
            if job_status == 'COMPLETE':
                sns.publish(
                    TopicArn=success_sns_topic_arn,
                    Subject=f'Ingestion job for knowledge base {knowledge_base_id} data source {data_source_id} job {ingestion_job_id} Completed',
                    Message=json.dumps(ingestion_job, indent=2, sort_keys=True, default=str)
                )
            elif job_status == 'FAILED':
                sns.publish(
                    TopicArn=failure_sns_topic_arn,
                    Subject=f'Ingestion job for knowledge base {knowledge_base_id} data source {data_source_id} job {ingestion_job_id} FAILED',
                    Message=json.dumps(ingestion_job, indent=2, sort_keys=True, default=str)
                )
            elif job_status == 'STOPPED':
                sns.publish(
                    TopicArn=failure_sns_topic_arn,
                    Subject=f'Ingestion job for knowledge base {knowledge_base_id} data source {data_source_id} job {ingestion_job_id} STOPPED',
                    Message=json.dumps(ingestion_job, indent=2, sort_keys=True, default=str)
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
