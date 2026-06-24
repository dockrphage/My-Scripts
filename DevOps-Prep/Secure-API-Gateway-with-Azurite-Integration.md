Turning a simple "API Gateway" into a powerful demonstration of advanced engineering and DevOps principles.

### 🏗️ Architecture Overview

We are building a **secure, observable, and resilient API Gateway** that processes and stores data locally. The architecture leverages four key components:

*   **API Layer**: A FastAPI application acting as the Gateway. It will handle authentication, request validation, and business logic.
*   **Middleware Stack**: A series of middleware components for logging (with sensitive data masking), rate limiting, and request tracking.
*   **Storage Emulator**: **Azurite**, the official local emulator for Azure Storage, providing Blob and Table storage services without cloud costs.
*   **Container Orchestration**: **Docker Compose** will define and run the entire stack (FastAPI app and Azurite) as a single, portable application.

### 🗺️ The Progressive 5-Phase Implementation Plan

#### Phase 0: Environment Setup & Infrastructure as Code (IaC)
*Focus: Creating a reproducible, version-controlled local environment.*

1.  **Initialize Project**: Create a Git repository with a standard project structure (`/src`, `/docker`, `/scripts`, `/tests`). This establishes a code-first approach.
2.  **Define the Stack with Docker Compose**: Create a `docker-compose.yaml` file.
    *   **Azurite Service**: Define the container using `mcr.microsoft.com/azure-storage/azurite`. Expose ports `10000` (Blob), `10001` (Queue), and `10002` (Table) for local access.
    *   **FastAPI Service**: Define the application container, mounting your local source code for live development. It will depend on the Azurite service.
3.  **Validate Local Connectivity**: Write a simple Python script to connect to Azurite using the standard development connection string and verify it can create a test table. This confirms your local Azure emulator is working correctly.

#### Phase 1: The Core Gateway API
*Focus: Building a functional API with a data access layer.*

1.  **Define Data Models**: Create Pydantic models for the data you will process (e.g., a `WorkflowRequest` with fields like `id`, `payload`, and `source`).
2.  **Implement CRUD Endpoints**: Develop the core `POST /workflows` endpoint. The endpoint should validate the incoming data against your Pydantic model.
3.  **Integrate Azurite Table Storage**: Implement logic to save the validated request data into an Azurite Table. This involves using the `azure-data-tables` package with the local connection string. This step demonstrates the "Storage" part of the architecture.
4.  **Implement Blob Storage for Payloads**: For larger or complex data, modify the endpoint to store the full request payload in an Azurite Blob container. The Table entry then stores a reference (URL) to the blob. This models a common data partitioning pattern.

#### Phase 2: Advanced Middleware & Observability
*Focus: Building a production-ready gateway with logging and security.*

1.  **Implement Request Logging Middleware**:
    *   Create a custom middleware to log all incoming requests and outgoing responses.
    *   **Crucially, implement sensitive data masking**. The middleware should redact values for keys like `password`, `token`, `authorization`, or `secret` from logs using pattern matching or a predefined list.
    *   Ensure it logs the duration of each request for performance monitoring. The `TimingMiddleware` from community examples provides a good reference for this.
2.  **Add Distributed Tracing (Correlation ID)**:
    *   Implement a middleware that checks for an incoming `X-Correlation-ID` header. If present, it uses it; if not, it generates a UUID.
    *   Inject this ID into the application's logger context (e.g., using `structlog` or `logging.LoggerAdapter`). This ensures every log entry from a request has the same trace ID, a *critical pattern for debugging in a microservices architecture*.
3.  **Implement Request Validation Error Handling**:
    *   Override FastAPI's default `RequestValidationError` handler. When invalid data is sent, the handler should log the full request body (for debugging) and return a structured, standardized error response to the client. This pattern is essential for developer experience (DX).

#### Phase 3: Security & Control Plane
*Focus: Simulating Azure's security features and policy enforcement.*

1.  **Implement Simple API Key Authentication**:
    *   Create a middleware to validate a static API key provided in the `X-API-Key` header. This simulates an Azure API Management (APIM) policy for checking subscription keys.
    *   Reject requests without a valid key with a `403 Forbidden` response.
2.  **Implement a "Policy as Code" Check**:
    *   Write a custom dependency or middleware that enforces a simple local policy (e.g., "A request cannot have a source of 'external' and a payload size over 10KB").
    *   This simulates the Azure Policy or APIM policy engine, demonstrating how you can enforce governance and compliance rules at the application layer.

#### Phase 4: Performance & Resilience Engineering
*Focus: Demonstrating advanced operational capabilities.*

1.  **Implement Rate Limiting**:
    *   Integrate a token-bucket algorithm (e.g., using `slowapi` or a custom in-memory store) to limit requests per client IP address. This simulates APIM's throttling policies.
2.  **Simulate Asynchronous Processing**:
    *   Modify the `POST /workflows` endpoint to not process data immediately. Instead, it should write the job to an Azurite Queue.
    *   Create a **background worker** (a separate Python script or FastAPI `BackgroundTask`) that polls this queue and "processes" the data.
    *   Return a `202 Accepted` response with a `location` header pointing to a status endpoint. This demonstrates how to build decoupled, resilient systems.

