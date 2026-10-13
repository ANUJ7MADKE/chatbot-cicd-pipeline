from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="DevOps Chatbot API", version="1.0.0")

class ChatRequest(BaseModel):
    message: str

RESPONSES = {
    "ping": "PONG!",
    "status": "All systems operational.",
    "cost": "Current run rate: within allocated budget."
}

@app.get("/")
def health_check():
    return {"status": "healthy", "service": "chatbot"}

@app.post("/chat")
def chat_endpoint(req: ChatRequest):
    user_msg = req.message.strip().lower()
    reply = RESPONSES.get(user_msg, f"I received: '{req.message}'. Ask me 'status' or 'ping'.")
    return {"reply": reply}