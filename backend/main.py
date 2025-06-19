from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Dict, Any, List
import uvicorn
from datetime import datetime

from config import settings
from agents.task_agent import TaskAgent

app = FastAPI(
    title="AI-powered task management system",
    description="** AI-Task-Manager is an AI-powered task management system designed to help individuals and teams manage their tasks efficiently by leveraging machine learning to provide smart task prioritization and intelligent suggestions. The system integrates seamless real-time updates and insightful analytics to enhance productivity and streamline workflows.",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize agents
task_agent = TaskAgent()

class TaskRequest(BaseModel):
    task: str
    context: Dict[str, Any] = {}

class TaskResponse(BaseModel):
    result: Dict[str, Any]
    timestamp: datetime
    processing_time: float

@app.get("/")
async def root():
    return {
        "message": "Welcome to AI-powered task management system",
        "features": ['GET /tasks/prioritize**: Auto-prioritize tasks based on AI analysis.', 'POST /tasks/suggest**: Get AI-generated suggestions for task management.', 'WebSocket /updates**: Establish a WebSocket connection for real-time task updates.', 'GET /analytics**: Retrieve analytical insights and reports.', 'POST /nlp/command**: Process natural language commands for task creation and updates.'],
        "version": "1.0.0"
    }

@app.post("/api/process", response_model=TaskResponse)
async def process_task(request: TaskRequest):
    """Process a task using AI agents"""
    start_time = datetime.utcnow()
    
    try:
        result = await task_agent.process({
            "task": request.task,
            "context": request.context
        })
        
        processing_time = (datetime.utcnow() - start_time).total_seconds()
        
        return TaskResponse(
            result=result,
            timestamp=datetime.utcnow(),
            processing_time=processing_time
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.utcnow()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
