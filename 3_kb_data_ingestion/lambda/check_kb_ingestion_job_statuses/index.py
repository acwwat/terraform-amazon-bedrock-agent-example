import boto3
import json
from botocore.exceptions import ClientError

bedrock_agent = boto3.client('bedrock-agent')
ssm = boto3.client('ssm')
sns = boto3.client('sns')
sqs = boto3.client('sqs')


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
        sqs_queue_url = get_ssm_parameter('/check-kb-ingestion-job-statuses/sqs-queue-url')
        success_sns_topic_arn = get_ssm_parameter('/check-kb-ingestion-job-statuses/success-sns-topic-arn')
        failure_sns_topic_arn = get_ssm_parameter('/check-kb-ingestion-job-statuses/failure-sns-topic-arn')

        response = sqs.receive_message(
            QueueUrl=sqs_queue_url,
            MaxNumberOfMessages=10
        )
        while 'Messages' in response:
            messages = response['Messages']
            for message in messages:
                body = json.loads(message['Body'])
                knowledge_base_id = body['knowledge_base_id']
                data_source_id = body['data_source_id']
                ingestion_job_id = body['ingestion_job_id']

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

                if job_status in ['COMPLETE', 'FAILED', 'STOPPED']:
                    sqs.delete_message(
                        QueueUrl=sqs_queue_url,
                        ReceiptHandle=message['ReceiptHandle']
                    )
            response = sqs.receive_message(
                QueueUrl=sqs_queue_url,
                MaxNumberOfMessages=10
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
