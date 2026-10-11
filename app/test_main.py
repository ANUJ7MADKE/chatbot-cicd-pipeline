from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    res = client.get("/")
    assert res.status_code == 200
    assert res.json()["status"] == "healthy"
    assert res.json()["service"] == "chatbot"


def test_chat_ping():
    res = client.post("/chat", json={"message": "ping"})
    assert res.status_code == 200
    assert res.json()["reply"] == "pong"


def test_chat_status():
    res = client.post("/chat", json={"message": "status"})
    assert res.status_code == 200
    assert res.json()["reply"] == "All systems operational."


def test_chat_cost():
    res = client.post("/chat", json={"message": "cost"})
    assert res.status_code == 200
    assert res.json()["reply"] == "Current run rate: within allocated budget."


def test_chat_unknown_message_fallback():
    res = client.post("/chat", json={"message": "hello there"})
    assert res.status_code == 200
    reply = res.json()["reply"]
    assert "I received: 'hello there'" in reply
    assert "Ask me 'status' or 'ping'." in reply


def test_chat_case_insensitive_with_whitespace():
    res = client.post("/chat", json={"message": "  PING  "})
    assert res.status_code == 200
    assert res.json()["reply"] == "pong"


def test_chat_missing_message_returns_422():
    res = client.post("/chat", json={})
    assert res.status_code == 422


def test_chat_wrong_message_type_returns_422():
    res = client.post("/chat", json={"message": 123})
    assert res.status_code == 422