### 🎙️ The DevOps Interview Articulation Perspective


*   **Infrastructure as Code & Reproducibility**: Emphasize that the entire environment is defined in code (`docker-compose.yaml`), making it shareable and ensuring a consistent developer experience. The connection to Azurite is seamless, mimicking production[6][9].
*   **Zero-Trust & Observability**: Point to the middleware stack. You built for security (auth, policy checks, data masking) and observability (structured logs, correlation IDs) from day one, not as an afterthought.
*   **API Management Fundamentals**: This architecture directly mirrors Azure API Management's core functions: a gateway to enforce security, policies, and rate limiting, while providing a clean API façade.
*   **Hybrid and Multi-Cloud Readiness**: By using Docker and emulators, the solution is platform-agnostic. The same code can be deployed to Azure (using real Storage) or another cloud, showcasing adaptability and a "cloud-agnostic" design philosophy.












# 🚀 Secure API Gateway with Azurite Integration
## Complete Progressive Implementation Guide

---

## 📋 Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Phase 0: Project Setup](#phase-0-project-setup)
4. [Phase 1: Core API Gateway](#phase-1-core-api-gateway)
5. [Phase 2: Middleware & Security](#phase-2-middleware--security)
6. [Phase 3: Azurite Integration](#phase-3-azurite-integration)
7. [Phase 4: Advanced Features](#phase-4-advanced-features)
8. [Phase 5: Production Readiness](#phase-5-production-readiness)
9. [Testing & Validation](#testing--validation)
10. [Troubleshooting Guide](#troubleshooting-guide)

---

## Architecture Overview

### System Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    API Gateway                              │
├─────────────────────────────────────────────────────────────┤
│  FastAPI Application                                        │
│  ├── API Key Authentication (Middleware)                   │
│  ├── Rate Limiting (5 req/min)                            │
│  ├── Request/Response Logging (Correlation IDs)           │
│  └── CRUD Endpoints (/api/v1/workflows)                   │
├─────────────────────────────────────────────────────────────┤
│  Storage Layer                                              │
│  ├── Azurite (Local Azure Emulator)                       │
│  │   ├── Table Storage (workflowrecords)                  │
│  │   ├── Blob Storage (workflow-payloads)                 │
│  │   └── Queue Storage (workflow-queue)                   │
│  └── In-Memory (Fallback)                                 │
├─────────────────────────────────────────────────────────────┤
│  Deployment                                                 │
│  ├── Docker Compose                                        │
│  ├── Git Version Control                                   │
│  └── Hot Reload for Development                            │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack
- **API Framework**: FastAPI 0.104.1
- **Server**: Uvicorn 0.24.0
- **Storage**: Azurite (Azure Emulator)
- **Container**: Docker & Docker Compose
- **Language**: Python 3.11
- **Version Control**: Git

---

## Prerequisites

### Required Software
```bash
# Install Docker & Docker Compose
docker --version
docker-compose --version

# Install Python 3.11+
python3 --version

# Install Git
git --version

# Install curl for testing
curl --version
```

### System Requirements
- **CPU**: 2+ cores
- **RAM**: 4GB+ (8GB recommended)
- **Storage**: 10GB free space
- **OS**: Linux, macOS, or Windows (with WSL2)

### Project Directory Structure
```
azure-secure-api-gateway/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── storage_service.py   # Azure Storage integration
│   ├── api/
│   │   ├── __init__.py
│   │   └── v1/
│   │       ├── __init__.py
│   │       └── endpoints.py
│   └── middleware/
│       ├── __init__.py
│       └── auth.py
├── docker-compose.yaml
├── Dockerfile
├── requirements.txt
└── test_api.sh
```

---

## Phase 0: Project Setup

### Step 0.1: Initialize Project
```bash
# Create project directory
mkdir azure-secure-api-gateway
cd azure-secure-api-gateway

# Initialize Git repository
git init

# Create Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Create project structure
mkdir -p app/api/v1 app/middleware
touch app/__init__.py app/main.py
touch app/api/__init__.py app/api/v1/__init__.py
touch app/middleware/__init__.py
```

### Step 0.2: Create Requirements File
```bash
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
python-dotenv==1.0.0
six==1.16.0
azure-storage-blob==12.19.0
azure-storage-queue==12.8.0
azure-data-tables==12.4.0
cryptography==41.0.7
certifi==2023.11.17
charset-normalizer==3.3.2
idna==3.6
urllib3==2.1.0
requests==2.31.0
EOF
```

### Step 0.3: Create Dockerfile
```bash
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Azure SDK dependencies explicitly
RUN pip install --no-cache-dir \
    six \
    azure-storage-blob \
    azure-storage-queue \
    azure-data-tables

# Copy application code
COPY ./app /app

# Set Python path
ENV PYTHONPATH=/app

# Expose port
EXPOSE 8000

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF
```

### Step 0.4: Create Docker Compose Configuration
```bash
cat > docker-compose.yaml << 'EOF'
version: '3.8'

services:
  azurite:
    image: mcr.microsoft.com/azure-storage/azurite:latest
    container_name: azurite
    hostname: azurite
    ports:
      - "10000:10000"  # Blob
      - "10001:10001"  # Queue
      - "10002:10002"  # Table
    volumes:
      - azurite_data:/data
    command: "azurite --silent --location /data --debug /data/debug.log --blobHost 0.0.0.0 --queueHost 0.0.0.0 --tableHost 0.0.0.0"
    restart: unless-stopped
    networks:
      - app-network

  api-gateway:
    build: .
    container_name: api-gateway
    ports:
      - "8000:8000"
    environment:
      - PYTHONUNBUFFERED=1
      - API_KEYS=dev-key-1,dev-key-2,test-key
      - AZURITE_CONNECTION_STRING=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;QueueEndpoint=http://azurite:10001/devstoreaccount1;TableEndpoint=http://azurite:10002/devstoreaccount1;
    depends_on:
      - azurite
    restart: unless-stopped
    volumes:
      - ./app:/app
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  azurite_data:
EOF
```

### Step 0.5: Create .gitignore
```bash
cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
.venv/
env/
venv/
ENV/
env.bak/
venv.bak/

# Docker
*.log
*.pid
*.pid.lock

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Application
*.db
*.sqlite3
azurite_data/
EOF
```

---

## Phase 1: Core API Gateway

### Step 1.1: Create Storage Service
```bash
cat > app/storage_service.py << 'EOF'
import os
import json
import logging
from typing import Optional, Dict, Any, List
from datetime import datetime
import uuid

logger = logging.getLogger(__name__)

class AzureStorageService:
    def __init__(self):
        self.connection_string = os.getenv(
            "AZURITE_CONNECTION_STRING",
            "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;QueueEndpoint=http://azurite:10001/devstoreaccount1;TableEndpoint=http://azurite:10002/devstoreaccount1;"
        )
        self._initialized = False
        self.blob_client = None
        self.queue_client = None
        self.table_client = None
        self._init_clients()
        
    def _init_clients(self):
        """Initialize Azure Storage clients"""
        try:
            from azure.storage.blob import BlobServiceClient
            from azure.storage.queue import QueueServiceClient
            from azure.data.tables import TableServiceClient
            
            # Create clients
            self.blob_client = BlobServiceClient.from_connection_string(self.connection_string)
            self.queue_client = QueueServiceClient.from_connection_string(self.connection_string)
            self.table_client = TableServiceClient.from_connection_string(self.connection_string)
            
            # Create containers/tables
            try:
                self.blob_client.create_container("workflow-payloads")
                logger.info("✅ Created blob container: workflow-payloads")
            except Exception as e:
                if "ContainerAlreadyExists" in str(e) or "already exists" in str(e):
                    logger.info("✅ Blob container already exists: workflow-payloads")
            
            try:
                self.queue_client.create_queue("workflow-queue")
                logger.info("✅ Created queue: workflow-queue")
            except Exception as e:
                if "QueueAlreadyExists" in str(e) or "already exists" in str(e):
                    logger.info("✅ Queue already exists: workflow-queue")
            
            # Table names must be alphanumeric (no hyphens!)
            try:
                self.table_client.create_table("workflowrecords")
                logger.info("✅ Created table: workflowrecords")
            except Exception as e:
                if "TableAlreadyExists" in str(e) or "already exists" in str(e):
                    logger.info("✅ Table already exists: workflowrecords")
            
            self._initialized = True
            logger.info("✅ Azure Storage clients initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to initialize Azure Storage: {e}")
            self._initialized = False
            return False

    def is_available(self) -> bool:
        return self._initialized

    def store_workflow(self, workflow) -> Dict[str, Any]:
        if not self._initialized:
            return {"stored": False, "mode": "memory", "id": workflow.id}
        
        try:
            table = self.table_client.get_table_client("workflowrecords")
            
            entity = {
                "PartitionKey": workflow.source,
                "RowKey": workflow.id,
                "payload": json.dumps(workflow.payload),
                "created_at": datetime.utcnow().isoformat(),
                "status": "active"
            }
            
            table.create_entity(entity=entity)
            logger.info(f"✅ Workflow {workflow.id} stored in Table Storage")
            
            # Store payload in Blob Storage
            try:
                blob_container = self.blob_client.get_container_client("workflow-payloads")
                blob_name = f"{workflow.id}/{uuid.uuid4()}.json"
                blob_container.upload_blob(
                    blob_name,
                    json.dumps(workflow.payload).encode('utf-8'),
                    overwrite=True
                )
                logger.info(f"✅ Payload stored in Blob: {blob_name}")
            except Exception as e:
                logger.warning(f"⚠️ Could not store in Blob: {e}")
            
            return {
                "stored": True,
                "mode": "azurite",
                "id": workflow.id,
                "location": "table-storage"
            }
            
        except Exception as e:
            logger.error(f"❌ Error storing workflow: {e}")
            return {"stored": False, "mode": "memory", "id": workflow.id, "error": str(e)}

    def get_workflow(self, workflow_id: str) -> Optional[Dict[str, Any]]:
        if not self._initialized:
            return None
            
        try:
            table = self.table_client.get_table_client("workflowrecords")
            entities = list(table.query_entities(f"RowKey eq '{workflow_id}'"))
            
            if entities:
                entity = dict(entities[0])
                if "payload" in entity and isinstance(entity["payload"], str):
                    try:
                        entity["payload"] = json.loads(entity["payload"])
                    except:
                        pass
                return entity
            return None
            
        except Exception as e:
            logger.error(f"❌ Error retrieving workflow: {e}")
            return None

    def delete_workflow(self, workflow_id: str) -> bool:
        if not self._initialized:
            return False
            
        try:
            table = self.table_client.get_table_client("workflowrecords")
            entities = list(table.query_entities(f"RowKey eq '{workflow_id}'"))
            if not entities:
                return False
            
            entity = entities[0]
            table.delete_entity(
                partition_key=entity.get("PartitionKey"),
                row_key=entity.get("RowKey")
            )
            logger.info(f"✅ Workflow {workflow_id} deleted from Table Storage")
            return True
            
        except Exception as e:
            logger.error(f"❌ Error deleting workflow: {e}")
            return False

    def list_workflows(self, limit: int = 100) -> List[Dict[str, Any]]:
        if not self._initialized:
            return []
            
        try:
            table = self.table_client.get_table_client("workflowrecords")
            entities = list(table.query_entities(query_filter=None, results_per_page=limit))
            
            results = []
            for entity in entities:
                item = dict(entity)
                if "payload" in item and isinstance(item["payload"], str):
                    try:
                        item["payload"] = json.loads(item["payload"])
                    except:
                        pass
                results.append(item)
            
            return results
            
        except Exception as e:
            logger.error(f"❌ Error listing workflows: {e}")
            return []
EOF
```

### Step 1.2: Create Main Application
```bash
cat > app/main.py << 'EOF'
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import logging
import uuid
import time
from datetime import datetime
from typing import Dict, List, Optional
import json
import os
import sys

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="Secure API Gateway",
    version="1.0.0",
    description="A secure API Gateway with Azure Storage integration"
)

# In-memory storage (fallback)
memory_storage: Dict[str, Dict] = {}

# Import Azure Storage Service
storage_available = False
storage_service = None

try:
    from storage_service import AzureStorageService
    storage_service = AzureStorageService()
    storage_available = storage_service.is_available()
    
    if storage_available:
        logger.info("✅ Azure Storage (Azurite) connected successfully")
    else:
        logger.warning("⚠️ Azure Storage initialized but not available")
        
except ImportError as e:
    logger.warning(f"⚠️ Could not import Azure Storage service: {e}")
    storage_service = None
    storage_available = False
except Exception as e:
    logger.warning(f"⚠️ Could not initialize Azure Storage: {e}")
    storage_service = None
    storage_available = False

if not storage_available:
    logger.info("📦 Using in-memory storage")

# Request/Response Models
class WorkflowRequest(BaseModel):
    id: str
    payload: dict
    source: str

class WorkflowResponse(BaseModel):
    message: str
    workflow_id: str
    timestamp: str
    status: str = "processed"
    storage_mode: str = "memory"

# Rate limiting
request_counts: Dict[str, List[float]] = {}
RATE_LIMIT = 5  # requests
TIME_WINDOW = 60  # seconds

def is_rate_limited(client_ip: str) -> bool:
    current_time = time.time()
    
    if client_ip in request_counts:
        request_counts[client_ip] = [
            t for t in request_counts[client_ip] 
            if current_time - t < TIME_WINDOW
        ]
    else:
        request_counts[client_ip] = []
    
    if len(request_counts[client_ip]) >= RATE_LIMIT:
        return True
    
    request_counts[client_ip].append(current_time)
    return False

# Middleware: Logging & Rate Limiting
@app.middleware("http")
async def log_and_rate_limit_requests(request: Request, call_next):
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    client_ip = request.client.host if request.client else "unknown"
    
    # Skip rate limiting for health and docs
    if request.url.path not in ["/", "/health", "/docs", "/redoc", "/openapi.json"]:
        if is_rate_limited(client_ip):
            logger.warning(f"🚫 Rate limit exceeded for {client_ip}")
            return JSONResponse(
                status_code=429,
                content={
                    "detail": "Too many requests. Please try again later.",
                    "retry_after": TIME_WINDOW
                }
            )
    
    start_time = time.time()
    logger.info(f"📥 {request.method} {request.url.path} | CID: {correlation_id} | IP: {client_ip}")
    
    try:
        response = await call_next(request)
        process_time = time.time() - start_time
        logger.info(f"📤 {response.status_code} | {process_time:.3f}s | CID: {correlation_id}")
        
        response.headers["X-Correlation-ID"] = correlation_id
        response.headers["X-Process-Time"] = str(process_time)
        return response
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"}
        )

# Middleware: API Key Validation
API_KEYS = set(os.getenv("API_KEYS", "dev-key-1,dev-key-2,test-key").split(","))

@app.middleware("http")
async def api_key_middleware(request: Request, call_next):
    if request.url.path in ["/", "/health", "/docs", "/redoc", "/openapi.json"]:
        return await call_next(request)
    
    if request.url.path == "/favicon.ico":
        return JSONResponse(status_code=404, content={"detail": "Not found"})
    
    api_key = request.headers.get("X-API-Key")
    if not api_key or api_key not in API_KEYS:
        logger.warning(f"🔑 Invalid API key for {request.url.path}")
        return JSONResponse(
            status_code=403,
            content={"detail": "Invalid or missing API Key"}
        )
    
    return await call_next(request)

# Health Check
@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "api-gateway",
        "version": "1.0.0",
        "storage": "azurite" if storage_available else "memory",
        "timestamp": datetime.utcnow().isoformat()
    }

# Root
@app.get("/")
async def root():
    return {
        "message": "Secure API Gateway",
        "version": "1.0.0",
        "storage": "azurite" if storage_available else "memory",
        "docs": "/docs",
        "health": "/health",
        "endpoints": {
            "POST /api/v1/workflows": "Create workflow",
            "GET /api/v1/workflows": "List workflows",
            "GET /api/v1/workflows/{id}": "Get workflow",
            "DELETE /api/v1/workflows/{id}": "Delete workflow"
        }
    }

# API Endpoints
@app.post("/api/v1/workflows", response_model=WorkflowResponse)
async def create_workflow(workflow: WorkflowRequest):
    try:
        logger.info(f"📝 Creating workflow: {workflow.id} from {workflow.source}")
        
        storage_mode = "memory"
        
        if storage_available and storage_service:
            result = storage_service.store_workflow(workflow)
            if result.get("stored"):
                storage_mode = "azurite"
                logger.info(f"✅ Workflow {workflow.id} stored in Azurite")
            else:
                memory_storage[workflow.id] = {
                    "id": workflow.id,
                    "payload": workflow.payload,
                    "source": workflow.source,
                    "created_at": datetime.utcnow().isoformat(),
                    "status": "active"
                }
                storage_mode = result.get("mode", "memory")
                logger.info(f"⚠️ Azurite storage failed, using memory mode")
        else:
            memory_storage[workflow.id] = {
                "id": workflow.id,
                "payload": workflow.payload,
                "source": workflow.source,
                "created_at": datetime.utcnow().isoformat(),
                "status": "active"
            }
            logger.info(f"📦 Workflow {workflow.id} stored in memory")
        
        return WorkflowResponse(
            message="Workflow created successfully",
            workflow_id=workflow.id,
            timestamp=datetime.utcnow().isoformat(),
            status="active",
            storage_mode=storage_mode
        )
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/workflows")
async def list_workflows():
    try:
        if storage_available and storage_service:
            workflows = storage_service.list_workflows()
            if workflows:
                return {
                    "workflows": workflows,
                    "count": len(workflows),
                    "source": "azurite"
                }
        
        return {
            "workflows": list(memory_storage.values()),
            "count": len(memory_storage),
            "source": "memory"
        }
    except Exception as e:
        logger.error(f"❌ Error listing workflows: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/workflows/{workflow_id}")
async def get_workflow(workflow_id: str):
    try:
        if storage_available and storage_service:
            result = storage_service.get_workflow(workflow_id)
            if result:
                result["source"] = "azurite"
                return result
        
        if workflow_id in memory_storage:
            memory_storage[workflow_id]["source"] = "memory"
            return memory_storage[workflow_id]
        
        raise HTTPException(status_code=404, detail=f"Workflow {workflow_id} not found")
    except Exception as e:
        logger.error(f"❌ Error getting workflow: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/v1/workflows/{workflow_id}")
async def delete_workflow(workflow_id: str):
    try:
        deleted = False
        
        if storage_available and storage_service:
            deleted = storage_service.delete_workflow(workflow_id)
        
        if workflow_id in memory_storage:
            del memory_storage[workflow_id]
            deleted = True
        
        if not deleted:
            raise HTTPException(status_code=404, detail=f"Workflow {workflow_id} not found")
        
        return {"message": f"Workflow {workflow_id} deleted successfully"}
    except Exception as e:
        logger.error(f"❌ Error deleting workflow: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Startup Event
@app.on_event("startup")
async def startup_event():
    logger.info("🚀 API Gateway started")
    logger.info(f"📊 Storage: {'Azurite' if storage_available else 'Memory'}")
    logger.info(f"📊 Endpoints: {len(app.routes)}")
    logger.info(f"🔑 API Keys: {len(API_KEYS)}")

# Shutdown Event
@app.on_event("shutdown")
async def shutdown_event():
    logger.info("🛑 API Gateway shutting down")
    if storage_available:
        logger.info("📊 Data stored in Azurite")
    else:
        logger.info(f"📊 Memory workflows: {len(memory_storage)}")
EOF
```

---

## Phase 2: Middleware & Security

### Step 2.1: Create Authentication Middleware (Optional Enhancement)
```bash
cat > app/middleware/auth.py << 'EOF'
import os
import logging
from fastapi import Request, HTTPException
from fastapi.security import APIKeyHeader
from typing import Optional

logger = logging.getLogger(__name__)

# API Key Header
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

# Valid API Keys from environment
VALID_API_KEYS = set(os.getenv("API_KEYS", "dev-key-1,dev-key-2,test-key").split(","))

async def validate_api_key(request: Request) -> bool:
    """
    Validate API key from request header.
    Returns True if valid, False otherwise.
    """
    api_key = request.headers.get("X-API-Key")
    
    if not api_key:
        logger.warning("🔑 Missing API Key header")
        return False
    
    if api_key not in VALID_API_KEYS:
        logger.warning(f"🔑 Invalid API Key: {api_key[:8]}...")
        return False
    
    return True

async def get_current_api_key(request: Request) -> str:
    """
    Get and validate API key from request.
    Raises HTTPException if invalid.
    """
    api_key = request.headers.get("X-API-Key")
    
    if not api_key:
        raise HTTPException(
            status_code=403,
            detail="Missing API Key. Please provide X-API-Key header."
        )
    
    if api_key not in VALID_API_KEYS:
        raise HTTPException(
            status_code=403,
            detail="Invalid API Key. Please provide a valid key."
        )
    
    return api_key
EOF
```

### Step 2.2: Create Request Validation Models
```bash
cat > app/models/request_models.py << 'EOF'
from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Any
from datetime import datetime

class WorkflowRequest(BaseModel):
    """Workflow creation request model"""
    id: str = Field(..., description="Unique workflow ID", min_length=3, max_length=50)
    payload: Dict[str, Any] = Field(..., description="Workflow payload data")
    source: str = Field(..., description="Source of the workflow", min_length=2, max_length=20)
    
    @validator('id')
    def validate_id(cls, v):
        if not v.isalnum() and '-' not in v and '_' not in v:
            raise ValueError('ID must be alphanumeric with - or _')
        return v
    
    @validator('source')
    def validate_source(cls, v):
        if not v.isalnum() and '-' not in v:
            raise ValueError('Source must be alphanumeric with -')
        return v

class WorkflowResponse(BaseModel):
    """Workflow creation response model"""
    message: str = Field(..., description="Response message")
    workflow_id: str = Field(..., description="Workflow ID")
    timestamp: str = Field(..., description="Creation timestamp")
    status: str = Field(..., description="Workflow status")
    storage_mode: str = Field(..., description="Storage mode used (azurite/memory)")

class WorkflowUpdateRequest(BaseModel):
    """Workflow update request model"""
    payload: Optional[Dict[str, Any]] = None
    status: Optional[str] = None
    
    @validator('status')
    def validate_status(cls, v):
        if v and v not in ['active', 'paused', 'completed', 'failed']:
            raise ValueError('Status must be: active, paused, completed, failed')
        return v
EOF
```

---

## Phase 3: Azurite Integration

### Step 3.1: Verify Azurite Connection
```bash
# Test Azurite connectivity
docker exec api-gateway python3 -c "
import sys
sys.path.append('/app')
from storage_service import AzureStorageService
storage = AzureStorageService()
print(f'Azurite available: {storage.is_available()}')
"
```

### Step 3.2: Test Data Storage
```bash
# Create test workflow
curl -X POST http://localhost:8000/api/v1/workflows \
  -H "X-API-Key: dev-key-1" \
  -H "Content-Type: application/json" \
  -d '{"id":"test-azurite","payload":{"test":"data"},"source":"web"}' \
  | python3 -m json.tool

# Verify storage
curl http://localhost:8000/api/v1/workflows/test-azurite \
  -H "X-API-Key: dev-key-1" \
  | python3 -m json.tool
```

### Step 3.3: Create Test Script
```bash
cat > test_azurite.sh << 'EOF'
#!/bin/bash
echo "🔍 Testing Azurite Integration..."
echo ""

echo "1️⃣ Health Check:"
curl -s http://localhost:8000/health | python3 -m json.tool
echo ""

echo "2️⃣ Create Workflow:"
curl -s -X POST http://localhost:8000/api/v1/workflows \
  -H "X-API-Key: dev-key-1" \
  -H "Content-Type: application/json" \
  -d '{"id":"azurite-test-'$(date +%s)'","payload":{"message":"Stored in Azurite!","timestamp":"'$(date -Iseconds)'"},"source":"web"}' \
  | python3 -m json.tool
echo ""

echo "3️⃣ List Workflows:"
curl -s http://localhost:8000/api/v1/workflows \
  -H "X-API-Key: dev-key-1" \
  | python3 -m json.tool
echo ""

echo "✅ Test complete!"
EOF

chmod +x test_azurite.sh
./test_azurite.sh
```

---

## Phase 4: Advanced Features

### Step 4.1: Add Background Worker (Optional)
```bash
cat > app/worker.py << 'EOF'
import os
import json
import time
import logging
from datetime import datetime
from azure.storage.queue import QueueServiceClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_workflow(data):
    """Process a workflow from the queue"""
    logger.info(f"📋 Processing workflow: {data.get('id', 'unknown')}")
    # Add your processing logic here
    time.sleep(1)  # Simulate work
    return True

def main():
    """Main worker loop"""
    connection_string = os.getenv(
        "AZURITE_CONNECTION_STRING",
        "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;QueueEndpoint=http://azurite:10001/devstoreaccount1;TableEndpoint=http://azurite:10002/devstoreaccount1;"
    )
    
    queue_client = QueueServiceClient.from_connection_string(connection_string)
    queue = queue_client.get_queue_client("workflow-queue")
    
    logger.info("🔄 Worker started, waiting for messages...")
    
    while True:
        try:
            messages = queue.receive_messages(max_messages=10, visibility_timeout=30)
            for msg in messages:
                data = json.loads(msg.content)
                logger.info(f"📥 Received message: {data.get('id', 'unknown')}")
                
                if process_workflow(data):
                    queue.delete_message(msg)
                    logger.info(f"✅ Processed: {data.get('id', 'unknown')}")
                else:
                    logger.error(f"❌ Failed to process: {data.get('id', 'unknown')}")
                    
        except Exception as e:
            logger.error(f"❌ Worker error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
EOF
```

### Step 4.2: Add Monitoring Endpoint
```bash
# Add to main.py - monitoring endpoint
@app.get("/metrics")
async def get_metrics():
    """Get API metrics"""
    return {
        "workflows": {
            "total": len(memory_storage),
            "storage": "azurite" if storage_available else "memory"
        },
        "rate_limiting": {
            "limit": RATE_LIMIT,
            "window_seconds": TIME_WINDOW
        },
        "active_keys": len(API_KEYS)
    }
```

---

## Phase 5: Production Readiness

### Step 5.1: Environment Configuration
```bash
cat > .env.example << 'EOF'
# API Configuration
API_KEYS=prod-key-1,prod-key-2
RATE_LIMIT=100
RATE_WINDOW=60

# Azure Storage
AZURITE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=mystorageaccount;AccountKey=...
AZURE_STORAGE_ACCOUNT=mystorageaccount
AZURE_STORAGE_KEY=your-key-here

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json

# Security
SECRET_KEY=your-secret-key-here
JWT_ALGORITHM=HS256
EOF
```

### Step 5.2: Health Check Endpoint
```bash
# Enhanced health check
@app.get("/health/ready")
async def readiness_check():
    """Kubernetes readiness probe"""
    return {
        "status": "ready",
        "storage": "azurite" if storage_available else "memory",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/health/live")
async def liveness_check():
    """Kubernetes liveness probe"""
    return {"status": "alive", "timestamp": datetime.utcnow().isoformat()}
```

### Step 5.3: Docker Compose Production
```bash
cat > docker-compose.prod.yaml << 'EOF'
version: '3.8'

services:
  azurite:
    image: mcr.microsoft.com/azure-storage/azurite:latest
    container_name: azurite
    ports:
      - "10000:10000"
      - "10001:10001"
      - "10002:10002"
    volumes:
      - azurite_data:/data
    command: "azurite --silent --location /data --blobHost 0.0.0.0 --queueHost 0.0.0.0 --tableHost 0.0.0.0"
    restart: always

  api-gateway:
    build: 
      context: .
      dockerfile: Dockerfile.prod
    container_name: api-gateway
    ports:
      - "8000:8000"
    environment:
      - PYTHONUNBUFFERED=1
      - API_KEYS=${API_KEYS}
      - AZURITE_CONNECTION_STRING=${AZURITE_CONNECTION_STRING}
      - RATE_LIMIT=${RATE_LIMIT:-100}
      - RATE_WINDOW=${RATE_WINDOW:-60}
    depends_on:
      - azurite
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  azurite_data:
EOF
```

### Step 5.4: Production Dockerfile
```bash
cat > Dockerfile.prod << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Azure SDK
RUN pip install --no-cache-dir azure-storage-blob azure-storage-queue azure-data-tables

# Copy application
COPY ./app /app

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Run application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
```

---

## Testing & Validation

### Complete Test Suite
```bash
cat > test_complete.sh << 'EOF'
#!/bin/bash
echo "🚀 Complete API Gateway Test Suite"
echo "=================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test function
test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local expected=$4
    local headers=${5:-""}
    local data=${6:-""}
    
    echo -n "Testing $name... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -o /dev/null -w "%{http_code}" -H "$headers" "$url")
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" -X $method -H "$headers" -d "$data" "$url")
    fi
    
    if [ "$response" = "$expected" ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        return 0
    else
        echo -e "${RED}❌ FAIL (Expected $expected, Got $response)${NC}"
        return 1
    fi
}

# 1. Health Check
test_endpoint "Health Check" "GET" "http://localhost:8000/health" "200"

# 2. Root Endpoint
test_endpoint "Root Endpoint" "GET" "http://localhost:8000/" "200"

# 3. Authentication (Missing API Key)
test_endpoint "Auth (No Key)" "POST" "http://localhost:8000/api/v1/workflows" "403" "Content-Type: application/json" '{"id":"test","payload":{},"source":"web"}'

# 4. Create Workflow (Valid Key)
test_endpoint "Create Workflow" "POST" "http://localhost:8000/api/v1/workflows" "200" "X-API-Key: dev-key-1,Content-Type: application/json" '{"id":"test-1","payload":{"data":"test"},"source":"web"}'

# 5. Get Workflow
test_endpoint "Get Workflow" "GET" "http://localhost:8000/api/v1/workflows/test-1" "200" "X-API-Key: dev-key-1"

# 6. List Workflows
test_endpoint "List Workflows" "GET" "http://localhost:8000/api/v1/workflows" "200" "X-API-Key: dev-key-1"

# 7. Delete Workflow
test_endpoint "Delete Workflow" "DELETE" "http://localhost:8000/api/v1/workflows/test-1" "200" "X-API-Key: dev-key-1"

# 8. Rate Limiting Test
echo -n "Testing Rate Limiting... "
for i in {1..6}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8000/api/v1/workflows -H "X-API-Key: dev-key-1" -H "Content-Type: application/json" -d '{"id":"rate-'$i'","payload":{},"source":"web"}')
    if [ $i -le 5 ] && [ "$status" = "200" ]; then
        continue
    elif [ $i -eq 6 ] && [ "$status" = "429" ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        break
    else
        echo -e "${RED}❌ FAIL${NC}"
        break
    fi
done

echo ""
echo "=================================="
echo "✅ Test suite complete!"
EOF

chmod +x test_complete.sh
./test_complete.sh
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: ModuleNotFoundError: No module named 'app'
**Cause**: Python import path issue in Docker container
**Solution**:
```bash
# Fix by using direct import in main.py
from storage_service import AzureStorageService  # Instead of from app.storage_service
```

#### Issue 2: Azurite shows "memory" instead of "azurite"
**Cause**: Table name contains invalid characters
**Solution**:
```python
# Use alphanumeric table names only
table_name = "workflowrecords"  # NOT "workflow-records"
```

#### Issue 3: Connection reset by peer
**Cause**: Application crashing on startup
**Solution**:
```bash
# Check logs
docker logs api-gateway

# Verify imports
docker exec api-gateway python3 -c "import main; print('OK')"
```

#### Issue 4: Rate limiting not working
**Cause**: Middleware ordering issue
**Solution**:
```python
# Ensure middleware is added in correct order
app.add_middleware(RateLimitMiddleware)  # First
app.add_middleware(APIKeyMiddleware)     # Second
```

#### Issue 5: Azurite data not persisting
**Cause**: Volume not properly mounted
**Solution**:
```yaml
# In docker-compose.yaml
volumes:
  - azurite_data:/data  # Ensure this is present
```

### Debug Commands
```bash
# Check container logs
docker-compose logs -f api-gateway
docker logs azurite --tail 50

# Test connectivity
docker exec api-gateway ping azurite
docker exec api-gateway curl http://azurite:10000/devstoreaccount1

# Check Python path
docker exec api-gateway python3 -c "import sys; print(sys.path)"

# Verify imports
docker exec api-gateway python3 -c "from storage_service import AzureStorageService; print('OK')"

# Check environment variables
docker exec api-gateway env | grep AZURITE

# Enter container for debugging
docker exec -it api-gateway /bin/bash
```

---

## Summary & Next Steps

### ✅ What You've Built
- **Complete API Gateway** with FastAPI
- **Azure Storage Integration** via Azurite
- **Authentication** with API Keys
- **Rate Limiting** with in-memory tracking
- **Request Logging** with Correlation IDs
- **Docker Compose** for local development
- **Production-ready** configuration

### 🚀 Next Steps
1. **Add JWT Authentication** for enhanced security
2. **Implement Background Workers** for async processing
3. **Add Prometheus Metrics** for monitoring
4. **Create CI/CD Pipeline** with GitHub Actions
5. **Deploy to Azure** using Container Instances or App Service

### 📚 Resources
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Azure Storage Documentation](https://docs.microsoft.com/en-us/azure/storage/)
- [Docker Documentation](https://docs.docker.com/)
- [Azurite Documentation](https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite)

---

## 🎉 Final Summary

Successfully built a complete, production-ready Azure development environment on local laptop!

**Key Achievements:**
- ✅ Infrastructure as Code (Docker Compose)
- ✅ API Development (FastAPI)
- ✅ Azure Services (Azurite emulator)
- ✅ Security (API Keys, Rate Limiting)
- ✅ Observability (Logging, Correlation IDs)
- ✅ Git Workflow (Branches)
- ✅ Production Readiness

This is exactly what professional DevOps engineers do to test Azure services locally before deploying to the cloud.  🚀
