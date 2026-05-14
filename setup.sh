#!/usr/bin/env bash
set -euo pipefail

ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SQS_VIDEO_VISIBILITY_TIMEOUT_SECONDS="${SQS_VIDEO_VISIBILITY_TIMEOUT_SECONDS:-3600}"
SQS_THUMBNAIL_VISIBILITY_TIMEOUT_SECONDS="${SQS_THUMBNAIL_VISIBILITY_TIMEOUT_SECONDS:-600}"
SQS_WAIT_TIME_SECONDS="${SQS_WAIT_TIME_SECONDS:-20}"
SQS_MAX_MESSAGES="${SQS_MAX_MESSAGES:-10}"
SQS_ERROR_DELAY_SECONDS="${SQS_ERROR_DELAY_SECONDS:-2}"
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_CHUNK_DETAILS="${LOG_CHUNK_DETAILS:-false}"
LOG_FFMPEG_PROGRESS="${LOG_FFMPEG_PROGRESS:-true}"

export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"

aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region "$REGION"
aws configure set output json

aws_local() {
  aws --endpoint-url="$ENDPOINT_URL" "$@"
}

create_bucket() {
  local bucket="$1"

  if aws_local s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    echo "Bucket já existe: $bucket"
  else
    aws_local s3 mb "s3://$bucket"
    echo "Bucket criado: $bucket"
  fi
}

create_queue() {
  local queue="$1"

  if aws_local sqs get-queue-url --queue-name "$queue" >/dev/null 2>&1; then
    echo "Fila já existe: $queue"
  else
    aws_local sqs create-queue --queue-name "$queue" >/dev/null
    echo "Fila criada: $queue"
  fi
}

create_notification_config() {
  local bucket="$1"
  local config="$2"
  local queue_url="$3"
  local prefix="$4"
  local queue_arn
  local notification_file

  queue_arn="$(aws_local sqs get-queue-attributes \
    --queue-url "$queue_url" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)"

  notification_file="$(mktemp)"
  cat > "$notification_file" <<EOF
{
  "QueueConfigurations": [
    {
      "Id": "xtube-$config-upload-event",
      "QueueArn": "$queue_arn",
      "Events": [
        "s3:ObjectCreated:*"
      ],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "$prefix"
            }
          ]
        }
      }
    }
  ]
}
EOF

  aws_local s3api put-bucket-notification-configuration \
    --bucket "$bucket" \
    --notification-configuration file://"$notification_file" >/dev/null

  rm -f "$notification_file"

  echo "Configuração aplicada: $config"
}

purge_queue() {
  local queue_url="$1"
  local queue_name="$2"

  aws_local sqs purge-queue --queue-url "$queue_url" >/dev/null 2>&1 || true
  echo "Fila limpa: $queue_name"
}

echo "Configurando AWS local em $ENDPOINT_URL"
echo "Região: $REGION"
echo "Credenciais locais: $AWS_ACCESS_KEY_ID / $AWS_SECRET_ACCESS_KEY"

create_bucket "xtube-videos-input"
create_bucket "xtube-videos-output"
create_bucket "xtube-thumbnails"
create_bucket "xtube-temp"

create_queue "xtube-video-processing"
create_queue "xtube-video-processing-dlq"
create_queue "xtube-thumbnail-processing"

MAIN_QUEUE_URL="$(aws_local sqs get-queue-url --queue-name xtube-video-processing --query QueueUrl --output text)"
DLQ_URL="$(aws_local sqs get-queue-url --queue-name xtube-video-processing-dlq --query QueueUrl --output text)"
THUMBNAIL_QUEUE_URL="$(aws_local sqs get-queue-url --queue-name xtube-thumbnail-processing --query QueueUrl --output text)"

DLQ_ARN="$(aws_local sqs get-queue-attributes \
  --queue-url "$DLQ_URL" \
  --attribute-names QueueArn \
  --query 'Attributes.QueueArn' \
  --output text)"

aws_local sqs set-queue-attributes \
  --queue-url "$MAIN_QUEUE_URL" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\",\"VisibilityTimeout\":\"$SQS_VIDEO_VISIBILITY_TIMEOUT_SECONDS\",\"MessageRetentionPeriod\":\"1209600\"}"

aws_local sqs set-queue-attributes \
  --queue-url "$THUMBNAIL_QUEUE_URL" \
  --attributes "{\"VisibilityTimeout\":\"$SQS_THUMBNAIL_VISIBILITY_TIMEOUT_SECONDS\",\"MessageRetentionPeriod\":\"1209600\"}"

create_notification_config "xtube-videos-input" "video" "$MAIN_QUEUE_URL" "uploads/"
create_notification_config "xtube-thumbnails" "thumbnail" "$THUMBNAIL_QUEUE_URL" "uploads/"

purge_queue "$MAIN_QUEUE_URL" "xtube-video-processing"
purge_queue "$THUMBNAIL_QUEUE_URL" "xtube-thumbnail-processing"
purge_queue "$DLQ_URL" "xtube-video-processing-dlq"

cat > .env.localstack <<EOF
AWS_ENDPOINT_URL=$ENDPOINT_URL
AWS_REGION=$REGION
AWS_DEFAULT_REGION=$REGION
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

S3_BUCKET_INPUT=xtube-videos-input
S3_BUCKET_OUTPUT=xtube-videos-output
S3_BUCKET_THUMBNAILS=xtube-thumbnails
S3_BUCKET_TEMP=xtube-temp

SQS_VIDEO_PROCESSING_URL=$MAIN_QUEUE_URL
SQS_VIDEO_PROCESSING_DLQ_URL=$DLQ_URL
SQS_THUMBNAIL_PROCESSING_URL=$THUMBNAIL_QUEUE_URL
SQS_VIDEO_VISIBILITY_TIMEOUT_SECONDS=$SQS_VIDEO_VISIBILITY_TIMEOUT_SECONDS
SQS_THUMBNAIL_VISIBILITY_TIMEOUT_SECONDS=$SQS_THUMBNAIL_VISIBILITY_TIMEOUT_SECONDS
SQS_WAIT_TIME_SECONDS=$SQS_WAIT_TIME_SECONDS
SQS_MAX_MESSAGES=$SQS_MAX_MESSAGES
SQS_ERROR_DELAY_SECONDS=$SQS_ERROR_DELAY_SECONDS

LOG_LEVEL=$LOG_LEVEL
LOG_CHUNK_DETAILS=$LOG_CHUNK_DETAILS
LOG_FFMPEG_PROGRESS=$LOG_FFMPEG_PROGRESS
EOF

echo ""
echo "Infraestrutura local criada com sucesso."

echo ""
echo "Buckets:"
aws_local s3 ls

echo ""
echo "Filas:"
aws_local sqs list-queues --query QueueUrls --output table

echo ""
echo "Arquivo .env.localstack gerado."
