# XTube Local AWS Infrastructure

This repository contains the local AWS infrastructure setup for the XTube project using LocalStack.

It provides local versions of the AWS services required by the video processing pipeline, including S3 buckets and SQS queues.

## Overview

The infrastructure is designed to simulate AWS locally during development.

It creates:

- S3 buckets for video input, processed output, thumbnails, and temporary files
- SQS queues for video processing and thumbnail processing
- A Dead Letter Queue for failed video processing messages
- A `.env.localstack` file containing the generated local infrastructure configuration

## Files

```text
.
├── compose.yaml
├── setup.sh
├── .gitignore
└── README.md
```

## Requirements

Before running the infrastructure, make sure the following tools and credentials are available:

- Docker
- Docker Compose
- AWS CLI
- LocalStack Auth Token

You can verify the installed tools with:

```bash
docker --version
docker compose version
aws --version
```

The LocalStack Auth Token must be defined in a local `.env` file:

```env
LOCALSTACK_AUTH_TOKEN=your-localstack-auth-token
```

## LocalStack

The `compose.yaml` file starts a LocalStack container exposing the local AWS endpoint on:

```text
http://localhost:4566
```

The service is bound to localhost only:

```text
127.0.0.1:4566:4566
```

This prevents the LocalStack endpoint from being exposed externally.

The container requires `LOCALSTACK_AUTH_TOKEN` even when Pro features are disabled.

The current Compose configuration uses:

```yaml
services:
  infra-aws:
    image: localstack/localstack:latest
    container_name: xtube-infra-aws
    ports:
      - "127.0.0.1:4566:4566"
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN}
      - DEBUG=1
      - PERSISTENCE=1
      - ACTIVATE_PRO=0
    volumes:
      - "./xtube-infra-aws:/var/lib/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
```

`ACTIVATE_PRO=0` keeps Pro features disabled, but the token is still required for container startup.

## Environment Variables

Create a `.env` file in the project root:

```bash
touch .env
```

Add your LocalStack Auth Token:

```env
LOCALSTACK_AUTH_TOKEN=your-localstack-auth-token
```

The `.env` file is ignored by Git and must not be committed.

The setup script also configures fake AWS credentials for local usage:

```env
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=us-east-1
AWS_REGION=us-east-1
```

These credentials are not real AWS credentials. They are used only to authenticate requests against LocalStack.

## Starting the Infrastructure

Start LocalStack with:

```bash
docker compose up -d
```

Check if the container is running:

```bash
docker ps
```

Expected container name:

```text
xtube-infra-aws
```

Check the LocalStack logs:

```bash
docker logs -f xtube-infra-aws
```

Check the LocalStack health endpoint:

```bash
curl http://localhost:4566/_localstack/health
```

## Running the Setup Script

Make the setup script executable:

```bash
chmod +x setup.sh
```

Run the script:

```bash
./setup.sh
```

The script performs the following actions:

- Configures local AWS credentials
- Creates the required S3 buckets
- Creates the required SQS queues
- Configures the Dead Letter Queue for video processing
- Generates a `.env.localstack` file
- Lists the created buckets and queues

## Created S3 Buckets

The script creates the following buckets:

| Bucket | Purpose |
|---|---|
| `xtube-videos-input` | Stores original uploaded videos |
| `xtube-videos-output` | Stores processed video files |
| `xtube-thumbnails` | Stores generated thumbnails |
| `xtube-temp` | Stores temporary processing files |

## Created SQS Queues

The script creates the following queues:

| Queue | Purpose |
|---|---|
| `xtube-video-processing` | Main queue for video processing jobs |
| `xtube-video-processing-dlq` | Dead Letter Queue for failed video processing jobs |
| `xtube-thumbnail-processing` | Queue for thumbnail generation jobs |

## Queue Configuration

The main video processing queue uses the Dead Letter Queue after 3 failed receives:

```text
maxReceiveCount = 3
```

The main video processing queue uses:

```text
VisibilityTimeout = 300 seconds
MessageRetentionPeriod = 1209600 seconds
```

The thumbnail processing queue uses:

```text
VisibilityTimeout = 120 seconds
MessageRetentionPeriod = 1209600 seconds
```

## Generated Environment File

After running the setup script, a `.env.localstack` file is generated.

Example:

```env
AWS_ENDPOINT_URL=http://localhost:4566
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test

S3_BUCKET_INPUT=xtube-videos-input
S3_BUCKET_OUTPUT=xtube-videos-output
S3_BUCKET_THUMBNAILS=xtube-thumbnails
S3_BUCKET_TEMP=xtube-temp

SQS_VIDEO_PROCESSING_URL=http://localhost:4566/000000000000/xtube-video-processing
SQS_VIDEO_PROCESSING_DLQ_URL=http://localhost:4566/000000000000/xtube-video-processing-dlq
SQS_THUMBNAIL_PROCESSING_URL=http://localhost:4566/000000000000/xtube-thumbnail-processing
```

