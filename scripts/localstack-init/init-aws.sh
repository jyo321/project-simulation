#!/usr/bin/env bash
# Runs automatically inside the LocalStack container on startup (mounted to
# /etc/localstack/init/ready.d/ — see docker-compose.yml). Recreates, against LocalStack,
# the S3/SQS/SNS topology that infra/terraform provisions against real AWS, so the whole
# system is runnable end-to-end on a laptop with no AWS account.
set -euo pipefail

awslocal s3 mb s3://raw-documents
awslocal s3 mb s3://generated-documents
awslocal s3 mb s3://reports

awslocal sqs create-queue --queue-name document-validation-dlq
awslocal sqs create-queue --queue-name document-validation
awslocal sqs create-queue --queue-name status-projector-dlq
awslocal sqs create-queue --queue-name status-projector
awslocal sqs create-queue --queue-name notifications-dlq
awslocal sqs create-queue --queue-name notifications
awslocal sqs create-queue --queue-name credit-scoring-jobs-dlq
awslocal sqs create-queue --queue-name credit-scoring-jobs
awslocal sqs create-queue --queue-name fraud-analysis-jobs-dlq
awslocal sqs create-queue --queue-name fraud-analysis-jobs

TOPIC_ARN=$(awslocal sns create-topic --name application-events --query TopicArn --output text)

STATUS_PROJECTOR_QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/status-projector \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

NOTIFICATIONS_QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/notifications \
  --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

# RawMessageDelivery=true so the workers see the domain-event JSON directly in the SQS
# message body, matching the assumption baked into StatusProjectorWorker/NotificationWorker.
awslocal sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$STATUS_PROJECTOR_QUEUE_ARN" \
  --attributes '{"RawMessageDelivery":"true"}'
awslocal sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$NOTIFICATIONS_QUEUE_ARN" \
  --attributes '{"RawMessageDelivery":"true"}'

echo "Northbridge LocalStack topology ready: 3 buckets, 10 queues, 1 SNS topic with 2 subscriptions."
