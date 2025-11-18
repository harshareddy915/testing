# Harness Pipeline Setup Guide - Node.js to S3

## Overview
This guide helps you set up a Harness CI pipeline to build, package, and deploy Node.js applications to AWS S3.

## Prerequisites

### 1. Harness Account Setup
- Active Harness account with CI module enabled
- Project created in Harness
- GitHub connector configured

### 2. AWS Setup
- AWS account with S3 access
- S3 bucket created for storing artifacts
- IAM user with appropriate permissions

### 3. Repository Setup
- Node.js application in GitHub
- `package.json` with build script
- `.gitignore` properly configured

## Step-by-Step Setup

### Step 1: Configure AWS Secrets in Harness

1. Navigate to your project in Harness
2. Go to **Project Settings** → **Secrets**
3. Create the following secrets:

**AWS Access Key ID:**
- Name: `aws_access_key_id`
- Type: Text
- Value: Your AWS access key

**AWS Secret Access Key:**
- Name: `aws_secret_access_key`
- Type: Text
- Value: Your AWS secret key

### Step 2: Configure GitHub Connector

1. Go to **Project Settings** → **Connectors**
2. Create a new **GitHub** connector:
   - Name: `Github` (or update in pipeline YAML)
   - URL: `https://github.com`
   - Authentication: Use SSH or Personal Access Token
   - Test connection

### Step 3: Create S3 Bucket

```bash
# Using AWS CLI
aws s3 mb s3://your-app-builds --region us-east-1

# Set bucket policy (adjust as needed)
aws s3api put-bucket-versioning \
  --bucket your-app-builds \
  --versioning-configuration Status=Enabled
```

### Step 4: Configure IAM Permissions

Create an IAM policy with the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-app-builds",
        "arn:aws:s3:::your-app-builds/*"
      ]
    }
  ]
}
```

### Step 5: Import Pipeline to Harness

1. Copy the pipeline YAML file
2. In Harness, go to **Pipelines** → **Create Pipeline**
3. Choose **Import From Git** or paste YAML directly
4. Update the following fields:
   - `connectorRef`: Your GitHub connector name
   - `projectIdentifier`: Your project ID
   - `orgIdentifier`: Your organization ID

### Step 6: Configure Pipeline Variables

When running the pipeline, provide:

**Basic Pipeline:**
- `s3_bucket`: Your S3 bucket name (e.g., `my-app-builds`)

**Advanced Pipeline:**
- `app_name`: Your application name (e.g., `my-node-app`)
- `s3_bucket`: Your S3 bucket name
- `s3_prefix`: Folder path in S3 (default: `builds`)
- `aws_region`: AWS region (default: `us-east-1`)
- `environment`: Environment (dev/staging/prod)

## Pipeline Features

### Basic Pipeline (`node-s3-pipeline.yaml`)
- Install npm dependencies
- Run tests (optional)
- Build application
- Create tar.gz package
- Upload to S3
- Upload "latest" version

### Advanced Pipeline (`node-s3-pipeline-advanced.yaml`)
- Environment setup and validation
- Dependency installation with caching
- Code linting
- Unit tests with coverage
- Production build
- Package with metadata
- Metadata JSON generation
- S3 upload with tags
- Upload verification
- Cleanup

## Package Structure

The pipeline creates packages with the following structure:

**Basic:**
```
node-app-20241117-143022.tar.gz
├── package.json
├── package-lock.json
├── dist/
└── node_modules/
```

**Advanced:**
```
myapp-main-a1b2c3d4-build123.tar.gz
├── package.json
├── package-lock.json
├── dist/
└── node_modules/

myapp-main-a1b2c3d4-build123.tar.gz.metadata.json
{
  "application": "myapp",
  "version": "1.0.0",
  "branch": "main",
  "commit": "a1b2c3d4...",
  "buildNumber": "123",
  ...
}
```

## S3 Structure

**Basic Pipeline:**
```
s3://your-bucket/
└── builds/
    ├── node-app-20241117-143022.tar.gz
    └── node-app-latest.tar.gz
```

**Advanced Pipeline:**
```
s3://your-bucket/
└── builds/
    └── prod/
        └── main/
            ├── myapp-main-a1b2c3d4-build123.tar.gz
            ├── myapp-main-a1b2c3d4-build123.tar.gz.metadata.json
            ├── latest.tar.gz
            └── latest.metadata.json
```

## Customization Options

### 1. Change Node Version
```yaml
image: node:20-alpine  # or node:16-alpine, node:latest
```

### 2. Add Build Environment Variables
```yaml
envVariables:
  NODE_ENV: production
  API_URL: https://api.example.com
```

### 3. Customize Package Contents
```yaml
tar -czf ${PACKAGE_NAME} \
  package.json \
  dist/ \
  config/ \
  public/
```

### 4. Add Slack Notifications
```yaml
- step:
    type: Run
    name: Notify Slack
    identifier: notify_slack
    spec:
      command: |
        curl -X POST $SLACK_WEBHOOK_URL \
          -H 'Content-Type: application/json' \
          -d '{"text":"Build completed: ${S3_URL}"}'
```

### 5. Add Deployment Stage
```yaml
- stage:
    name: Deploy to Server
    identifier: deploy
    type: Custom
    spec:
      execution:
        steps:
          - step:
              type: Run
              name: Download and Extract
              spec:
                command: |
                  aws s3 cp ${S3_URL} ./package.tar.gz
                  tar -xzf package.tar.gz
                  npm start
```

## Troubleshooting

### Issue: Dependencies fail to install
**Solution:** Check package-lock.json is committed and use `npm ci` instead of `npm install`

### Issue: Build fails with memory error
**Solution:** Increase Node memory limit:
```yaml
envVariables:
  NODE_OPTIONS: --max_old_space_size=4096
```

### Issue: S3 upload fails with credentials error
**Solution:** Verify secrets are correctly configured and IAM permissions are set

### Issue: Package is too large
**Solution:** Exclude unnecessary files:
```yaml
tar -czf ${PACKAGE_NAME} \
  --exclude='tests' \
  --exclude='coverage' \
  --exclude='*.md' \
  package.json dist/
```

## Testing the Pipeline

### 1. Test with a feature branch
```bash
git checkout -b test-pipeline
git push origin test-pipeline
```

### 2. Run the pipeline in Harness UI
- Select the pipeline
- Click "Run"
- Choose the branch
- Provide required inputs
- Monitor execution

### 3. Verify S3 upload
```bash
aws s3 ls s3://your-bucket/builds/ --recursive --human-readable
```

### 4. Download and test package
```bash
aws s3 cp s3://your-bucket/builds/your-package.tar.gz ./
tar -xzf your-package.tar.gz
cd dist && npm start
```

## Best Practices

1. **Use npm ci for reproducible builds**
2. **Version your packages with git commit SHA**
3. **Store metadata with each build**
4. **Enable S3 versioning for rollback capability**
5. **Use different S3 paths for each environment**
6. **Implement artifact retention policies**
7. **Run tests before building**
8. **Use secrets for all credentials**
9. **Add build notifications**
10. **Monitor pipeline execution times**

## Next Steps

1. Add integration tests
2. Implement deployment automation
3. Set up rollback mechanism
4. Add performance monitoring
5. Configure alerts for failed builds
6. Implement artifact cleanup policies
7. Add security scanning (npm audit)
8. Set up multi-environment deployments

## Support

- Harness Documentation: https://docs.harness.io
- AWS S3 Documentation: https://docs.aws.amazon.com/s3
- Node.js Best Practices: https://nodejs.org/en/docs/guides
