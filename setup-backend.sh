#!/bin/bash

# CashSense AWS Backend Setup Script
# This script helps you set up the backend environment for AWS services

echo "========================================"
echo "CashSense AWS Backend Setup"
echo "========================================"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

echo "✅ Node.js $(node --version) detected"
echo ""

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is not installed. Please install npm first."
    exit 1
fi

echo "✅ npm $(npm --version) detected"
echo ""

# Navigate to backend directory
cd "$(dirname "$0")/cashsense-backend" || exit

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo "❌ package.json not found. Creating default package.json..."
    cat > package.json << 'EOF'
{
  "name": "cashsense-backend",
  "version": "1.0.0",
  "description": "Backend API for CashSense Flutter App with AWS integration",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "echo \"No tests specified\" && exit 0"
  },
  "keywords": ["cashsense", "aws", "backend", "api"],
  "author": "DHD Software",
  "license": "MIT",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "aws-sdk": "^2.1490.0",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
EOF
    echo "✅ Created package.json"
fi

# Install dependencies
echo "📦 Installing dependencies..."
npm install

if [ $? -eq 0 ]; then
    echo "✅ Dependencies installed successfully"
else
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo ""

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "⚠️  .env file not found. Creating template..."
    cat > .env << 'EOF'
# AWS Configuration
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here

# S3 Configuration
S3_BUCKET=cashsense-backups

# DynamoDB Tables
DYNAMODB_USERS_TABLE=cashsense-users
DYNAMODB_TRANSACTIONS_TABLE=cashsense-transactions
DYNAMODB_CATEGORIES_TABLE=cashsense-categories
DYNAMODB_ACCOUNTS_TABLE=cashsense-accounts
DYNAMODB_BILLS_TABLE=cashsense-bills

# SNS Configuration
SNS_ANDROID_ARN=your_android_platform_application_arn
SNS_IOS_ARN=your_ios_platform_application_arn

# Cognito Configuration
COGNITO_USER_POOL_ID=your_user_pool_id
COGNITO_CLIENT_ID=your_client_id
COGNITO_REGION=us-east-1

# Server Configuration
PORT=3000
NODE_ENV=development
EOF
    echo "✅ Created .env template"
    echo ""
    echo "⚠️  IMPORTANT: Edit .env file and add your AWS credentials!"
    echo "   1. Open .env in a text editor"
    echo "   2. Replace 'your_access_key_here' with your AWS Access Key"
    echo "   3. Replace 'your_secret_key_here' with your AWS Secret Key"
    echo "   4. Update other AWS resource ARNs as needed"
    echo ""
else
    echo "✅ .env file already exists"
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Edit .env file with your AWS credentials"
echo "2. Create AWS resources (S3 bucket, DynamoDB tables, etc.)"
echo "3. Run: npm start"
echo ""
echo "For detailed setup instructions, see AWS_BACKUP_SETUP.md"
echo ""
