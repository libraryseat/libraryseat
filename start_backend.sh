#!/bin/bash

# Backend Service Startup Script

echo "=== Starting Backend Service ==="
echo ""

# Navigate to backend directory
cd "$(dirname "$0")/BACKEND" || exit 1

# Check conda environment
if ! conda info --envs | grep -q "YOLO"; then
    echo "Error: YOLO conda environment does not exist"
    echo "Please create environment first: conda create -n YOLO python=3.9 -y"
    exit 1
fi

# Activate conda environment
echo "Activating YOLO conda environment..."
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate YOLO

# Check dependencies
if ! python -c "import fastapi" 2>/dev/null; then
    echo "Warning: fastapi not installed, installing dependencies..."
    pip install -r requirements.txt
fi

# Check if port is occupied
if lsof -ti:8000 > /dev/null 2>&1; then
    echo "Warning: Port 8000 is already in use"
    echo "Stopping process using the port..."
    kill -9 $(lsof -ti:8000) 2>/dev/null
    sleep 2
fi

# Start server
echo ""
echo "Starting Backend Server..."
echo "Access URL: http://localhost:8000"
echo "API Docs: http://localhost:8000/docs"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