This file should be used by the XTube services during local development.

It is ignored by Git.

## Validating the Infrastructure

List all buckets:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
```

List all queues:

```bash
aws --endpoint-url=http://localhost:4566 sqs list-queues
```

Upload a test file to the input bucket:

```bash
echo "test video content" > test-video.txt
aws --endpoint-url=http://localhost:4566 s3 cp test-video.txt s3://xtube-videos-input/test-video.txt
```

List files from the input bucket:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls s3://xtube-videos-input
```

Send a test message to the video processing queue:

```bash
aws --endpoint-url=http://localhost:4566 sqs send-message \
  --queue-url http://localhost:4566/000000000000/xtube-video-processing \
  --message-body '{"videoId":"test-video","bucket":"xtube-videos-input","key":"test-video.txt"}'
```

Receive messages from the queue:

```bash
aws --endpoint-url=http://localhost:4566 sqs receive-message \
  --queue-url http://localhost:4566/000000000000/xtube-video-processing
```

## Using the Generated Variables

Load the generated local environment variables:

```bash
source .env.localstack
```

Then the application can use these values:

```text
AWS_ENDPOINT_URL
AWS_REGION
AWS_DEFAULT_REGION
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
S3_BUCKET_INPUT
S3_BUCKET_OUTPUT
S3_BUCKET_THUMBNAILS
S3_BUCKET_TEMP
SQS_VIDEO_PROCESSING_URL
SQS_VIDEO_PROCESSING_DLQ_URL
SQS_THUMBNAIL_PROCESSING_URL
```

## Recommended Development Flow

Start LocalStack:

```bash
docker compose up -d
```

Initialize the infrastructure:

```bash
chmod +x setup.sh
./setup.sh
```

Load the generated environment variables:

```bash
source .env.localstack
```

Run the XTube services locally.

## Restarting the Infrastructure

Stop the containers:

```bash
docker compose down
```

Start again:

```bash
docker compose up -d
```

Because persistence is enabled, LocalStack data is stored in:

```text
./xtube-infra-aws
```

## Resetting the Infrastructure

To fully remove the local AWS data:

```bash
docker compose down
sudo rm -rf xtube-infra-aws
rm -f .env.localstack
```

Then start again:

```bash
docker compose up -d
./setup.sh
```

## Git Ignored Files

The following files and directories are ignored:

```text
.env
.env.localstack
xtube-infra-aws
```

This prevents local credentials, generated configuration, and LocalStack persisted data from being committed.

## Troubleshooting

### AWS CLI not found

If you see:

```text
aws: command not found
```

Install AWS CLI first.

On Linux x86_64:

```bash
sudo apt update
sudo apt install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

### LocalStack fails because the Auth Token is missing

If the LocalStack container does not start correctly, check whether the `.env` file exists and contains:

```env
LOCALSTACK_AUTH_TOKEN=your-localstack-auth-token
```

Then restart the container:

```bash
docker compose down
docker compose up -d
```

Check the logs:

```bash
docker logs -f xtube-infra-aws
```

### LocalStack is not responding

Check if the container is running:

```bash
docker ps
```

Check the logs:

```bash
docker logs -f xtube-infra-aws
```

Test the endpoint:

```bash
curl http://localhost:4566/_localstack/health
```

### Bucket or queue already exists

The setup script is idempotent.

If a bucket or queue already exists, the script will not recreate it. It will reuse the existing resource.

### Permission denied when running setup.sh

Run:

```bash
chmod +x setup.sh
```

Then execute again:

```bash
./setup.sh
```

### Cannot connect to the Docker daemon

If you see a Docker daemon error, start Docker:

```bash
sudo service docker start
```

Or, depending on your system:

```bash
sudo systemctl start docker
```

Then run:

```bash
docker ps
```

## Architecture

```text
XTube Services
      |
      | AWS SDK
      v
LocalStack
      |
      |-- S3
      |   |-- xtube-videos-input
      |   |-- xtube-videos-output
      |   |-- xtube-thumbnails
      |   |-- xtube-temp
      |
      |-- SQS
          |-- xtube-video-processing
          |-- xtube-video-processing-dlq
          |-- xtube-thumbnail-processing
```

## Purpose

This setup allows XTube to run its video infrastructure locally without using real AWS resources.

It is intended for:

- Local development
- Integration testing
- Queue-based video processing simulation
- S3 upload and retrieval testing
- Worker pipeline validation