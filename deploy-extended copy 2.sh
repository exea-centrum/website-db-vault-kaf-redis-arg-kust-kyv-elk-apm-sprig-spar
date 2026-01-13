#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "❌ Error on line ${LINENO} (exit ${rc})"; exit ${rc}' ERR
IFS=$'\n\t'

PROJECT="website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar"
NAMESPACE="davtroelkpyjs"
REGISTRY="${REGISTRY:-ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar}"
REPO_URL="${REPO_URL:-https://github.com/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.git}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${ROOT_DIR}/app"
TEMPLATES_DIR="${APP_DIR}/templates"
MANIFESTS_DIR="${ROOT_DIR}/manifests"
BASE_DIR="${MANIFESTS_DIR}/base"
WORKFLOW_DIR="${ROOT_DIR}/.github/workflows"
JAVA_DIR="${ROOT_DIR}/java-app"
SPARK_DIR="${ROOT_DIR}/spark-jobs"
ELK_DIR="${ROOT_DIR}/elk"

info(){ printf "🔧 [unified] %s\n" "$*"; }
mkdir_p(){ mkdir -p "$@"; }

generate_structure(){
 mkdir_p "$APP_DIR" "$TEMPLATES_DIR" "$BASE_DIR" "$WORKFLOW_DIR" "${APP_DIR}/static" "${APP_DIR}/static/js" "${APP_DIR}/static/css"
 mkdir_p "$JAVA_DIR/src/main/java/com/davtroweb/survey" "$SPARK_DIR/src/main/scala/com/davtroweb/analytics" "$ELK_DIR"
}

generate_fastapi_app(){
 # FastAPI Application Package
 cat > "${APP_DIR}/__init__.py" <<'PY'
# FastAPI Application Package
PY

 # FastAPI Main Application
 cat > "${APP_DIR}/main.py" <<'PY'
from fastapi import FastAPI, Form, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import os
import logging
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel
from typing import List, Dict, Any
import time
import hvac
import json
import redis
from kafka import KafkaProducer

app = FastAPI(title="Dawid Trojanowski - Strona Osobista")
templates = Jinja2Templates(directory="templates")
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi_app")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "outgoing_messages")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-0.kafka.davtroelkpyjs.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "survey-topic")

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    max_retries = 10
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP.split(','),
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                retries=3,
                request_timeout_ms=10000
            )
            logger.info("Kafka producer created successfully")
            return producer
        except Exception as e:
            logger.warning(f"Kafka connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All Kafka connection attempts failed: {e}")
                return None

def get_vault_secret(secret_path: str) -> dict:
    try:
        vault_addr = os.getenv("VAULT_ADDR", "http://vault:8200")
        vault_token = os.getenv("VAULT_TOKEN")
        
        if vault_token:
            client = hvac.Client(url=vault_addr, token=vault_token)
            if client.is_authenticated():
                secret = client.read(secret_path)
                if secret and 'data' in secret:
                    return secret['data'].get('data', {})
        else:
            logger.warning("Vault token not available, using fallback")
            
    except Exception as e:
        logger.warning(f"Vault error: {e}, using fallback")
    
    return {}

def get_database_config() -> str:
    vault_secret = get_vault_secret("secret/data/database/postgres")
    
    if vault_secret:
        return f"dbname={vault_secret.get('postgres-db', 'webdb')} " \
               f"user={vault_secret.get('postgres-user', 'webuser')} " \
               f"password={vault_secret.get('postgres-password', 'testpassword')} " \
               f"host={vault_secret.get('postgres-host', 'postgres-db')} " \
               f"port=5432"
    else:
        return os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db port=5432")

DB_CONN = get_database_config()

Instrumentator().instrument(app).expose(app)

class SurveyResponse(BaseModel):
    question: str
    answer: str

def get_db_connection():
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DB_CONN)
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Database connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All database connection attempts failed: {e}")

def init_database():
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS survey_responses(
                    id SERIAL PRIMARY KEY,
                    question TEXT NOT NULL,
                    answer TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS page_visits(
                    id SERIAL PRIMARY KEY,
                    page VARCHAR(255) NOT NULL,
                    visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            cur.execute("""
                CREATE TABLE IF NOT EXISTS contact_messages(
                    id SERIAL PRIMARY KEY,
                    email VARCHAR(255) NOT NULL,
                    message TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            conn.commit()
            cur.close()
            conn.close()
            logger.info("Database initialized successfully")
            return
        except Exception as e:
            logger.warning(f"Database initialization attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All database initialization attempts failed: {e}")

@app.on_event("startup")
async def startup_event():
    init_database()

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("INSERT INTO page_visits (page) VALUES ('home')")
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Error logging page visit: {e}")
    
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/health")
async def health_check():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        
        vault_secret = get_vault_secret("secret/data/database/postgres")
        vault_status = "connected" if vault_secret else "disconnected"
        
        return {
            "status": "healthy",
            "database": "connected",
            "vault": vault_status
        }
    except Exception as e:
        logger.warning(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "vault": "disconnected",
            "error": str(e)
        }

@app.get("/api/survey/questions")
async def get_survey_questions():
    questions = [
        {
            "id": 1,
            "text": "Jak oceniasz design strony?",
            "type": "rating",
            "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
        },
        {
            "id": 2,
            "text": "Czy informacje były przydatne?",
            "type": "choice",
            "options": ["Tak", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
        },
        {
            "id": 3,
            "text": "Jakie technologie Cię zainteresowały?",
            "type": "multiselect",
            "options": ["Python", "JavaScript", "React", "Kubernetes", "Docker", "PostgreSQL", "Vault"]
        },
        {
            "id": 4,
            "text": "Czy poleciłbyś tę stronę innym?",
            "type": "choice",
            "options": ["Zdecydowanie tak", "Prawdopodobnie tak", "Nie wiem", "Raczej nie", "Zdecydowanie nie"]
        },
        {
            "id": 5,
            "text": "Co sądzisz o portfolio?",
            "type": "text",
            "placeholder": "Podziel się swoją opinią..."
        }
    ]
    return questions

@app.post("/api/survey/submit")
async def submit_survey(response: SurveyResponse):
    try:
        r = get_redis()
        payload = {
            "type": "survey",
            "question": response.question,
            "answer": response.answer,
            "timestamp": time.time()
        }
        r.rpush(REDIS_LIST, json.dumps(payload))
        
        logger.info(f"Survey response queued: {response.question} -> {response.answer}")
        return {"status": "success", "message": "Dziękujemy za wypełnienie ankiety!"}
    except Exception as e:
        logger.error(f"Error queueing survey response: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas zapisywania odpowiedzi")

@app.get("/api/survey/stats")
async def get_survey_stats():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT question, answer, COUNT(*) as count
            FROM survey_responses
            GROUP BY question, answer
            ORDER BY question, count DESC
        """)
        responses = cur.fetchall()
        
        cur.execute("SELECT COUNT(*) FROM page_visits")
        total_visits = cur.fetchone()[0]
        
        cur.close()
        conn.close()
        
        stats = {}
        for question, answer, count in responses:
            if question not in stats:
                stats[question] = []
            stats[question].append({"answer": answer, "count": count})
        
        return {
            "survey_responses": stats,
            "total_visits": total_visits,
            "total_responses": sum(len(answers) for answers in stats.values())
        }
    except Exception as e:
        logger.error(f"Error fetching survey stats: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas pobierania statystyk")

@app.post("/api/contact")
async def submit_contact(email: str = Form(...), message: str = Form(...)):
    try:
        r = get_redis()
        payload = {
            "type": "contact",
            "email": email,
            "message": message,
            "timestamp": time.time()
        }
        r.rpush(REDIS_LIST, json.dumps(payload))
        
        logger.info(f"Contact message queued from: {email}")
        return {"status": "success", "message": "Wiadomość została wysłana!"}
    except Exception as e:
        logger.error(f"Error queueing contact message: {e}")
        raise HTTPException(status_code=500, detail="Błąd podczas wysyłania wiadomości")

# Import Spring Boot Proxy
from .spring_proxy import router as spring_router
app.include_router(spring_router)

# New Survey Route
@app.get("/new-survey", response_class=HTMLResponse)
async def new_survey(request: Request):
    return templates.TemplateResponse("new_survey.html", {"request": request})

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
PY

 # Spring Boot Proxy
 cat > "${APP_DIR}/spring_proxy.py" <<'PY'
"""
Proxy do komunikacji z Spring Boot API
"""
from fastapi import APIRouter, HTTPException
import httpx
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v2", tags=["spring-survey"])

# Konfiguracja Spring Boot API
SPRING_API_URL = "http://spring-app-service:8080/api"

@router.get("/survey/questions")
async def get_spring_survey_questions():
    """
    Pobiera pytania z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/questions",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching questions from Spring: {e}")
        # Fallback questions
        return [
            {
                "id": 1,
                "text": "Jak oceniasz wydajność Spring Boot API?",
                "type": "rating",
                "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
            },
            {
                "id": 2,
                "text": "Która technologia Java Cię interesuje?",
                "type": "choice",
                "options": ["Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams"]
            },
            {
                "id": 3,
                "text": "Jak oceniasz integrację z Python/FastAPI?",
                "type": "rating",
                "options": ["1 - Słaba", "2", "3", "4", "5 - Doskonała"]
            },
            {
                "id": 4,
                "text": "Czy uważasz, że ELK Stack jest przydatny?",
                "type": "choice",
                "options": ["Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
            },
            {
                "id": 5,
                "text": "Twoje sugestie dotyczące architektury:",
                "type": "text",
                "placeholder": "Podziel się swoimi pomysłami..."
            }
        ]

@router.post("/survey/submit")
async def submit_spring_survey(data: Dict[str, Any]):
    """
    Wysyła odpowiedzi do Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{SPRING_API_URL}/survey/submit",
                json=data,
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error submitting to Spring: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error submitting survey: {str(e)}"
        )

@router.get("/survey/stats")
async def get_spring_survey_stats():
    """
    Pobiera statystyki z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/stats",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching stats from Spring: {e}")
        return {
            "totalResponses": 0,
            "avgRating": 0.0,
            "uniqueUsers": 0,
            "charts": {
                "ratings": {"labels": [], "datasets": []},
                "technologies": {"labels": [], "datasets": []}
            }
        }

@router.get("/spark/jobs")
async def get_spark_jobs():
    """
    Pobiera status zadań Spark
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "http://spark-master:8080/api/v1/applications",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching Spark jobs: {e}")
        return []

@router.get("/elk/logs")
async def search_elk_logs(query: str = "", size: int = 10):
    """
    Wyszukuje logi w Elasticsearch
    """
    try:
        async with httpx.AsyncClient() as client:
            es_query = {
                "query": {
                    "bool": {
                        "must": [
                            {"match": {"message": query}} if query else {"match_all": {}}
                        ]
                    }
                },
                "size": size,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            response = await client.post(
                "http://elasticsearch:9200/logs*/_search",
                json=es_query,
                headers={"Content-Type": "application/json"},
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error searching ELK logs: {e}")
        return {"hits": {"hits": []}}
PY

 # Worker
 cat > "${APP_DIR}/worker.py" <<'PY'
#!/usr/bin/env python3
import os, json, time, logging
import redis
from kafka import KafkaProducer
import psycopg2
import hvac

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("worker")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_LIST = os.getenv("REDIS_LIST", "outgoing_messages")

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-0.kafka.davtroelkpyjs.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "survey-topic")

def get_vault_secret(secret_path: str) -> dict:
    try:
        vault_addr = os.getenv("VAULT_ADDR", "http://vault:8200")
        vault_token = os.getenv("VAULT_TOKEN")
        
        if vault_token:
            client = hvac.Client(url=vault_addr, token=vault_token)
            if client.is_authenticated():
                secret = client.read(secret_path)
                if secret and 'data' in secret:
                    return secret['data'].get('data', {})
        else:
            logger.warning("Vault token not available, using fallback")
            
    except Exception as e:
        logger.warning(f"Vault error: {e}, using fallback")
    
    return {}

def get_database_config() -> str:
    vault_secret = get_vault_secret("secret/data/database/postgres")
    
    if vault_secret:
        return f"dbname={vault_secret.get('postgres-db', 'webdb')} " \
               f"user={vault_secret.get('postgres-user', 'webuser')} " \
               f"password={vault_secret.get('postgres-password', 'testpassword')} " \
               f"host={vault_secret.get('postgres-host', 'postgres-db')} " \
               f"port=5432"
    else:
        return os.getenv("DATABASE_URL", "dbname=webdb user=webuser password=testpassword host=postgres-db port=5432")

DATABASE_URL = get_database_config()

def get_redis():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

def get_kafka():
    max_retries = 10
    for attempt in range(max_retries):
        try:
            producer = KafkaProducer(
                bootstrap_servers=KAFKA_BOOTSTRAP.split(','),
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                retries=3,
                request_timeout_ms=10000
            )
            logger.info("Kafka producer created successfully")
            return producer
        except Exception as e:
            logger.warning(f"Kafka connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All Kafka connection attempts failed: {e}")
                return None

def get_db_connection():
    max_retries = 30
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DATABASE_URL)
            return conn
        except psycopg2.OperationalError as e:
            logger.warning(f"Database connection attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(10)
            else:
                logger.error(f"All database connection attempts failed: {e}")

def save_to_db(item_type, data):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        if item_type == "survey":
            cur.execute(
                "INSERT INTO survey_responses (question, answer) VALUES (%s, %s)",
                (data.get("question"), data.get("answer"))
            )
        elif item_type == "contact":
            cur.execute(
                "INSERT INTO contact_messages (email, message) VALUES (%s, %s)",
                (data.get("email"), data.get("message"))
            )
        
        conn.commit()
        logger.info(f"Saved {item_type} to database")
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Error saving to database: {e}")

def process_item(item, producer):
    try:
        item_type = item.get("type")
        save_to_db(item_type, item)
        
        if producer:
            try:
                future = producer.send(KAFKA_TOPIC, value=item)
                future.get(timeout=10)
                logger.info(f"Sent to Kafka topic {KAFKA_TOPIC}: {item}")
            except Exception as e:
                logger.warning(f"Failed to send to Kafka (will continue without Kafka): {e}")
        
    except Exception as e:
        logger.exception(f"Processing failed for item: {item}")

def main():
    r = get_redis()
    producer = get_kafka()
    
    logger.info("Worker started. Listening on Redis list '%s'", REDIS_LIST)
    
    while True:
        try:
            res = r.blpop(REDIS_LIST, timeout=10)
            if res:
                _, data = res
                try:
                    item = json.loads(data)
                except Exception:
                    item = {"raw": data, "type": "unknown"}
                
                process_item(item, producer)
                
        except Exception as e:
            logger.exception("Worker loop exception, reconnecting...")
            time.sleep(5)

if __name__ == "__main__":
    main()
PY

 # Static Files
 cat > "${APP_DIR}/static/js/new-survey.js" <<'JS'
// Nowa ankieta JavaScript z React-like komponentami
class NewSurveyApp {
    constructor() {
        this.state = {
            questions: [],
            answers: {},
            submitted: false,
            stats: null
        };
        this.init();
    }

    async init() {
        await this.loadQuestions();
        this.render();
        this.setupEventListeners();
    }

    async loadQuestions() {
        try {
            const response = await fetch('/api/v2/survey/questions');
            this.state.questions = await response.json();
            this.render();
        } catch (error) {
            console.error('Error loading questions:', error);
        }
    }

    async loadStats() {
        try {
            const response = await fetch('/api/v2/survey/stats');
            this.state.stats = await response.json();
            this.renderStats();
        } catch (error) {
            console.error('Error loading stats:', error);
        }
    }

    handleAnswer(questionId, value) {
        this.state.answers[questionId] = value;
        this.render();
    }

    async submitSurvey() {
        const responses = Object.entries(this.state.answers).map(([qId, answer]) => ({
            questionId: qId,
            question: this.state.questions.find(q => q.id == qId)?.text || '',
            answer: answer,
            timestamp: new Date().toISOString(),
            surveyType: 'java-survey'
        }));

        try {
            const response = await fetch('/api/v2/survey/submit', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ responses })
            });
            
            if (response.ok) {
                this.state.submitted = true;
                this.state.answers = {};
                await this.loadStats();
                this.showMessage('Ankieta została przesłana! Dziękujemy.', 'success');
            }
        } catch (error) {
            this.showMessage('Błąd podczas wysyłania ankiety', 'error');
        }
    }

    showMessage(text, type) {
        const messageDiv = document.getElementById('survey-message');
        messageDiv.textContent = text;
        messageDiv.className = `message ${type}`;
        messageDiv.style.display = 'block';
        setTimeout(() => { messageDiv.style.display = 'none'; }, 5000);
    }

    render() {
        const container = document.getElementById('new-survey-container');
        if (!container) return;

        container.innerHTML = `
            <div class="survey-header">
                <h2>🚀 Nowa Ankieta Technologiczna (JavaScript + Spring Boot)</h2>
                <p>Oceń nasze nowe technologie: Spring Boot, Apache Spark, MongoDB, ELK Stack</p>
            </div>
            
            ${this.state.questions.map(q => `
                <div class="question-card">
                    <h3>${q.text}</h3>
                    <div class="options">
                        ${this.renderQuestionInput(q)}
                    </div>
                </div>
            `).join('')}
            
            <button id="submit-survey-btn" class="submit-btn">
                ${this.state.submitted ? '✓ Wysłano!' : 'Wyślij ankietę'}
            </button>
            
            <div id="survey-message" class="message"></div>
        `;
    }

    renderQuestionInput(question) {
        switch(question.type) {
            case 'rating':
                return `
                    <div class="rating-buttons">
                        ${[1,2,3,4,5].map(num => `
                            <button class="rating-btn ${this.state.answers[question.id] == num ? 'selected' : ''}"
                                    onclick="surveyApp.handleAnswer(${question.id}, ${num})">
                                ${num}
                            </button>
                        `).join('')}
                    </div>
                `;
            case 'choice':
                return `
                    <div class="choice-buttons">
                        ${question.options.map(opt => `
                            <button class="choice-btn ${this.state.answers[question.id] == opt ? 'selected' : ''}"
                                    onclick="surveyApp.handleAnswer(${question.id}, '${opt}')">
                                ${opt}
                            </button>
                        `).join('')}
                    </div>
                `;
            case 'text':
                return `
                    <textarea class="text-answer" 
                              placeholder="${question.placeholder}"
                              oninput="surveyApp.handleAnswer(${question.id}, this.value)">
                    </textarea>
                `;
            default:
                return '';
        }
    }

    renderStats() {
        const statsContainer = document.getElementById('survey-stats-container');
        if (!statsContainer || !this.state.stats) return;

        statsContainer.innerHTML = `
            <h3>📊 Statystyki ankiety (Spring Boot + MongoDB)</h3>
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.totalResponses}</div>
                    <div class="stat-label">Wszystkich odpowiedzi</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.avgRating?.toFixed(1) || '0.0'}</div>
                    <div class="stat-label">Średnia ocena</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${this.state.stats.uniqueUsers}</div>
                    <div class="stat-label">Unikalnych użytkowników</div>
                </div>
            </div>
            
            <div class="charts">
                <canvas id="rating-chart" width="400" height="200"></canvas>
                <canvas id="tech-chart" width="400" height="200"></canvas>
            </div>
        `;

        this.renderCharts();
    }

    renderCharts() {
        // Implementacja wykresów Chart.js
        if (window.Chart && this.state.stats?.charts) {
            new Chart(document.getElementById('rating-chart'), {
                type: 'bar',
                data: this.state.stats.charts.ratings
            });
            
            new Chart(document.getElementById('tech-chart'), {
                type: 'pie',
                data: this.state.stats.charts.technologies
            });
        }
    }

    setupEventListeners() {
        document.addEventListener('click', (e) => {
            if (e.target.id === 'submit-survey-btn') {
                this.submitSurvey();
            }
        });
    }
}

// Globalna instancja
window.surveyApp = new NewSurveyApp();
JS

 cat > "${APP_DIR}/static/css/new-survey.css" <<'CSS'
/* Stylizacja nowej ankiety */
.new-survey-section {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 20px;
    padding: 2rem;
    margin: 2rem 0;
    color: white;
}

.survey-header {
    text-align: center;
    margin-bottom: 2rem;
}

.survey-header h2 {
    font-size: 2rem;
    margin-bottom: 0.5rem;
}

.survey-header p {
    opacity: 0.9;
    font-size: 1.1rem;
}

.question-card {
    background: rgba(255, 255, 255, 0.1);
    backdrop-filter: blur(10px);
    border-radius: 15px;
    padding: 1.5rem;
    margin: 1rem 0;
    border: 1px solid rgba(255, 255, 255, 0.2);
}

.question-card h3 {
    margin-bottom: 1rem;
    font-size: 1.3rem;
}

.rating-buttons {
    display: flex;
    gap: 0.5rem;
    justify-content: center;
}

.rating-btn {
    width: 50px;
    height: 50px;
    border-radius: 50%;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    font-size: 1.2rem;
    cursor: pointer;
    transition: all 0.3s ease;
}

.rating-btn:hover {
    background: rgba(255, 255, 255, 0.2);
    transform: translateY(-2px);
}

.rating-btn.selected {
    background: #4ade80;
    border-color: #22c55e;
    transform: scale(1.1);
}

.choice-buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
}

.choice-btn {
    padding: 0.75rem 1.5rem;
    border-radius: 50px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    cursor: pointer;
    transition: all 0.3s ease;
}

.choice-btn:hover {
    background: rgba(255, 255, 255, 0.2);
}

.choice-btn.selected {
    background: #3b82f6;
    border-color: #1d4ed8;
}

.text-answer {
    width: 100%;
    min-height: 100px;
    padding: 1rem;
    border-radius: 10px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    background: rgba(255, 255, 255, 0.1);
    color: white;
    resize: vertical;
}

.text-answer::placeholder {
    color: rgba(255, 255, 255, 0.6);
}

.submit-btn {
    display: block;
    width: 100%;
    padding: 1rem;
    margin-top: 2rem;
    background: linear-gradient(135deg, #4ade80 0%, #22c55e 100%);
    color: white;
    border: none;
    border-radius: 10px;
    font-size: 1.2rem;
    font-weight: bold;
    cursor: pointer;
    transition: all 0.3s ease;
}

.submit-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 10px 20px rgba(34, 197, 94, 0.3);
}

.message {
    margin-top: 1rem;
    padding: 1rem;
    border-radius: 10px;
    text-align: center;
    font-weight: bold;
}

.message.success {
    background: rgba(34, 197, 94, 0.2);
    border: 2px solid #22c55e;
    color: #22c55e;
}

.message.error {
    background: rgba(239, 68, 68, 0.2);
    border: 2px solid #ef4444;
    color: #ef4444;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
    margin: 2rem 0;
}

.stat-card {
    background: rgba(255, 255, 255, 0.1);
    border-radius: 15px;
    padding: 1.5rem;
    text-align: center;
    backdrop-filter: blur(10px);
}

.stat-value {
    font-size: 2.5rem;
    font-weight: bold;
    margin-bottom: 0.5rem;
}

.stat-label {
    opacity: 0.8;
    font-size: 0.9rem;
}

.charts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2rem;
    margin-top: 2rem;
}

@media (max-width: 768px) {
    .charts {
        grid-template-columns: 1fr;
    }
}
CSS

 # Templates
 cat > "${TEMPLATES_DIR}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Dawid Trojanowski - Strona Osobista</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .animate-fade-in { animation: fadeIn 0.5s ease-out; }
        .skill-bar { height: 10px; background: rgba(255,255,255,0.1); border-radius: 5px; overflow: hidden; }
        .skill-progress { height: 100%; border-radius: 5px; transition: width 1.5s ease-in-out; }
    </style>
</head>
<body class="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900 text-white min-h-screen">
    <header class="border-b border-purple-500/30 backdrop-blur-sm bg-black/20 sticky top-0 z-50">
        <div class="container mx-auto px-6 py-4">
            <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                    <h1 class="text-3xl font-bold bg-gradient-to-r from-purple-400 to-pink-400 bg-clip-text text-transparent">
                        Dawid Trojanowski
                    </h1>
                </div>
                <nav class="flex gap-4">
                    <button onclick="showTab('intro')" class="tab-btn px-4 py-2 rounded-lg bg-purple-500 text-white" data-tab="intro">O Mnie</button>
                    <button onclick="showTab('edu')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="edu">Edukacja</button>
                    <button onclick="showTab('exp')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="exp">Doświadczenie</button>
                    <button onclick="showTab('skills')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="skills">Umiejętności</button>
                    <button onclick="showTab('survey')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="survey">Ankieta</button>
                    <button onclick="showTab('new-survey')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="new-survey">Nowa Ankieta</button>
                    <button onclick="showTab('contact')" class="tab-btn px-4 py-2 rounded-lg text-purple-300" data-tab="contact">Kontakt</button>
                </nav>
            </div>
        </div>
    </header>

    <main class="container mx-auto px-6 py-12">
        <div id="intro-tab" class="tab-content">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">O Mnie</h2>
                    <p class="text-lg text-gray-300 leading-relaxed">
                        Cześć! Jestem Dawidem Trojanowskim, pasjonatem informatyki i nowych technologii. 
                        Specjalizuję się w tworzeniu rozproszonych systemów wykorzystujących FastAPI, Redis, 
                        Kafka i PostgreSQL z pełnym monitoringiem.
                    </p>
                </div>
            </div>
        </div>

        <div id="edu-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Edukacja</h2>
                <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                    <h3 class="text-2xl font-bold mb-4 text-purple-300">Politechnika Warszawska</h3>
                    <p class="text-gray-300 mb-4">Informatyka, studia magisterskie</p>
                </div>
            </div>
        </div>

        <div id="exp-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Doświadczenie Zawodowe</h2>
                <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                    <h3 class="text-2xl font-bold mb-4 text-purple-300">Full Stack Developer</h3>
                    <p class="text-gray-300 mb-4">Specjalizacja w systemach rozproszonych</p>
                </div>
            </div>
        </div>

        <div id="skills-tab" class="tab-content hidden">
            <div class="space-y-6 animate-fade-in">
                <h2 class="text-4xl font-bold mb-8 text-purple-300">Umiejętności</h2>
                <div class="grid md:grid-cols-2 gap-6">
                    <div class="bg-gradient-to-br from-slate-800/50 to-slate-900/50 backdrop-blur-lg border border-purple-500/20 rounded-xl p-6">
                        <h3 class="text-2xl font-bold mb-4 text-purple-300">Technologie</h3>
                        <div class="space-y-4">
                            <div>
                                <div class="flex justify-between mb-1"><span>FastAPI</span><span>90%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="90%"></div></div>
                            </div>
                            <div>
                                <div class="flex justify-between mb-1"><span>Kubernetes</span><span>85%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="85%"></div></div>
                            </div>
                            <div>
                                <div class="flex justify-between mb-1"><span>PostgreSQL</span><span>88%</span></div>
                                <div class="skill-bar"><div class="skill-progress bg-gradient-to-r from-purple-500 to-pink-500" data-width="88%"></div></div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div id="survey-tab" class="tab-content hidden">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">Ankieta</h2>
                    <p class="text-lg text-gray-300 mb-8">
                        Twoje odpowiedzi trafią przez Redis i Kafka do bazy PostgreSQL z pełnym monitoringiem!
                    </p>
                  
                    <form id="survey-form" class="space-y-6">
                        <div id="survey-questions"></div>
                        <button type="submit" class="w-full py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">
                            Wyślij ankietę
                        </button>
                    </form>
                  
                    <div id="survey-message" class="mt-4 hidden p-3 rounded-lg"></div>
                </div>

                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h3 class="text-2xl font-bold mb-6 text-purple-300">Statystyki ankiet</h3>
                    <div class="grid md:grid-cols-2 gap-6">
                        <div id="survey-stats"></div>
                        <div><canvas id="survey-chart" width="400" height="200"></canvas></div>
                    </div>
                </div>
            </div>
        </div>

        <div id="new-survey-tab" class="tab-content hidden">
            <div class="space-y-8 animate-fade-in">
                <div class="new-survey-section">
                    <div id="new-survey-container"></div>
                </div>
                <div class="mt-12">
                    <div id="survey-stats-container"></div>
                </div>
                <div class="mt-12 grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div class="bg-gray-800 rounded-xl p-6">
                        <h3 class="text-xl font-bold mb-4">⚡ Apache Spark Jobs</h3>
                        <div id="spark-jobs" class="space-y-2">
                            <div class="animate-pulse">Ładowanie zadań Spark...</div>
                        </div>
                        <button onclick="loadSparkJobs()" class="mt-4 px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600">
                            Odśwież status
                        </button>
                    </div>
                    <div class="bg-gray-800 rounded-xl p-6">
                        <h3 class="text-xl font-bold mb-4">🔍 Wyszukiwarka Logów (ELK)</h3>
                        <div class="flex gap-2 mb-4">
                            <input type="text" id="log-search" placeholder="Szukaj w logach..." 
                                   class="flex-1 px-4 py-2 bg-gray-700 text-white rounded-lg">
                            <button onclick="searchLogs()" class="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600">
                                Szukaj
                            </button>
                        </div>
                        <div id="logs-results" class="space-y-2 max-h-60 overflow-y-auto"></div>
                    </div>
                </div>
            </div>
        </div>

        <div id="contact-tab" class="tab-content hidden">
            <div class="space-y-8 animate-fade-in">
                <div class="bg-gradient-to-br from-purple-500/10 to-pink-500/10 backdrop-blur-lg border border-purple-500/20 rounded-2xl p-8">
                    <h2 class="text-4xl font-bold mb-6 text-purple-300">Kontakt</h2>
                    <div class="grid md:grid-cols-2 gap-6">
                        <div class="space-y-4">
                            <form id="contact-form">
                                <div><input type="email" name="email" placeholder="Twój email" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" required></div>
                                <div><textarea name="message" placeholder="Twoja wiadomość" rows="4" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" required></textarea></div>
                                <button type="submit" class="w-full mt-4 py-3 px-4 rounded-lg bg-purple-500 text-white hover:bg-purple-600 transition-all">Wyślij</button>
                            </form>
                            <div id="form-message" class="mt-4 hidden p-3 rounded-lg"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <script>
        function showTab(tabName) {
            document.querySelectorAll(".tab-content").forEach((tab) => {
                tab.classList.add("hidden");
                tab.classList.remove("animate-fade-in");
            });
            setTimeout(() => {
                const activeTab = document.getElementById(tabName + "-tab");
                activeTab.classList.remove("hidden");
                activeTab.classList.add("animate-fade-in");
                if (tabName === "skills") setTimeout(animateSkillBars, 300);
                if (tabName === "survey") { loadSurveyQuestions(); loadSurveyStats(); }
                if (tabName === "new-survey") { 
                    surveyApp.loadQuestions(); 
                    surveyApp.loadStats();
                    loadSparkJobs();
                }
            }, 50);
            document.querySelectorAll(".tab-btn").forEach((btn) => {
                btn.classList.remove("bg-purple-500", "text-white");
                btn.classList.add("text-purple-300");
            });
            document.querySelector(`[data-tab="${tabName}"]`).classList.add("bg-purple-500", "text-white");
        }

        function animateSkillBars() {
            document.querySelectorAll(".skill-progress").forEach((bar) => {
                bar.style.width = bar.getAttribute("data-width");
            });
        }

        async function loadSurveyQuestions() {
            try {
                const response = await fetch('/api/survey/questions');
                const questions = await response.json();
                const container = document.getElementById('survey-questions');
                container.innerHTML = '';
                questions.forEach((q, index) => {
                    const questionDiv = document.createElement('div');
                    questionDiv.className = 'space-y-3';
                    questionDiv.innerHTML = `<label class="block text-gray-300 font-semibold">${q.text}</label>`;
                    if (q.type === 'rating') {
                        questionDiv.innerHTML += `<div class="flex gap-2 flex-wrap">${q.options.map(option => `
                            <label class="flex items-center space-x-2 cursor-pointer">
                                <input type="radio" name="question_${q.id}" value="${option}" class="hidden peer" required>
                                <span class="px-4 py-2 rounded-lg bg-slate-700 text-gray-300 peer-checked:bg-purple-500 peer-checked:text-white transition-all">${option}</span>
                            </label>`).join('')}</div>`;
                    } else if (q.type === 'text') {
                        questionDiv.innerHTML += `<textarea name="question_${q.id}" placeholder="${q.placeholder}" class="w-full py-3 px-4 rounded-lg bg-slate-700 text-white border border-purple-500/30" rows="3"></textarea>`;
                    }
                    container.appendChild(questionDiv);
                });
            } catch (error) {
                console.error('Error loading survey questions:', error);
            }
        }

        async function loadSurveyStats() {
            try {
                const response = await fetch('/api/survey/stats');
                const stats = await response.json();
                const container = document.getElementById('survey-stats');
                if (stats.total_responses === 0) {
                    container.innerHTML = '<div class="text-center text-gray-400 py-8">Brak odpowiedzi na ankietę.</div>';
                    return;
                }
                let statsHTML = `<div class="space-y-4"><div class="grid grid-cols-2 gap-4 text-center">
                    <div class="bg-slate-800/50 rounded-lg p-4"><div class="text-2xl font-bold text-purple-300">${stats.total_visits}</div><div class="text-sm text-gray-400">Odwiedzin</div></div>
                    <div class="bg-slate-800/50 rounded-lg p-4"><div class="text-2xl font-bold text-purple-300">${stats.total_responses}</div><div class="text-sm text-gray-400">Odpowiedzi</div></div></div>`;
                for (const [question, answers] of Object.entries(stats.survey_responses)) {
                    statsHTML += `<div class="border-t border-purple-500/20 pt-4"><h4 class="font-semibold text-purple-300 mb-2">${question}</h4><div class="space-y-2">`;
                    answers.forEach(item => {
                        statsHTML += `<div class="flex justify-between items-center"><span class="text-gray-300 text-sm">${item.answer}</span><span class="text-purple-300 font-semibold">${item.count}</span></div>`;
                    });
                    statsHTML += `</div></div>`;
                }
                statsHTML += `</div>`;
                container.innerHTML = statsHTML;
                updateSurveyChart(stats);
            } catch (error) {
                console.error('Error loading survey stats:', error);
            }
        }

        function updateSurveyChart(stats) {
            const ctx = document.getElementById('survey-chart').getContext('2d');
            const labels = []; const data = [];
            for (const [question, answers] of Object.entries(stats.survey_responses)) {
                answers.forEach(item => { labels.push(`${question}: ${item.answer}`); data.push(item.count); });
            }
            new Chart(ctx, {
                type: 'doughnut',
                data: { labels: labels, datasets: [{ data: data, backgroundColor: ['#a855f7','#ec4899','#8b5cf6','#d946ef','#7c3aed'] }] },
                options: { responsive: true, plugins: { legend: { position: 'bottom', labels: { color: '#cbd5e1', font: { size: 10 } } } } }
            });
        }

        document.getElementById('survey-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const responses = [];
            for (let i = 1; i <= 5; i++) {
                const questionElement = e.target.elements[`question_${i}`];
                if (questionElement) {
                    if (questionElement.type === 'radio') {
                        const selected = document.querySelector(`input[name="question_${i}"]:checked`);
                        if (selected) responses.push({ question: `Pytanie ${i}`, answer: selected.value });
                    } else if (questionElement.tagName === 'TEXTAREA' && questionElement.value.trim()) {
                        responses.push({ question: `Pytanie ${i}`, answer: questionElement.value.trim() });
                    }
                }
            }
            if (responses.length === 0) { showSurveyMessage('Proszę odpowiedzieć na przynajmniej jedno pytanie', 'error'); return; }
            try:
                for (const response of responses) {
                    await fetch('/api/survey/submit', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(response) });
                }
                showSurveyMessage('Dziękujemy za wypełnienie ankiety!', 'success');
                e.target.reset(); loadSurveyStats();
            } catch (error) {
                console.error('Error submitting survey:', error);
                showSurveyMessage('Wystąpił błąd podczas wysyłania ankiety', 'error');
            }
        });

        function showSurveyMessage(text, type) {
            const messageDiv = document.getElementById('survey-message');
            messageDiv.textContent = text;
            messageDiv.className = 'mt-4 p-3 rounded-lg';
            messageDiv.classList.add(type === 'error' ? 'bg-red-500/20 text-red-300 border border-red-500/30' : 'bg-green-500/20 text-green-300 border border-green-500/30');
            messageDiv.classList.remove('hidden');
            setTimeout(() => { messageDiv.classList.add('hidden'); }, 5000);
        }

        async function loadSparkJobs() {
            try {
                const response = await fetch('/api/v2/spark/jobs');
                const jobs = await response.json();
                
                const container = document.getElementById('spark-jobs');
                if (jobs.length === 0) {
                    container.innerHTML = '<div class="text-gray-400">Brak aktywnych zadań Spark</div>';
                    return;
                }
                
                container.innerHTML = jobs.map(job => `
                    <div class="p-3 bg-gray-900 rounded-lg">
                        <div class="flex justify-between items-center">
                            <span class="font-medium">${job.name}</span>
                            <span class="px-2 py-1 text-xs rounded ${job.state === 'RUNNING' ? 'bg-green-500' : 'bg-yellow-500'}">
                                ${job.state}
                            </span>
                        </div>
                        <div class="text-sm text-gray-400 mt-1">ID: ${job.id}</div>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Error loading Spark jobs:', error);
                document.getElementById('spark-jobs').innerHTML = 
                    '<div class="text-red-400">Błąd ładowania zadań Spark</div>';
            }
        }

        async function searchLogs() {
            const query = document.getElementById('log-search').value;
            
            try {
                const response = await fetch(`/api/v2/elk/logs?query=${encodeURIComponent(query)}`);
                const data = await response.json();
                
                const container = document.getElementById('logs-results');
                const hits = data.hits?.hits || [];
                
                if (hits.length === 0) {
                    container.innerHTML = '<div class="text-gray-400">Brak wyników</div>';
                    return;
                }
                
                container.innerHTML = hits.map(hit => {
                    const source = hit._source;
                    return `
                        <div class="p-3 bg-gray-900 rounded-lg">
                            <div class="text-sm font-medium">${source.message || 'Brak wiadomości'}</div>
                            <div class="text-xs text-gray-400 mt-1">
                                ${source['@timestamp'] || new Date().toISOString()}
                            </div>
                            ${source.level ? `<span class="text-xs px-2 py-1 rounded ${source.level === 'ERROR' ? 'bg-red-500' : 'bg-blue-500'}">${source.level}</span>` : ''}
                        </div>
                    `;
                }).join('');
            } catch (error) {
                console.error('Error searching logs:', error);
                document.getElementById('logs-results').innerHTML = 
                    '<div class="text-red-400">Błąd wyszukiwania logów</div>';
            }
        }

        document.getElementById('contact-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const formData = new FormData(e.target);
            try {
                const response = await fetch('/api/contact', { method: 'POST', body: formData });
                const result = await response.json();
                showFormMessage(result.message, response.ok ? "success" : "error");
                if (response.ok) e.target.reset();
            } catch (error) {
                console.error('Error sending contact form:', error);
                showFormMessage("Wystąpił błąd podczas wysyłania wiadomości", "error");
            }
        });

        function showFormMessage(text, type) {
            const formMessage = document.getElementById('form-message');
            formMessage.textContent = text;
            formMessage.className = "mt-4 p-3 rounded-lg";
            formMessage.classList.add(type === "error" ? "bg-red-500/20 text-red-300 border border-red-500/30" : "bg-green-500/20 text-green-300 border border-green-500/30");
            formMessage.classList.remove("hidden");
            setTimeout(() => { formMessage.classList.add("hidden"); }, 5000);
        }

        document.addEventListener("DOMContentLoaded", () => {
            showTab("intro");
            // Ładujemy statystyki co 30 sekund
            setInterval(() => {
                if (!document.getElementById('new-survey-tab').classList.contains('hidden')) {
                    surveyApp.loadStats();
                }
            }, 30000);
        });
    </script>
    <script src="/static/js/new-survey.js"></script>
    <link rel="stylesheet" href="/static/css/new-survey.css">
</body>
</html>
HTML

 # Requirements
 cat > "${APP_DIR}/requirements.txt" <<'REQ'
fastapi==0.104.1
uvicorn==0.24.0
jinja2==3.1.2
psycopg2-binary==2.9.7
prometheus-fastapi-instrumentator==5.11.1
prometheus-client==0.16.0
python-multipart==0.0.6
pydantic==2.5.0
kafka-python==2.0.2
hvac==1.1.0
redis==4.6.0
httpx==0.25.1
REQ

 chmod +x "${APP_DIR}/worker.py"
}

generate_spring_app(){
 # Main aplikacji Spring Boot
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/SurveyApplication.java" <<'JAVA'
package com.davtroweb.survey;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.mongodb.config.EnableMongoAuditing;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.kafka.annotation.EnableKafka;

@SpringBootApplication
@EnableMongoAuditing
@EnableScheduling
@EnableKafka
public class SurveyApplication {
    public static void main(String[] args) {
        SpringApplication.run(SurveyApplication.class, args);
    }
}
JAVA

# Model MongoDB
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/model/SurveyResponse.java" <<'JAVA'
package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "survey_responses")
public class SurveyResponse {
    
    @Id
    private String id;
    
    @Indexed
    private String surveyId;
    
    private String userId;
    private String sessionId;
    
    private Map<String, Object> answers;
    private SurveyMetadata metadata;
    
    @Indexed
    private LocalDateTime submittedAt;
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class SurveyMetadata {
        private String surveyType;
        private String browser;
        private String ipAddress;
        private String userAgent;
        private String referer;
        private Map<String, Object> technicalData;
    }
}
JAVA

# Model dla analiz Spark
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/model/SparkAnalytics.java" <<'JAVA'
package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "spark_analytics")
@CompoundIndex(name = "type_timestamp_idx", def = "{'analysisType': 1, 'timestamp': -1}")
public class SparkAnalytics {
    
    @Id
    private String id;
    
    private String analysisType; // "sentiment", "trend", "correlation", "prediction"
    private LocalDateTime timestamp;
    private LocalDateTime dataStartTime;
    private LocalDateTime dataEndTime;
    
    private Map<String, Object> results;
    private Map<String, Double> metrics; // accuracy, precision, recall, etc.
    private Map<String, Object> parameters;
    
    private String sparkJobId;
    private String sparkApplicationId;
    private ProcessingStatus status;
    
    public enum ProcessingStatus {
        PENDING, PROCESSING, COMPLETED, FAILED
    }
}
JAVA

# Repository MongoDB
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/repository/SurveyRepository.java" <<'JAVA'
package com.davtroweb.survey.repository;

import com.davtroweb.survey.model.SurveyResponse;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Repository
public interface SurveyRepository extends MongoRepository<SurveyResponse, String> {
    
    List<SurveyResponse> findBySurveyId(String surveyId);
    
    @Query("{'submittedAt': {$gte: ?0, $lte: ?1}}")
    List<SurveyResponse> findByDateRange(LocalDateTime start, LocalDateTime end);
    
    @Query("{'surveyId': ?0, 'answers.?1': ?2}")
    List<SurveyResponse> findByAnswerValue(String surveyId, String questionKey, Object value);
    
    @Query(value = "{'surveyId': ?0}", count = true)
    long countBySurveyId(String surveyId);
    
    @Query(value = "{}", fields = "{'answers': 1, 'submittedAt': 1}")
    List<Map<String, Object>> findAllForAnalytics();
}
JAVA

# Controller REST API
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/controller/SurveyController.java" <<'JAVA'
package com.davtroweb.survey.controller;

import com.davtroweb.survey.model.SurveyResponse;
import com.davtroweb.survey.repository.SurveyRepository;
import com.davtroweb.survey.service.SparkService;
import com.davtroweb.survey.service.ElkService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@RestController
@RequestMapping("/api/survey")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class SurveyController {
    
    private final SurveyRepository surveyRepository;
    private final SparkService sparkService;
    private final ElkService elkService;
    
    @GetMapping("/questions")
    public ResponseEntity<List<Map<String, Object>>> getQuestions() {
        List<Map<String, Object>> questions = new ArrayList<>();
        
        questions.add(Map.of(
            "id", "spring_performance",
            "text", "Jak oceniasz wydajność Spring Boot API?",
            "type", "rating",
            "options", Arrays.asList("1 - Słabo", "2", "3", "4", "5 - Doskonale"),
            "category", "performance"
        ));
        
        questions.add(Map.of(
            "id", "java_tech_interest",
            "text", "Która technologia Java Cię interesuje?",
            "type", "multiselect",
            "options", Arrays.asList("Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams", "Quarkus", "Micronaut"),
            "category", "technology"
        ));
        
        questions.add(Map.of(
            "id", "integration_quality",
            "text", "Jak oceniasz integrację z Python/FastAPI?",
            "type", "rating",
            "options", Arrays.asList("1 - Słaba", "2", "3", "4", "5 - Doskonała"),
            "category", "integration"
        ));
        
        questions.add(Map.of(
            "id", "elk_usefulness",
            "text", "Czy uważasz, że ELK Stack jest przydatny?",
            "type", "choice",
            "options", Arrays.asList("Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"),
            "category", "monitoring"
        ));
        
        questions.add(Map.of(
            "id", "architecture_suggestions",
            "text", "Twoje sugestie dotyczące architektury:",
            "type", "text",
            "placeholder", "Podziel się swoimi pomysłami...",
            "category", "feedback"
        ));
        
        return ResponseEntity.ok(questions);
    }
    
    @PostMapping("/submit")
    public ResponseEntity<Map<String, Object>> submitSurvey(
            @RequestBody Map<String, Object> request,
            HttpServletRequest httpRequest) {
        
        try {
            String surveyId = "spring_js_survey_v1";
            String sessionId = httpRequest.getSession().getId();
            String userId = (String) request.getOrDefault("userId", "anonymous");
            
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> responses = (List<Map<String, Object>>) request.get("responses");
            
            // Przygotuj odpowiedzi jako mapa
            Map<String, Object> answers = new HashMap<>();
            for (Map<String, Object> response : responses) {
                String questionId = (String) response.get("questionId");
                Object answer = response.get("answer");
                answers.put(questionId, answer);
            }
            
            // Metadane
            SurveyResponse.SurveyMetadata metadata = new SurveyResponse.SurveyMetadata();
            metadata.setSurveyType("spring_js_hybrid");
            metadata.setBrowser(httpRequest.getHeader("User-Agent"));
            metadata.setIpAddress(httpRequest.getRemoteAddr());
            metadata.setUserAgent(httpRequest.getHeader("User-Agent"));
            metadata.setReferer(httpRequest.getHeader("Referer"));
            
            Map<String, Object> techData = new HashMap<>();
            techData.put("javaVersion", System.getProperty("java.version"));
            techData.put("springVersion", "3.1.0");
            techData.put("timestamp", System.currentTimeMillis());
            metadata.setTechnicalData(techData);
            
            // Zapisz w MongoDB
            SurveyResponse surveyResponse = new SurveyResponse();
            surveyResponse.setSurveyId(surveyId);
            surveyResponse.setUserId(userId);
            surveyResponse.setSessionId(sessionId);
            surveyResponse.setAnswers(answers);
            surveyResponse.setMetadata(metadata);
            surveyResponse.setSubmittedAt(LocalDateTime.now());
            
            surveyRepository.save(surveyResponse);
            
            // Wyślij do Kafka dla Spark
            sparkService.sendToKafka(surveyResponse);
            
            // Wyślij do ELK
            elkService.logSurveySubmission(surveyResponse);
            
            log.info("Survey submitted successfully: sessionId={}, responses={}", sessionId, responses.size());
            
            return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Ankieta została przesłana!",
                "surveyId", surveyId,
                "timestamp", LocalDateTime.now().toString()
            ));
            
        } catch (Exception e) {
            log.error("Error submitting survey", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "success", false,
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        try {
            List<SurveyResponse> allResponses = surveyRepository.findAll();
            
            // Podstawowe statystyki
            long totalResponses = allResponses.size();
            
            // Oblicz średnią ocenę
            double avgRating = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("spring_performance"))
                .mapToInt(r -> {
                    Object answer = r.getAnswers().get("spring_performance");
                    if (answer instanceof String) {
                        String str = (String) answer;
                        if (str.contains("1")) return 1;
                        if (str.contains("2")) return 2;
                        if (str.contains("3")) return 3;
                        if (str.contains("4")) return 4;
                        if (str.contains("5")) return 5;
                    }
                    return 0;
                })
                .average()
                .orElse(0.0);
            
            // Unikalni użytkownicy
            long uniqueUsers = allResponses.stream()
                .map(SurveyResponse::getSessionId)
                .distinct()
                .count();
            
            // Popularność technologii
            Map<String, Long> techPopularity = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("java_tech_interest"))
                .flatMap(r -> {
                    Object answer = r.getAnswers().get("java_tech_interest");
                    if (answer instanceof List) {
                        @SuppressWarnings("unchecked")
                        List<String> techs = (List<String>) answer;
                        return techs.stream();
                    } else if (answer instanceof String) {
                        return Arrays.stream(((String) answer).split(","));
                    }
                    return Stream.empty();
                })
                .collect(Collectors.groupingBy(
                    tech -> tech.trim(),
                    Collectors.counting()
                ));
            
            // Przygotuj dane dla wykresów
            Map<String, Object> charts = new HashMap<>();
            
            // Wykres ocen
            Map<String, Object> ratingsChart = new HashMap<>();
            ratingsChart.put("labels", Arrays.asList("1", "2", "3", "4", "5"));
            ratingsChart.put("datasets", List.of(Map.of(
                "label", "Oceny wydajności Spring Boot",
                "data", Arrays.asList(10, 15, 30, 25, 20),
                "backgroundColor", "rgba(59, 130, 246, 0.5)"
            )));
            charts.put("ratings", ratingsChart);
            
            // Wykres technologii
            Map<String, Object> techChart = new HashMap<>();
            techChart.put("labels", new ArrayList<>(techPopularity.keySet()));
            techChart.put("datasets", List.of(Map.of(
                "label", "Popularność technologii",
                "data", new ArrayList<>(techPopularity.values()),
                "backgroundColor", Arrays.asList(
                    "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#06B6D4"
                )
            )));
            charts.put("technologies", techChart);
            
            Map<String, Object> response = new HashMap<>();
            response.put("totalResponses", totalResponses);
            response.put("avgRating", Math.round(avgRating * 10) / 10.0);
            response.put("uniqueUsers", uniqueUsers);
            response.put("techPopularity", techPopularity);
            response.put("charts", charts);
            response.put("lastUpdated", LocalDateTime.now().toString());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Error generating stats", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/spark/status")
    public ResponseEntity<Map<String, Object>> getSparkStatus() {
        return ResponseEntity.ok(sparkService.getSparkStatus());
    }
    
    @PostMapping("/spark/trigger")
    public ResponseEntity<Map<String, Object>> triggerSparkJob(
            @RequestParam String jobType) {
        try {
            Map<String, Object> result = sparkService.triggerSparkJob(jobType);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
}
JAVA

# Service dla Spark
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/service/SparkService.java" <<'JAVA'
package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class SparkService {
    
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final RestTemplate restTemplate;
    
    private static final String KAFKA_TOPIC = "survey-events";
    private static final String SPARK_MASTER_URL = "http://spark-master:8080";
    
    public void sendToKafka(SurveyResponse surveyResponse) {
        try {
            Map<String, Object> event = new HashMap<>();
            event.put("type", "SURVEY_SUBMITTED");
            event.put("surveyId", surveyResponse.getSurveyId());
            event.put("userId", surveyResponse.getUserId());
            event.put("timestamp", System.currentTimeMillis());
            event.put("data", surveyResponse.getAnswers());
            
            kafkaTemplate.send(KAFKA_TOPIC, surveyResponse.getSurveyId(), event);
            log.info("Sent survey to Kafka: surveyId={}", surveyResponse.getSurveyId());
            
        } catch (Exception e) {
            log.error("Error sending to Kafka", e);
        }
    }
    
    public Map<String, Object> getSparkStatus() {
        Map<String, Object> status = new HashMap<>();
        
        try {
            // Sprawdź status Spark Master
            String response = restTemplate.getForObject(
                SPARK_MASTER_URL + "/api/v1/applications", 
                String.class
            );
            
            status.put("sparkMaster", "RUNNING");
            status.put("applications", response);
            
        } catch (Exception e) {
            log.warn("Spark master not available", e);
            status.put("sparkMaster", "UNAVAILABLE");
            status.put("error", e.getMessage());
        }
        
        status.put("timestamp", System.currentTimeMillis());
        return status;
    }
    
    public Map<String, Object> triggerSparkJob(String jobType) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Tutaj można dodać wywołanie REST API Spark do uruchomienia zadania
            // lub wysłać wiadomość do Kafka, którą Spark Stream będzie nasłuchiwał
            
            Map<String, String> jobRequest = new HashMap<>();
            jobRequest.put("jobType", jobType);
            jobRequest.put("triggeredBy", "spring-boot");
            jobRequest.put("timestamp", String.valueOf(System.currentTimeMillis()));
            
            kafkaTemplate.send("spark-jobs", jobType, jobRequest);
            
            result.put("success", true);
            result.put("message", "Spark job triggered: " + jobType);
            result.put("jobId", "job_" + System.currentTimeMillis());
            
        } catch (Exception e) {
            log.error("Error triggering Spark job", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
JAVA

# Service dla ELK
cat > "${JAVA_DIR}/src/main/java/com/davtroweb/survey/service/ElkService.java" <<'JAVA'
package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class ElkService {
    
    private final RestTemplate restTemplate;
    
    private static final String ELASTICSEARCH_URL = "http://elasticsearch:9200";
    private static final String LOGSTASH_URL = "http://logstash:5000";
    
    public void logSurveySubmission(SurveyResponse surveyResponse) {
        try {
            // Przygotuj dokument dla Elasticsearch
            Map<String, Object> logEntry = new HashMap<>();
            logEntry.put("@timestamp", System.currentTimeMillis());
            logEntry.put("level", "INFO");
            logEntry.put("logger", "SurveyController");
            logEntry.put("message", "Survey submitted: " + surveyResponse.getSurveyId());
            logEntry.put("surveyId", surveyResponse.getSurveyId());
            logEntry.put("userId", surveyResponse.getUserId());
            logEntry.put("sessionId", surveyResponse.getSessionId());
            logEntry.put("responseCount", surveyResponse.getAnswers().size());
            logEntry.put("source", "spring-boot");
            
            // Wyślij do Elasticsearch
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(logEntry, headers);
            
            ResponseEntity<String> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_doc",
                request,
                String.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                log.debug("Log sent to Elasticsearch: surveyId={}", surveyResponse.getSurveyId());
            }
            
            // Równolegle wyślij do Logstash (jeśli potrzebne)
            try {
                restTemplate.postForEntity(
                    LOGSTASH_URL,
                    request,
                    String.class
                );
            } catch (Exception e) {
                log.debug("Logstash not available, skipping");
            }
            
        } catch (Exception e) {
            log.error("Error sending log to ELK", e);
        }
    }
    
    public Map<String, Object> searchLogs(String query, int size) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Przygotuj zapytanie Elasticsearch
            Map<String, Object> searchQuery = new HashMap<>();
            searchQuery.put("query", Map.of(
                "match", Map.of("message", query)
            ));
            searchQuery.put("size", size);
            searchQuery.put("sort", List.of(
                Map.of("@timestamp", Map.of("order", "desc"))
            ));
            
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(searchQuery, headers);
            
            ResponseEntity<Map> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_search",
                request,
                Map.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                result.put("success", true);
                result.put("data", response.getBody());
            } else {
                result.put("success", false);
                result.put("error", "Elasticsearch query failed");
            }
            
        } catch (Exception e) {
            log.error("Error searching logs", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
JAVA

# Konfiguracja Spring
cat > "${JAVA_DIR}/src/main/resources/application.yml" <<'YAML'
server:
  port: 8080
  servlet:
    context-path: /
    
spring:
  application:
    name: survey-spring-app
  
  data:
    mongodb:
      uri: mongodb://mongodb:27017/survey_db
      auto-index-creation: true
  
  kafka:
    bootstrap-servers: kafka:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      properties:
        spring.json.type.mapping: surveyResponse:com.davtroweb.survey.model.SurveyResponse
    consumer:
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.type.mapping: surveyResponse:com.davtroweb.survey.model.SurveyResponse
        spring.json.trusted.packages: "*"
  
  jackson:
    time-zone: UTC
    date-format: com.fasterxml.jackson.databind.util.ISO8601DateFormat

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true

logging:
  level:
    com.davtroweb.survey: DEBUG
    org.springframework.kafka: INFO
    org.apache.kafka: INFO
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"
  file:
    name: /var/log/spring-survey.log

elk:
  enabled: true
  elasticsearch:
    url: http://elasticsearch:9200
  logstash:
    url: http://logstash:5000

spark:
  master: spark://spark-master:7077
  streaming:
    enabled: true
    checkpoint-dir: /tmp/spark-checkpoints
YAML

# Dockerfile dla Spring Boot
cat > "${JAVA_DIR}/Dockerfile" <<'DOCKER'
FROM eclipse-temurin:17-jdk-alpine as builder
WORKDIR /app
COPY .mvn/ .mvn
COPY mvnw pom.xml ./
RUN ./mvnw dependency:go-offline
COPY src ./src
RUN ./mvnw clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
DOCKER

# Maven Wrapper i pom.xml
mkdir_p "${JAVA_DIR}/.mvn/wrapper"
cat > "${JAVA_DIR}/.mvn/wrapper/maven-wrapper.properties" <<'PROPS'
distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.5/apache-maven-3.9.5-bin.zip
wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.2.0/maven-wrapper-3.2.0.jar
PROPS

cat > "${JAVA_DIR}/pom.xml" <<'POM'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.davtroweb</groupId>
    <artifactId>survey-spring-app</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <name>Survey Spring Boot Application</name>
    <description>Spring Boot application for survey management with MongoDB and Kafka</description>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.1.0</version>
        <relativePath/>
    </parent>

    <properties>
        <java.version>17</java.version>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <!-- Spring Boot Starters -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-mongodb</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
        
        <!-- Kafka -->
        <dependency>
            <groupId>org.springframework.kafka</groupId>
            <artifactId>spring-kafka</artifactId>
        </dependency>
        
        <!-- Lombok -->
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
            <optional>true</optional>
        </dependency>
        
        <!-- Monitoring -->
        <dependency>
            <groupId>io.micrometer</groupId>
            <artifactId>micrometer-registry-prometheus</artifactId>
        </dependency>
        
        <!-- Testing -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.kafka</groupId>
            <artifactId>spring-kafka-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    <excludes>
                        <exclude>
                            <groupId>org.projectlombok</groupId>
                            <artifactId>lombok</artifactId>
                        </exclude>
                    </excludes>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
POM
}

generate_spark_jobs(){
 # Główne zadanie Spark
cat > "${SPARK_DIR}/src/main/scala/com/davtroweb/analytics/SurveyAnalytics.scala" <<'SCALA'
package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.{OutputMode, Trigger}
import org.apache.spark.sql.{Dataset, Row}
import java.time.LocalDateTime
import scala.collection.JavaConverters._

object SurveyAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("SurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .config("spark.kryoserializer.buffer.max", "512m")
      .getOrCreate()
    
    import spark.implicits._
    
    // Schemat danych ankietowych
    val surveySchema = StructType(Array(
      StructField("surveyId", StringType, nullable = false),
      StructField("userId", StringType, nullable = true),
      StructField("sessionId", StringType, nullable = false),
      StructField("answers", MapType(StringType, StringType), nullable = false),
      StructField("submittedAt", TimestampType, nullable = false),
      StructField("metadata", StructType(Array(
        StructField("surveyType", StringType, nullable = true),
        StructField("browser", StringType, nullable = true),
        StructField("ipAddress", StringType, nullable = true)
      )))
    ))
    
    // Czytaj dane z Kafka
    val kafkaStream = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "kafka:9092")
      .option("subscribe", "survey-events")
      .option("startingOffsets", "latest")
      .load()
    
    // Przetwórz dane JSON
    val surveyStream = kafkaStream
      .select(from_json(col("value").cast("string"), surveySchema).as("data"))
      .select("data.*")
    
    // 1. Analiza sentymentu odpowiedzi tekstowych
    val textAnalysis = surveyStream
      .filter(col("answers").getItem("architecture_suggestions").isNotNull)
      .select(
        col("surveyId"),
        col("userId"),
        col("answers").getItem("architecture_suggestions").as("suggestion"),
        col("submittedAt")
      )
      .withColumn("suggestion_length", length(col("suggestion")))
      .withColumn("suggestion_words", size(split(col("suggestion"), " ")))
      .withColumn("sentiment_score", 
        when(col("suggestion").contains("dobr") || col("suggestion").contains("super") || 
             col("suggestion").contains("świetn"), 1.0)
        .when(col("suggestion").contains("kieps") || col("suggestion").contains("słab") || 
              col("suggestion").contains("problem"), -1.0)
        .otherwise(0.0)
      )
    
    // 2. Agregacje ocen
    val ratingAnalysis = surveyStream
      .filter(col("answers").getItem("spring_performance").isNotNull)
      .select(
        col("surveyId"),
        col("answers").getItem("spring_performance").as("rating"),
        col("submittedAt")
      )
      .withColumn("rating_numeric", 
        when(col("rating").contains("1"), 1)
        .when(col("rating").contains("2"), 2)
        .when(col("rating").contains("3"), 3)
        .when(col("rating").contains("4"), 4)
        .when(col("rating").contains("5"), 5)
        .otherwise(0)
      )
      .groupBy(window(col("submittedAt"), "5 minutes").as("window"))
      .agg(
        count("*").as("total_responses"),
        avg("rating_numeric").as("avg_rating"),
        stddev("rating_numeric").as("rating_stddev"),
        collect_list("rating_numeric").as("all_ratings")
      )
    
    // 3. Analiza popularności technologii
    val techAnalysis = surveyStream
      .filter(col("answers").getItem("java_tech_interest").isNotNull)
      .select(
        explode(split(col("answers").getItem("java_tech_interest"), ",")).as("technology"),
        col("submittedAt")
      )
      .withColumn("technology_clean", trim(col("technology")))
      .groupBy(col("technology_clean"))
      .agg(
        count("*").as("total_votes"),
        countDistinct("submittedAt").as("unique_sessions")
      )
      .orderBy(desc("total_votes"))
    
    // 4. Zapisz wyniki do MongoDB
    val query1 = textAnalysis.writeStream
      .outputMode(OutputMode.Append())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "text_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
    
    val query2 = ratingAnalysis.writeStream
      .outputMode(OutputMode.Update())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "rating_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()
    
    val query3 = techAnalysis.writeStream
      .outputMode(OutputMode.Complete())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("overwrite")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "tech_popularity")
          .save()
      }
      .trigger(Trigger.ProcessingTime("2 minutes"))
      .start()
    
    // 5. Zapisz logi do Elasticsearch
    val elkStream = surveyStream
      .select(
        lit("survey_event").as("type"),
        col("surveyId"),
        col("userId"),
        col("sessionId"),
        col("submittedAt"),
        to_json(col("answers")).as("answers_json"),
        lit(LocalDateTime.now().toString).as("@timestamp")
      )
    
    val query4 = elkStream.writeStream
      .outputMode(OutputMode.Append())
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "spark_surveys/_doc")
      .option("checkpointLocation", "/tmp/elk-checkpoint")
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()
    
    // Czekaj na zakończenie
    spark.streams.awaitAnyTermination()
  }
}
SCALA

# Zadanie batch Spark
cat > "${SPARK_DIR}/src/main/scala/com/davtroweb/analytics/BatchAnalytics.scala" <<'SCALA'
package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.expressions.Window
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object BatchAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("BatchSurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.mongodb.input.uri", "mongodb://mongodb:27017/survey_db.survey_responses")
      .config("spark.mongodb.output.uri", "mongodb://mongodb:27017/survey_analytics")
      .getOrCreate()
    
    import spark.implicits._
    
    // Czytaj dane z MongoDB
    val surveyDF = spark.read
      .format("mongo")
      .option("database", "survey_db")
      .option("collection", "survey_responses")
      .load()
    
    // 1. Dzienne statystyki
    val dailyStats = surveyDF
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date")
      .agg(
        count("*").as("total_submissions"),
        countDistinct($"userId").as("unique_users"),
        countDistinct($"sessionId").as("unique_sessions"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0)).as("avg_rating")
      )
      .orderBy(desc("date"))
    
    // 2. Analiza trendów technologicznych
    val techTrends = surveyDF
      .filter($"answers.java_tech_interest".isNotNull)
      .withColumn("technology", explode(split($"answers.java_tech_interest", ",")))
      .withColumn("technology_clean", trim($"technology"))
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date", $"technology_clean")
      .agg(count("*").as("daily_votes"))
      .orderBy(desc("date"), desc("daily_votes"))
    
    // 3. Korelacje między odpowiedziami
    val correlations = surveyDF
      .select(
        when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0).as("spring_rating"),
        when($"answers.integration_quality".contains("5"), 5)
          .when($"answers.integration_quality".contains("4"), 4)
          .when($"answers.integration_quality".contains("3"), 3)
          .when($"answers.integration_quality".contains("2"), 2)
          .when($"answers.integration_quality".contains("1"), 1)
          .otherwise(0).as("integration_rating"),
        when($"answers.elk_usefulness".contains("Tak, zdecydowanie"), 2)
          .when($"answers.elk_usefulness".contains("Raczej tak"), 1)
          .when($"answers.elk_usefulness".contains("Raczej nie"), -1)
          .when($"answers.elk_usefulness".contains("Nie"), -2)
          .otherwise(0).as("elk_sentiment")
      )
      .na.drop()
      .agg(
        corr("spring_rating", "integration_rating").as("spring_integration_corr"),
        corr("spring_rating", "elk_sentiment").as("spring_elk_corr"),
        corr("integration_rating", "elk_sentiment").as("integration_elk_corr")
      )
    
    // 4. Raport godzinowy
    val hourlyReport = surveyDF
      .withColumn("hour", hour($"submittedAt"))
      .groupBy($"hour")
      .agg(
        count("*").as("submissions"),
        countDistinct($"userId").as("users"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .otherwise(3)).as("avg_rating")
      )
      .orderBy("hour")
    
    // 5. Zapisz wyniki do MongoDB
    dailyStats.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "daily_stats")
      .save()
    
    techTrends.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "tech_trends")
      .save()
    
    correlations.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "correlations")
      .save()
    
    hourlyReport.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "hourly_report")
      .save()
    
    // 6. Wygeneruj raport do Elasticsearch
    val reportTimestamp = LocalDateTime.now()
      .format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))
    
    val finalReport = spark.createDataFrame(Seq(
      (reportTimestamp, dailyStats.count(), hourlyReport.count(), 
       correlations.first().getAs[Double]("spring_integration_corr"))
    )).toDF("generated_at", "total_days", "total_hours", "avg_correlation")
    
    finalReport.write
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "survey_reports/_doc")
      .save()
    
    spark.stop()
  }
}
SCALA

# Build dla Spark
cat > "${SPARK_DIR}/build.sbt" <<'SBT'
name := "survey-spark-analytics"
version := "1.0.0"
scalaVersion := "2.12.15"

val sparkVersion = "3.4.0"

libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-streaming" % sparkVersion % "provided",
  "org.apache.spark" %% "spark-sql-kafka-0-10" % sparkVersion,
  "org.apache.spark" %% "spark-streaming-kafka-0-10" % sparkVersion,
  "org.mongodb.spark" %% "mongo-spark-connector" % "10.1.1",
  "org.elasticsearch" %% "elasticsearch-spark-30" % "8.10.2",
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.2",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.2"
)

assemblyMergeStrategy in assembly := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case x => MergeStrategy.first
}
SBT
}

generate_dockerfile(){
 cat > "${ROOT_DIR}/Dockerfile" <<'DOCK'
FROM python:3.11-slim-bullseye
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ /app/
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCK
}

generate_github_actions(){
 mkdir_p "$WORKFLOW_DIR"
 cat > "${WORKFLOW_DIR}/ci-cd-extended.yaml" <<'YAML'
name: CI/CD Extended - Full Stack

on:
  push:
    branches: [main]
    paths:
      - 'app/**'
      - 'java-app/**'
      - 'spark-jobs/**'
      - 'manifests/**'
      - 'Dockerfile'
      - '.github/workflows/ci-cd-extended.yaml'
  workflow_dispatch:

jobs:
  build-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Python Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar:${{ github.sha }}
          cache-from: type=registry,ref=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar:latest
          cache-to: type=inline

  build-spring:
    runs-on: ubuntu-latest
    needs: build-python
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          java-version: '17'
          distribution: 'temurin'
      
      - name: Build Spring Boot
        working-directory: ./java-app
        run: |
          chmod +x mvnw
          ./mvnw clean package -DskipTests
      
      - name: Build Spring Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./java-app
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spring:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spring:${{ github.sha }}

  build-spark:
    runs-on: ubuntu-latest
    needs: build-spring
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Scala
        uses: olafurpg/setup-scala@v13
        with:
          java-version: adopt@1.11
      
      - name: Build Spark Jobs
        working-directory: ./spark-jobs
        run: |
          sbt assembly
      
      - name: Build Spark Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./spark-jobs
          push: true
          tags: |
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spark:latest
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spark:${{ github.sha }}

  deploy:
    runs-on: ubuntu-latest
    needs: [build-python, build-spring, build-spark]
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure Kustomize
        run: |
          cd manifests/base
          kustomize edit set image \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar:${{ github.sha }} \
            ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spring=ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spring:${{ github.sha }}
      
      - name: Deploy to Kubernetes
        run: |
          kubectl apply -k manifests/base --namespace=davtroelkpyjs
          kubectl rollout status deployment/fastapi-web-app -n davtroelkpyjs --timeout=300s
          kubectl rollout status deployment/spring-app -n davtroelkpyjs --timeout=300s
          kubectl rollout status deployment/spark-master -n davtroelkpyjs --timeout=300s
          kubectl rollout status deployment/spark-worker -n davtroelkpyjs --timeout=300s
      
      - name: Verify Deployment
        run: |
          kubectl get pods -n davtroelkpyjs
          kubectl get svc -n davtroelkpyjs
YAML
}

generate_k8s_manifests(){
 # Podstawowe manifesty z pierwszego skryptu (zaktualizowane namespace)
 cat > "${BASE_DIR}/fastapi-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: fastapi-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
data:
  APP_NAME: "${PROJECT}"
  APP_ENV: "production"
  PYTHONUNBUFFERED: "1"
YAML

 cat > "${BASE_DIR}/app-deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-web-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: fastapi
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: fastapi
    spec:
      serviceAccountName: fastapi-sa
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            [
              "sh",
              "-c",
              'until pg_isready -h postgres-db-normal -p 5432 -U webuser; do echo "waiting for postgres..."; sleep 5; done; echo "postgres ready"',
            ]
          env:
            - name: PGPASSWORD
              value: "testpassword"
            - name: PGUSER
              value: "webuser"
        - name: wait-for-redis
          image: busybox:1.36
          command:
            [
              "sh",
              "-c",
              'until nc -z redis 6379; do echo "waiting for redis..."; sleep 5; done; echo "redis ready"',
            ]
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            [
              "/bin/bash",
              "-c",
              'for i in {1..120}; do if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then echo "✓ kafka broker ready"; break; fi; echo "Attempt \$i/120: Kafka not ready..."; sleep 5; done',
            ]
      containers:
      - name: app
        image: ${REGISTRY}:latest
        ports:
        - containerPort: 8000
        env:
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "outgoing_messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_TOPIC
          value: "survey-topic"
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN
          value: "root"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432"
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 30
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 20
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-web-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: fastapi
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: fastapi
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8000
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: fastapi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
YAML

 cat > "${BASE_DIR}/message-processor.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: message-processor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: worker
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: worker
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: worker
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            [
              "sh",
              "-c",
              'until pg_isready -h postgres-db-normal -p 5432 -U webuser; do echo "waiting for postgres..."; sleep 5; done; echo "postgres ready"',
            ]
          env:
            - name: PGPASSWORD
              value: "testpassword"
            - name: PGUSER
              value: "webuser"
        - name: wait-for-redis
          image: busybox:1.36
          command:
            [
              "sh",
              "-c",
              'until nc -z redis 6379; do echo "waiting for redis..."; sleep 5; done; echo "redis ready"',
            ]
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            [
              "/bin/bash",
              "-c",
              'for i in {1..120}; do if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then echo "✓ kafka broker ready"; break; fi; echo "Attempt \$i/120: Kafka not ready..."; sleep 5; done',
            ]
      containers:
      - name: worker
        image: ${REGISTRY}:latest
        command: ["python", "worker.py"]
        env:
        - name: REDIS_HOST
          value: "redis"
        - name: REDIS_PORT
          value: "6379"
        - name: REDIS_LIST
          value: "outgoing_messages"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_TOPIC
          value: "survey-topic"
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN
          value: "root"
        - name: DATABASE_URL
          value: "dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          exec:
            command:
              - sh
              - -c
              - 'python -c "import redis; redis.Redis(host=\"redis\", port=6379, socket_connect_timeout=5).ping()"'
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          exec:
            command:
              - sh
              - -c
              - 'python -c "import redis; redis.Redis(host=\"redis\", port=6379, socket_connect_timeout=5).ping()"'
          initialDelaySeconds: 30
          periodSeconds: 10
YAML

 cat > "${BASE_DIR}/postgres-db.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres
spec:
  ports:
  - port: 5432
    name: postgres
  selector:
    app: ${PROJECT}
    component: postgres
  clusterIP: None
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-db
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres
spec:
  serviceName: postgres-db
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: postgres
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: postgres
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 999
        runAsNonRoot: true
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_USER
          value: "webuser"
        - name: POSTGRES_PASSWORD
          value: "testpassword"
        - name: POSTGRES_DB
          value: "webdb"
        - name: PGDATA
          value: "/var/lib/postgresql/data/pgdata"
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          exec:
            command: ["pg_isready", "-U", "webuser", "-d", "webdb"]
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "webuser", "-d", "webdb"]
          initialDelaySeconds: 30
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
YAML

 cat > "${BASE_DIR}/postgres-clusterip.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: postgres-db-normal
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: ${PROJECT}
    component: postgres
YAML

 cat > "${BASE_DIR}/pgadmin.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgadmin-servers
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  servers.json: |
    {
      "Servers": {
        "1": {
          "Name": "PostgreSQL Database",
          "Group": "Servers",
          "Host": "postgres-db-normal",
          "Port": 5432,
          "MaintenanceDB": "webdb",
          "Username": "webuser",
          "Password": "testpassword",
          "SSLMode": "prefer"
        }
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: pgadmin
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: pgadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: pgadmin
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: pgadmin
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: pgadmin
    spec:
      initContainers:
        - name: wait-for-postgres
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for PostgreSQL to be ready..."
              until nc -z postgres-db-normal 5432; do
                echo "Waiting for PostgreSQL..."
                sleep 10
              done
              echo "PostgreSQL is ready!"
      containers:
        - name: pgadmin
          image: dpage/pgadmin4:7.2
          env:
            - name: PGADMIN_DEFAULT_EMAIL
              value: "admin@example.com"
            - name: PGADMIN_DEFAULT_PASSWORD
              value: "adminpassword"
            - name: PGADMIN_CONFIG_SERVER_MODE
              value: "False"
            - name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
              value: "False"
          ports:
            - containerPort: 80
              name: http
          resources:
            requests:
              cpu: "100m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 120
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /misc/ping
              port: 80
            initialDelaySeconds: 60
            periodSeconds: 10
          volumeMounts:
            - name: pgadmin-data
              mountPath: /var/lib/pgadmin
            - name: pgadmin-servers
              mountPath: /pgadmin4/servers.json
              subPath: servers.json
      volumes:
        - name: pgadmin-data
          persistentVolumeClaim:
            claimName: pgadmin-storage
        - name: pgadmin-servers
          configMap:
            name: pgadmin-servers
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: pgadmin
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: pgadmin
spec:
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: ${PROJECT}
    component: pgadmin
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
YAML

resources=$(cat <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: davtroelkpyjs
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
    component: vault
spec:
  clusterIP: None
  ports:
  - port: 8200
    name: http
  selector:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
    component: vault
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: davtroelkpyjs
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
    component: vault
spec:
  serviceName: vault
  replicas: 1
  selector:
    matchLabels:
      app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
      component: vault
  template:
    metadata:
      labels:
        app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
        component: vault
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault
        image: hashicorp/vault:1.15.0
        command: ["vault", "server", "-dev", "-dev-listen-address=0.0.0.0:8200", "-dev-root-token-id=root"]
        ports:
        - containerPort: 8200
        env:
        - name: VAULT_ADDR
          value: "http://127.0.0.1:8200"
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
        securityContext:
          capabilities:
            add: ["IPC_LOCK"]
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /v1/sys/health
            port: 8200
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /v1/sys/health
            port: 8200
          initialDelaySeconds: 15
          periodSeconds: 15
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-sa
  namespace: davtroelkpyjs
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-init
  namespace: davtroelkpyjs
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
data:
  init-vault.sh: |
    #!/bin/bash
    sleep 10
    export VAULT_ADDR="http://vault:8200"
    export VAULT_TOKEN="root"
    
    vault secrets enable -path=secret kv-v2
    
    vault kv put secret/database/postgres \
      postgres-user="webuser" \
      postgres-password="testpassword" \
      postgres-db="webdb" \
      postgres-host="postgres-db-normal"
    
    vault kv put secret/redis \
      redis-password=""
    
    vault kv put secret/kafka \
      kafka-brokers="kafka:9092"
    
    vault kv put secret/grafana \
      admin-user="admin" \
      admin-password="admin"
    
    vault kv put secret/pgadmin \
      pgadmin-email="admin@example.com" \
      pgadmin-password="adminpassword"
    
    echo "Vault initialization completed"
---
apiVersion: batch/v1
kind: Job
metadata:
  name: vault-init
  namespace: davtroelkpyjs
  labels:
    app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
    component: vault-init
spec:
  template:
    metadata:
      labels:
        app: website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar
        component: vault-init
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: vault-init
        image: hashicorp/vault:1.15.0
        command: ["/bin/sh", "/scripts/init-vault.sh"]
        volumeMounts:
        - name: vault-scripts
          mountPath: /scripts
        env:
        - name: VAULT_ADDR
          value: "http://vault:8200"
        - name: VAULT_TOKEN  
          value: "root"
      volumes:
      - name: vault-scripts
        configMap:
          name: vault-init
          defaultMode: 0755
      restartPolicy: OnFailure
  backoffLimit: 3
YAML
)

echo "$resources" > "${BASE_DIR}/vault.yaml"

 cat > "${BASE_DIR}/redis.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: redis
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: redis
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        command: ["redis-server", "--appendonly", "yes"]
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        livenessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          exec:
            command: ["redis-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: redis
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: redis
YAML

 cat > "${BASE_DIR}/kafka-kraft.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka
spec:
  clusterIP: None
  ports:
  - port: 9092
    name: client
  - port: 9093
    name: controller
  selector:
    app: ${PROJECT}
    component: kafka
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka
spec:
  serviceName: kafka
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.5.0
        env:
        - name: CLUSTER_ID
          value: "1TDYjwQaTrSOTzez8sKYEg"
        - name: KAFKA_BROKER_ID
          value: "0"
        - name: KAFKA_PROCESS_ROLES
          value: "broker,controller"
        - name: KAFKA_CONTROLLER_QUORUM_VOTERS
          value: "0@kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9093"
        - name: KAFKA_LISTENERS
          value: "PLAINTEXT://:9092,CONTROLLER://:9093"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: "PLAINTEXT://kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
        - name: KAFKA_CONTROLLER_LISTENER_NAMES
          value: "CONTROLLER"
        - name: KAFKA_INTER_BROKER_LISTENER_NAME
          value: "PLAINTEXT"
        - name: KAFKA_AUTO_CREATE_TOPICS_ENABLE
          value: "true"
        - name: KAFKA_LOG_DIR
          value: "/var/lib/kafka/data"
        - name: KAFKA_LOG_RETENTION_HOURS
          value: "168"
        - name: KAFKA_AUTO_LEADER_REBALANCE_ENABLE
          value: "true"
        ports:
        - containerPort: 9092
          name: client
        - containerPort: 9093
          name: controller
        volumeMounts:
        - name: kafka-data
          mountPath: /var/lib/kafka/data/
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        readinessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 60
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 90
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: kafka-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
YAML

 cat > "${BASE_DIR}/kafka-job-sa.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-job-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-topic-job
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
YAML

 cat > "${BASE_DIR}/kafka-topic-job.yaml" <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: create-kafka-topics
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-topic-job
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-topic-job
spec:
  backoffLimit: 5
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-topic-job
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-topic-job
    spec:
      serviceAccountName: kafka-job-sa
      initContainers:
        - name: wait-for-kafka-broker
          image: confluentinc/cp-kafka:7.5.0
          command:
            - /bin/bash
            - -c
            - |
              echo "Waiting for Kafka broker to be ready..."
              for i in {1..120}; do
                if /opt/confluent/bin/kafka-broker-api-versions --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 &>/dev/null; then
                  echo "✓ Kafka broker is ready!"
                  exit 0
                fi
                echo "Attempt \$i/120: Kafka not ready..."
                sleep 5
              done
              echo "✗ Kafka broker failed to start"
              exit 1
      containers:
        - name: create-topics
          image: confluentinc/cp-kafka:7.5.0
          command:
            - /bin/bash
            - -c
            - |
              set -e
              echo "Creating Kafka topics..."
              
              /opt/confluent/bin/kafka-topics --create \
                --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092 \
                --topic survey-topic \
                --partitions 3 \
                --replication-factor 1 \
                --config retention.ms=604800000 \
                --config min.insync.replicas=1 \
                --if-not-exists
              
              echo "Verifying topics..."
              /opt/confluent/bin/kafka-topics --list \
                --bootstrap-server kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092
              
              echo "✓ Kafka topics created successfully"
      restartPolicy: OnFailure
YAML

 cat > "${BASE_DIR}/kafka-ui.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-ui
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-ui
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-ui
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-ui
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-ui
    spec:
      initContainers:
        - name: wait-for-kafka
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for Kafka broker to be ready..."
              until nc -z kafka-0.kafka.${NAMESPACE}.svc.cluster.local 9092; do
                echo "Waiting for Kafka..."
                sleep 10
              done
              echo "Kafka is ready!"
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: "local"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: "kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092"
        - name: KAFKA_CLUSTERS_0_READONLY
          value: "false"
        - name: KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL
          value: "PLAINTEXT"
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "200m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-ui
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-ui
spec:
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: kafka-ui
YAML

 cat > "${BASE_DIR}/prometheus-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    rule_files:
      - /etc/prometheus/rules/*.yml
    
    scrape_configs:
      - job_name: 'fastapi'
        static_configs:
          - targets: ['fastapi-web-service:80']
        metrics_path: /metrics
        scrape_interval: 10s
        
      - job_name: 'redis'
        static_configs:
          - targets: ['redis:6379']
        metrics_path: /metrics
        scrape_interval: 15s
        
      - job_name: 'postgres'
        static_configs:
          - targets: ['postgres-exporter:9187']
        scrape_interval: 30s
        
      - job_name: 'kafka'
        static_configs:
          - targets: ['kafka-exporter:9308']
        scrape_interval: 30s
        
      - job_name: 'vault'
        static_configs:
          - targets: ['vault:8200']
        metrics_path: /v1/sys/metrics
        scrape_interval: 30s
        params:
          format: ['prometheus']
          
      - job_name: 'node-exporter'
        static_configs:
          - targets: ['node-exporter:9100']
        scrape_interval: 30s
YAML

 cat > "${BASE_DIR}/postgres-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: postgres-exporter
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: postgres-exporter
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:15-alpine
          command:
            - "sh"
            - "-c"
            - |
              until pg_isready -h postgres-db-normal -p 5432 -U webuser; do
                echo "Waiting for postgres..."
                sleep 5
              done
              echo "PostgreSQL is ready!"
          env:
            - name: PGPASSWORD
              value: "testpassword"
      containers:
      - name: postgres-exporter
        image: prometheuscommunity/postgres-exporter:v0.15.0
        ports:
        - containerPort: 9187
          name: http
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://webuser:testpassword@postgres-db-normal:5432/webdb?sslmode=disable"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9187
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9187
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: postgres-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: postgres-exporter
spec:
  ports:
  - port: 9187
    targetPort: 9187
    name: http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: postgres-exporter
YAML

 cat > "${BASE_DIR}/kafka-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kafka-exporter
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: kafka-exporter
    spec:
      initContainers:
        - name: wait-for-kafka
          image: busybox:1.35
          command:
            - "sh"
            - "-c"
            - |
              echo "Waiting for Kafka broker to be ready..."
              until nc -z kafka-0.kafka.${NAMESPACE}.svc.cluster.local 9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
              echo "Kafka is ready!"
      containers:
      - name: kafka-exporter
        image: danielqsj/kafka-exporter:v1.7.0
        ports:
        - containerPort: 9308
          name: http
        args:
        - --kafka.server=kafka-0.kafka.${NAMESPACE}.svc.cluster.local:9092
        - --web.listen-address=:9308
        - --log.level=info
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9308
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kafka-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: kafka-exporter
spec:
  ports:
  - port: 9308
    targetPort: 9308
    name: http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: kafka-exporter
YAML

 cat > "${BASE_DIR}/node-exporter.yaml" <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: node-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: node-exporter
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: node-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: node-exporter
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: node-exporter
    spec:
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
        args:
        - --path.procfs=/host/proc
        - --path.sysfs=/host/sys
        - --path.rootfs=/host/root
        - --collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)
        volumeMounts:
        - name: proc
          mountPath: /host/proc
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host/root
          readOnly: true
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
      - name: root
        hostPath:
          path: /
      hostNetwork: true
      hostPID: true
      tolerations:
      - effect: NoSchedule
        operator: Exists
---
apiVersion: v1
kind: Service
metadata:
  name: node-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: node-exporter
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: node-exporter
spec:
  ports:
  - port: 9100
    targetPort: 9100
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: node-exporter
  clusterIP: None
YAML

 cat > "${BASE_DIR}/service-monitors.yaml" <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: fastapi-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  endpoints:
  - port: http
    path: /metrics
    interval: 15s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  endpoints:
  - port: redis
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: postgres-exporter
  endpoints:
  - port: http
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-exporter
  endpoints:
  - port: http
    interval: 30s

---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: node-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: node-exporter
  endpoints:
  - port: http
    interval: 30s
YAML

 cat > "${BASE_DIR}/prometheus.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: prometheus
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: prometheus
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: prometheus
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: prometheus
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.48.0
        ports:
        - containerPort: 9090
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
        - name: data
          mountPath: /prometheus
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
        args:
        - '--config.file=/etc/prometheus/prometheus.yml'
        - '--storage.tsdb.path=/prometheus'
        - '--web.console.libraries=/etc/prometheus/console_libraries'
        - '--web.console.templates=/etc/prometheus/consoles'
        - '--storage.tsdb.retention.time=200h'
        - '--web.enable-lifecycle'
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: data
        persistentVolumeClaim:
          claimName: prometheus-data
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: prometheus
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: prometheus
spec:
  ports:
  - port: 9090
    targetPort: 9090
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: prometheus
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
YAML

 cat > "${BASE_DIR}/grafana-datasource.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-service:9090
      isDefault: true
      access: proxy
      editable: true
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
      editable: true
    - name: Tempo
      type: tempo
      url: http://tempo:3200
      access: proxy
      editable: true
    - name: PostgreSQL
      type: postgres
      url: postgres-db-normal:5432
      database: webdb
      user: webuser
      secureJsonData:
        password: "testpassword"
      jsonData:
        sslmode: "disable"
YAML

 cat > "${BASE_DIR}/grafana-dashboards.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  fastapi-dashboard.json: |-
    {
      "dashboard": {
        "title": "FastAPI Application Metrics",
        "panels": [
          {
            "title": "HTTP Requests",
            "type": "stat",
            "targets": [
              {
                "expr": "rate(http_requests_total[5m])",
                "legendFormat": "Requests/s"
              }
            ]
          }
        ]
      }
    }
  kafka-dashboard.json: |-
    {
      "dashboard": {
        "title": "Kafka Metrics", 
        "panels": [
          {
            "title": "Messages In",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(kafka_topic_messages_in_total[5m])",
                "legendFormat": "Messages/s"
              }
            ]
          }
        ]
      }
    }
  postgres-dashboard.json: |-
    {
      "dashboard": {
        "title": "PostgreSQL Metrics",
        "panels": [
          {
            "title": "Database Connections",
            "type": "stat",
            "targets": [
              {
                "expr": "pg_stat_database_numbackends{datname=\"webdb\"}",
                "legendFormat": "Connections"
              }
            ]
          }
        ]
      }
    }
  redis-dashboard.json: |-
    {
      "dashboard": {
        "title": "Redis Metrics",
        "panels": [
          {
            "title": "Connected Clients",
            "type": "stat",
            "targets": [
              {
                "expr": "redis_connected_clients",
                "legendFormat": "Clients"
              }
            ]
          }
        ]
      }
    }
  system-dashboard.json: |-
    {
      "dashboard": {
        "title": "System Metrics",
        "panels": [
          {
            "title": "CPU Usage",
            "type": "gauge",
            "targets": [
              {
                "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
                "legendFormat": "CPU %"
              }
            ]
          }
        ]
      }
    }
  vault-dashboard.json: |-
    {
      "dashboard": {
        "title": "Vault Metrics",
        "panels": [
          {
            "title": "Vault Health",
            "type": "stat",
            "targets": [
              {
                "expr": "vault_core_unsealed",
                "legendFormat": "Unsealed"
              }
            ]
          }
        ]
      }
    }
  comprehensive-dashboard.json: |-
    {
      "dashboard": {
        "title": "Comprehensive Monitoring",
        "panels": [
          {
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "title": "Application Overview",
            "type": "stat",
            "targets": [
              {
                "expr": "rate(http_requests_total[5m])",
                "legendFormat": "HTTP Requests/s"
              }
            ]
          }
        ]
      }
    }
YAML

 cat > "${BASE_DIR}/grafana.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: grafana
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: grafana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: grafana
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: grafana
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.2.2
        ports:
        - containerPort: 3000
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources
        - name: grafana-dashboards
          mountPath: /etc/grafana/provisioning/dashboards
        - name: dashboards
          mountPath: /var/lib/grafana/dashboards
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana-storage
      - name: grafana-datasources
        configMap:
          name: grafana-datasource
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboard-provisioning
      - name: dashboards
        configMap:
          name: grafana-dashboards
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: grafana
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: grafana
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: grafana
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-provisioning
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  dashboards.yaml: |
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      updateIntervalSeconds: 10
      allowUiUpdates: true
      options:
        path: /var/lib/grafana/dashboards
YAML

 cat > "${BASE_DIR}/loki-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  loki.yaml: |
    auth_enabled: false
    
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      
    common:
      path_prefix: /tmp/loki
      storage:
        filesystem:
          chunks_directory: /tmp/loki/chunks
          rules_directory: /tmp/loki/rules
      replication_factor: 1
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
    
    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h
    
    ruler:
      alertmanager_url: http://localhost:9093
    
    analytics:
      reporting_enabled: false
YAML

 cat > "${BASE_DIR}/loki.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: loki
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: loki
spec:
  serviceName: loki
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: loki
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: loki
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: loki
    spec:
      containers:
      - name: loki
        image: grafana/loki:2.9.2
        ports:
        - containerPort: 3100
        - containerPort: 9096
        volumeMounts:
        - name: config
          mountPath: /etc/loki
        - name: storage
          mountPath: /tmp/loki
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
        args:
        - -config.file=/etc/loki/loki.yaml
      volumes:
      - name: config
        configMap:
          name: loki-config
      - name: storage
        persistentVolumeClaim:
          claimName: loki-storage
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: loki
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: loki
spec:
  ports:
  - port: 3100
    targetPort: 3100
    protocol: TCP
  - port: 9096
    targetPort: 9096
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: loki
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-storage
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
YAML

 cat > "${BASE_DIR}/promtail-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    
    positions:
      filename: /tmp/positions.yaml
    
    clients:
      - url: http://loki:3100/loki/api/v1/push
    
    scrape_configs:
    - job_name: kubernetes-pods
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_kubernetes_io_config_mirror]
        action: drop
        regex: mirror
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: container
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: instance
      - source_labels: [__meta_kubernetes_pod_container_name]
        action: replace
        target_label: job
      - replacement: /var/log/pods/*\$1/*.log
        separator: /
        source_labels:
        - __meta_kubernetes_pod_uid
        - __meta_kubernetes_pod_container_name
        target_label: __path__
    
    - job_name: kubernetes-system
      static_configs:
      - targets:
          - localhost
        labels:
          job: kubernetes-system
          __path__: /var/log/containers/*.log
YAML

 cat > "${BASE_DIR}/promtail.yaml" <<YAML
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: promtail
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: promtail
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: promtail
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: promtail
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: promtail
    spec:
      serviceAccountName: promtail-sa
      containers:
      - name: promtail
        image: grafana/promtail:2.9.2
        volumeMounts:
        - name: config
          mountPath: /etc/promtail
        - name: pods
          mountPath: /var/log/pods
          readOnly: true
        - name: containers
          mountPath: /var/log/containers
          readOnly: true
        - name: varlib
          mountPath: /var/lib
          readOnly: true
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "100m"
            memory: "128Mi"
        args:
        - -config.file=/etc/promtail/promtail.yaml
      volumes:
      - name: config
        configMap:
          name: promtail-config
      - name: pods
        hostPath:
          path: /var/log/pods
      - name: containers
        hostPath:
          path: /var/log/containers
      - name: varlib
        hostPath:
          path: /var/lib
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: promtail-sa
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: promtail-clusterrole
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: promtail-clusterrolebinding
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: promtail-clusterrole
subjects:
- kind: ServiceAccount
  name: promtail-sa
  namespace: ${NAMESPACE}
YAML

 cat > "${BASE_DIR}/tempo-config.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: tempo-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
data:
  tempo.yaml: |
    server:
      http_listen_port: 3200
    
    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
            http:
    
    storage:
      trace:
        backend: local
        local:
          path: /tmp/tempo/blocks
        pool:
          max_workers: 100
          queue_depth: 10000
    
    ingester:
      max_block_duration: 5m
YAML

 cat > "${BASE_DIR}/tempo.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: tempo
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: tempo
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: tempo
spec:
  serviceName: tempo
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: tempo
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: tempo
        app.kubernetes.io/name: ${PROJECT}
        app.kubernetes.io/instance: ${PROJECT}
        app.kubernetes.io/component: tempo
    spec:
      containers:
      - name: tempo
        image: grafana/tempo:2.4.2
        ports:
        - containerPort: 3200
        - containerPort: 4317
        - containerPort: 4318
        volumeMounts:
        - name: config
          mountPath: /etc/tempo
        - name: storage
          mountPath: /tmp/tempo
        resources:
          requests:
            cpu: "100m"
            memory: "256Mi"
          limits:
            cpu: "250m"
            memory: "512Mi"
        args:
        - -config.file=/etc/tempo/tempo.yaml
      volumes:
      - name: config
        configMap:
          name: tempo-config
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tempo
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: tempo
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
    app.kubernetes.io/component: tempo
spec:
  ports:
  - port: 3200
    targetPort: 3200
    name: http
    protocol: TCP
  - port: 4317
    targetPort: 4317
    name: otlp-grpc
    protocol: TCP
  - port: 4318
    targetPort: 4318
    name: otlp-http
    protocol: TCP
  selector:
    app: ${PROJECT}
    component: tempo
YAML

 # Nowe manifesty z drugiego skryptu
 cat > "${BASE_DIR}/mongodb.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:7.0
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_ROOT_USERNAME
              value: "admin"
            - name: MONGO_INITDB_ROOT_PASSWORD
              value: "adminpassword"
          volumeMounts:
            - name: mongodb-data
              mountPath: /data/db
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            exec:
              command:
                - mongosh
                - --eval
                - "db.adminCommand('ping')"
            initialDelaySeconds: 30
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: mongodb-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
spec:
  ports:
    - port: 27017
      targetPort: 27017
  selector:
    app: ${PROJECT}
    component: mongodb
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb
data:
  init.js: |
    db = db.getSiblingDB('survey_db');
    
    db.createUser({
      user: 'survey_user',
      pwd: 'survey_password',
      roles: [
        { role: 'readWrite', db: 'survey_db' },
        { role: 'readWrite', db: 'survey_analytics' }
      ]
    });
    
    db.createCollection('survey_responses');
    db.survey_responses.createIndex({ surveyId: 1 });
    db.survey_responses.createIndex({ submittedAt: -1 });
    db.survey_responses.createIndex({ userId: 1 });
    
    db = db.getSiblingDB('survey_analytics');
    db.createCollection('text_analysis');
    db.createCollection('rating_analysis');
    db.createCollection('tech_popularity');
    db.createCollection('daily_stats');
    db.createCollection('tech_trends');
    db.createCollection('correlations');
    db.createCollection('hourly_report');
    
    print('MongoDB initialized successfully');
---
apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-init
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-init
spec:
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-init
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: init
          image: mongo:7.0
          command: 
            - mongosh
            - --host
            - mongodb
            - --username
            - admin
            - --password
            - adminpassword
            - --authenticationDatabase
            - admin
            - /scripts/init.js
          volumeMounts:
            - name: init-script
              mountPath: /scripts
      volumes:
        - name: init-script
          configMap:
            name: mongodb-init
YAML

 cat > "${BASE_DIR}/elasticsearch.yaml" <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  serviceName: elasticsearch
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: elasticsearch
    spec:
      initContainers:
        - name: fix-permissions
          image: busybox:1.35
          command: ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
          securityContext:
            privileged: true
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
      containers:
        - name: elasticsearch
          image: elasticsearch:8.10.2
          env:
            - name: discovery.type
              value: single-node
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
            - name: xpack.security.enabled
              value: "false"
            - name: xpack.security.enrollment.enabled
              value: "false"
            - name: xpack.monitoring.collection.enabled
              value: "true"
          ports:
            - containerPort: 9200
              name: http
            - containerPort: 9300
              name: transport
          volumeMounts:
            - name: elasticsearch-data
              mountPath: /usr/share/elasticsearch/data
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          readinessProbe:
            httpGet:
              path: /_cluster/health
              port: 9200
            initialDelaySeconds: 60
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: elasticsearch-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: elasticsearch
spec:
  ports:
    - port: 9200
      targetPort: 9200
      name: http
    - port: 9300
      targetPort: 9300
      name: transport
  selector:
    app: ${PROJECT}
    component: elasticsearch
YAML

 cat > "${BASE_DIR}/logstash.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: logstash
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: logstash
    spec:
      containers:
        - name: logstash
          image: logstash:8.10.2
          ports:
            - containerPort: 5000
              name: tcp
            - containerPort: 5001
              name: http
            - containerPort: 9600
              name: monitoring
          env:
            - name: XPACK_MONITORING_ENABLED
              value: "false"
          volumeMounts:
            - name: logstash-config
              mountPath: /usr/share/logstash/pipeline/
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            tcpSocket:
              port: 9600
            initialDelaySeconds: 30
            periodSeconds: 10
      volumes:
        - name: logstash-config
          configMap:
            name: logstash-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
data:
  logstash.conf: |
    input {
      tcp {
        port => 5000
        codec => json
      }
      http {
        port => 5001
        codec => json
      }
      beats {
        port => 5044
      }
    }
    
    filter {
      if [type] == "survey" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "surveys-%{+YYYY.MM.dd}"
          }
        }
      } else if [type] == "spark" {
        mutate {
          add_field => { 
            "[@metadata][index]" => "spark-%{+YYYY.MM.dd}"
          }
        }
      } else {
        mutate {
          add_field => { 
            "[@metadata][index]" => "logs-%{+YYYY.MM.dd}"
          }
        }
      }
      
      date {
        match => [ "timestamp", "ISO8601" ]
        target => "@timestamp"
      }
      
      mutate {
        remove_field => [ "timestamp" ]
      }
    }
    
    output {
      elasticsearch {
        hosts => ["elasticsearch:9200"]
        index => "%{[@metadata][index]}"
      }
      
      stdout {
        codec => rubydebug
      }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: logstash
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: logstash
spec:
  ports:
    - port: 5000
      targetPort: 5000
      name: tcp
    - port: 5001
      targetPort: 5001
      name: http
    - port: 5044
      targetPort: 5044
      name: beats
  selector:
    app: ${PROJECT}
    component: logstash
YAML

 cat > "${BASE_DIR}/kibana.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: kibana
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: kibana
    spec:
      containers:
        - name: kibana
          image: kibana:8.10.2
          ports:
            - containerPort: 5601
          env:
            - name: ELASTICSEARCH_HOSTS
              value: "http://elasticsearch:9200"
            - name: XPACK_MONITORING_ENABLED
              value: "true"
            - name: XPACK_SECURITY_ENABLED
              value: "false"
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          readinessProbe:
            httpGet:
              path: /api/status
              port: 5601
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: kibana
spec:
  ports:
    - port: 5601
      targetPort: 5601
  selector:
    app: ${PROJECT}
    component: kibana
YAML

 cat > "${BASE_DIR}/spring-app-deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spring-app
    spec:
      initContainers:
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-elasticsearch
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until wget -q -O- http://elasticsearch:9200; do
                echo "Waiting for Elasticsearch..."
                sleep 5
              done
      containers:
        - name: spring-app
          image: ghcr.io/exea-centrum/website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar-spring:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_DATA_MONGODB_URI
              value: "mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db"
            - name: SPRING_KAFKA_BOOTSTRAP_SERVERS
              value: "kafka:9092"
            - name: ELASTICSEARCH_URL
              value: "http://elasticsearch:9200"
            - name: LOGSTASH_URL
              value: "http://logstash:5000"
            - name: JAVA_OPTS
              value: "-Xms512m -Xmx512m -XX:+UseG1GC"
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "1000m"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spring-app-service
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: ${PROJECT}
    component: spring-app
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spring-app-config
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spring-app
data:
  application.yml: |
    spring:
      data:
        mongodb:
          uri: mongodb://survey_user:survey_password@mongodb:27017/survey_db?authSource=survey_db
          auto-index-creation: true
      
      kafka:
        bootstrap-servers: kafka:9092
        producer:
          key-serializer: org.apache.kafka.common.serialization.StringSerializer
          value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
        consumer:
          group-id: spring-survey-group
          key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
          value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
          properties:
            spring.json.trusted.packages: "*"
    
    management:
      endpoints:
        web:
          exposure:
            include: health,info,metrics,prometheus
      metrics:
        export:
          prometheus:
            enabled: true
    
    logging:
      level:
        com.davtroweb: DEBUG
      file:
        name: /var/log/spring-app.log
    
    elk:
      elasticsearch-url: http://elasticsearch:9200
      logstash-url: http://logstash:5000
    
    spark:
      master-url: spark://spark-master:7077
YAML

 cat > "${BASE_DIR}/spark-master.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-master
    spec:
      initContainers:
        - name: wait-for-kafka
          image: confluentinc/cp-kafka:7.5.0
          command: 
            - sh
            - -c
            - |
              until kafka-broker-api-versions --bootstrap-server kafka:9092; do
                echo "Waiting for Kafka..."
                sleep 5
              done
        - name: wait-for-mongodb
          image: mongo:7.0
          command: ['mongosh', '--host', 'mongodb', '--eval', 'db.adminCommand("ping")']
      containers:
        - name: spark-master
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 7077
              name: master
            - containerPort: 8080
              name: webui
            - containerPort: 4040
              name: jobui
          env:
            - name: SPARK_MODE
              value: "master"
            - name: SPARK_MASTER_HOST
              value: "spark-master"
            - name: SPARK_MASTER_PORT
              value: "7077"
            - name: SPARK_MASTER_WEBUI_PORT
              value: "8080"
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_LOCAL_STORAGE_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_SSL_ENABLED
              value: "no"
          resources:
            requests:
              cpu: "500m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 7077
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-master
spec:
  ports:
    - port: 7077
      targetPort: 7077
      name: master
    - port: 8080
      targetPort: 8080
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-master
YAML

 cat > "${BASE_DIR}/spark-worker.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spark-worker
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: spark-worker
    spec:
      initContainers:
        - name: wait-for-spark-master
          image: busybox:1.35
          command: 
            - sh
            - -c
            - |
              until nc -z spark-master 7077; do
                echo "Waiting for Spark Master..."
                sleep 5
              done
      containers:
        - name: spark-worker
          image: bitnami/spark:3.4.0
          ports:
            - containerPort: 8081
              name: webui
          env:
            - name: SPARK_MODE
              value: "worker"
            - name: SPARK_MASTER_URL
              value: "spark://spark-master:7077"
            - name: SPARK_WORKER_CORES
              value: "2"
            - name: SPARK_WORKER_MEMORY
              value: "2g"
            - name: SPARK_WORKER_WEBUI_PORT
              value: "8081"
            - name: SPARK_RPC_AUTHENTICATION_ENABLED
              value: "no"
            - name: SPARK_RPC_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_LOCAL_STORAGE_ENCRYPTION_ENABLED
              value: "no"
            - name: SPARK_SSL_ENABLED
              value: "no"
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
          readinessProbe:
            tcpSocket:
              port: 8081
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: spark-worker
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: spark-worker
spec:
  ports:
    - port: 8081
      targetPort: 8081
      name: webui
  selector:
    app: ${PROJECT}
    component: spark-worker
YAML

 cat > "${BASE_DIR}/network-policies.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-fastapi-to-postgres
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-fastapi-to-redis
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: fastapi
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: redis
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-worker-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: worker
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kafka-ui-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: kafka-ui
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-init-to-all
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: redis
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-to-postgres-exporter
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: prometheus
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres-exporter
      ports:
        - protocol: TCP
          port: 9187

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-pgadmin-to-postgres
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: pgadmin
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: postgres
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-communication
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: grafana
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: prometheus
      ports:
        - protocol: TCP
          port: 9090
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: loki
      ports:
        - protocol: TCP
          port: 3100
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: tempo
      ports:
        - protocol: TCP
          port: 3200

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-app-pods-to-deps
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-postgres-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 5432

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-redis-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 6379

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-kafka-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: kafka
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spring-to-mongodb
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: mongodb
      ports:
        - protocol: TCP
          port: 27017

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spark-to-kafka
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: kafka
      ports:
        - protocol: TCP
          port: 9092

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spark-to-mongodb
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: ${PROJECT}
      component: spark-master
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: ${PROJECT}
              component: mongodb
      ports:
        - protocol: TCP
          port: 27017
YAML

 cat > "${BASE_DIR}/monitoring-extended.yaml" <<YAML
# Exporter dla MongoDB
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  template:
    metadata:
      labels:
        app: ${PROJECT}
        component: mongodb-exporter
    spec:
      containers:
        - name: mongodb-exporter
          image: percona/mongodb_exporter:0.39.0
          ports:
            - containerPort: 9216
          args:
            - --mongodb.uri=mongodb://admin:adminpassword@mongodb:27017
            - --collect.collection
            - --collect.database
            - --collect.indexusage
            - --collect.connpoolstats
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-exporter
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
    component: mongodb-exporter
spec:
  ports:
    - port: 9216
      targetPort: 9216
  selector:
    app: ${PROJECT}
    component: mongodb-exporter

# ServiceMonitor dla MongoDB
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: mongodb-exporter
  endpoints:
  - port: http
    interval: 30s

# ServiceMonitor dla Spring Boot
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: spring-app
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 15s

# ServiceMonitor dla Elasticsearch
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: elasticsearch-monitor
  namespace: ${NAMESPACE}
  labels:
    app: ${PROJECT}
spec:
  selector:
    matchLabels:
      app: ${PROJECT}
      component: elasticsearch
  endpoints:
  - port: http
    path: /_prometheus/metrics
    interval: 30s

# Dodatkowe dashbordy Grafana
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-extended
  namespace: ${NAMESPACE}
data:
  spring-boot-dashboard.json: |-
    {
      "dashboard": {
        "title": "Spring Boot Metrics",
        "panels": [
          {
            "title": "HTTP Requests",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(http_server_requests_seconds_count[5m])",
                "legendFormat": "{{method}} {{status}}"
              }
            ]
          }
        ]
      }
    }
  
  spark-dashboard.json: |-
    {
      "dashboard": {
        "title": "Apache Spark",
        "panels": [
          {
            "title": "Spark Applications",
            "type": "stat",
            "targets": [
              {
                "expr": "spark_running_applications",
                "legendFormat": "Running Apps"
              }
            ]
          }
        ]
      }
    }
  
  mongodb-dashboard.json: |-
    {
      "dashboard": {
        "title": "MongoDB Metrics",
        "panels": [
          {
            "title": "MongoDB Connections",
            "type": "stat",
            "targets": [
              {
                "expr": "mongodb_connections_current",
                "legendFormat": "Connections"
              }
            ]
          }
        ]
      }
    }
  
  elk-dashboard.json: |-
    {
      "dashboard": {
        "title": "ELK Stack",
        "panels": [
          {
            "title": "Elasticsearch Health",
            "type": "stat",
            "targets": [
              {
                "expr": "elasticsearch_cluster_health_status",
                "legendFormat": "{{cluster}}"
              }
            ]
          }
        ]
      }
    }
YAML

 cat > "${BASE_DIR}/ingress-extended.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${PROJECT}-ingress-extended
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
spec:
  rules:
  - host: app.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /new-survey
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/v2
        pathType: Prefix
        backend:
          service:
            name: fastapi-web-service
            port:
              number: 80
      - path: /api/spring
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spring.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spring-app-service
            port:
              number: 8080
  
  - host: spark.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spark-master
            port:
              number: 8080
  
  - host: kibana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kibana
            port:
              number: 5601
  
  - host: grafana.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana-service
            port:
              number: 80
  
  - host: pgadmin.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  
  - host: kafka-ui.${PROJECT}.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kafka-ui
            port:
              number: 8080
YAML

 cat > "${BASE_DIR}/kyverno-policy.yaml" <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-requests-limits
  labels:
    app: ${PROJECT}
    app.kubernetes.io/name: ${PROJECT}
    app.kubernetes.io/instance: ${PROJECT}
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: check-container-resources
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "For production, all containers should define 'requests' and 'limits' for CPU and memory."
      pattern:
        spec:
          containers:
          - resources:
              requests:
                memory: "?*"
                cpu: "?*"
              limits:
                memory: "?*"
                cpu: "?*"
YAML

 cat > "${BASE_DIR}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}

resources:
  # Istniejące zasoby
  - postgres-db.yaml
  - postgres-clusterip.yaml
  - redis.yaml
  - vault.yaml
  - kafka-kraft.yaml
  - kafka-job-sa.yaml
  - kafka-topic-job.yaml
  - fastapi-config.yaml
  - app-deployment.yaml
  - message-processor.yaml
  - prometheus-config.yaml
  - postgres-exporter.yaml
  - kafka-exporter.yaml
  - node-exporter.yaml
  - service-monitors.yaml
  - prometheus.yaml
  - grafana-datasource.yaml
  - grafana-dashboards.yaml
  - grafana.yaml
  - loki-config.yaml
  - loki.yaml
  - promtail-config.yaml
  - promtail.yaml
  - tempo-config.yaml
  - tempo.yaml
  - pgadmin.yaml
  - kafka-ui.yaml
  - network-policies.yaml
  - kyverno-policy.yaml
  
  # Nowe zasoby
  - mongodb.yaml
  - elasticsearch.yaml
  - logstash.yaml
  - kibana.yaml
  - spring-app-deployment.yaml
  - spark-master.yaml
  - spark-worker.yaml
  - monitoring-extended.yaml
  - ingress-extended.yaml

# Common labels
commonLabels:
  app: ${PROJECT}
  app.kubernetes.io/name: ${PROJECT}
  app.kubernetes.io/instance: ${PROJECT}
  app.kubernetes.io/managed-by: kustomize

# Zmienne
vars:
  - name: NAMESPACE
    objref:
      kind: Namespace
      name: davtroelkpyjs
    fieldref:
      fieldpath: metadata.name
  - name: PROJECT
    objref:
      kind: ConfigMap
      name: fastapi-config
    fieldref:
      fieldpath: data.PROJECT
YAML

 cat > "${ROOT_DIR}/argocd-application.yaml" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${PROJECT}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}

generate_readme(){
 cat > "${ROOT_DIR}/README.md" <<README
# ${PROJECT} - Complete Monitoring Stack with Spring Boot, Spark & ELK

## 🛠️ Quick Start

\`\`\`bash
# Generate all files
./lmarena.sh generate

# Deploy to Kubernetes
kubectl apply -k manifests/base

# Watch pods
kubectl -n ${NAMESPACE} get pods -w

# Access applications:
# Main App: http://app.${PROJECT}.local
# New Survey: http://app.${PROJECT}.local/new-survey
# Spring Boot API: http://spring.${PROJECT}.local
# Spark UI: http://spark.${PROJECT}.local
# Kibana: http://kibana.${PROJECT}.local
# Grafana: http://grafana.${PROJECT}.local (admin/admin)
# PgAdmin: http://pgadmin.${PROJECT}.local (admin@example.com/adminpassword)
# Kafka UI: http://kafka-ui.${PROJECT}.local

# Initialize Vault
kubectl wait --for=condition=complete job/vault-init -n ${NAMESPACE}

# Initialize MongoDB
kubectl wait --for=condition=complete job/mongodb-init -n ${NAMESPACE}
\`\`\`

## 🌐 Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://app.${PROJECT}.local | - |
| New Survey (Spring Boot) | http://app.${PROJECT}.local/new-survey | - |
| Spring Boot API | http://spring.${PROJECT}.local | - |
| Spark Master UI | http://spark.${PROJECT}.local | - |
| Kibana | http://kibana.${PROJECT}.local | - |
| Grafana | http://grafana.${PROJECT}.local | admin/admin |
| PgAdmin | http://pgadmin.${PROJECT}.local | admin@example.com/adminpassword |
| Kafka UI | http://kafka-ui.${PROJECT}.local | - |

## 🏗️ Architecture Components:

### 1. **Python FastAPI Stack** (Original)
- **FastAPI Application** - Main web application with Vault integration
- **PostgreSQL** - Relational database for survey data
- **Redis** - Message queue for async processing
- **Kafka** - Event streaming platform
- **Vault** - Secrets management
- **Monitoring Stack** - Prometheus, Grafana, Loki, Tempo

### 2. **Java Spring Boot Stack** (New)
- **Spring Boot API** - REST API for new survey with MongoDB
- **MongoDB** - NoSQL database for survey responses
- **Apache Spark** - Real-time data processing and analytics
- **ELK Stack** - Elasticsearch, Logstash, Kibana for logging

### 3. **JavaScript Frontend** (New)
- **Modern JavaScript UI** - Interactive survey with React-like components
- **Chart.js** - Data visualization for survey statistics
- **Tailwind CSS** - Modern styling

## 🔧 Integration Details:

1. **Hybrid Architecture** - Python FastAPI + Java Spring Boot + JavaScript frontend
2. **Multiple Databases** - PostgreSQL (relational) + MongoDB (NoSQL)
3. **Real-time Processing** - Kafka + Apache Spark for data streaming
4. **Centralized Logging** - ELK Stack for logs from all components
5. **Unified Monitoring** - Prometheus + Grafana for all services
6. **Secrets Management** - HashiCorp Vault for all credentials

## 📊 Monitoring Stack:

- **Prometheus** - metrics collection from all services
- **Grafana** - unified dashboards with all datasources
- **Loki** - centralized log aggregation
- **Tempo** - distributed tracing
- **Postgres Exporter** - PostgreSQL metrics
- **MongoDB Exporter** - MongoDB metrics
- **Kafka Exporter** - Kafka metrics
- **Node Exporter** - system metrics

## 🔐 Security:

- All passwords in Vault
- Network policies for service communication
- Proper security contexts for databases
- Health checks and resource limits for all containers
- TLS/SSL ready configuration

## 🚀 Deployment Scripts:

\`\`\`bash
# Full deployment
./deploy-extended.sh

# Check status
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
kubectl get ingress -n ${NAMESPACE}
\`\`\`

## 🔄 CI/CD Pipeline:

GitHub Actions automatically builds and deploys:
1. **Python FastAPI application**
2. **Spring Boot Java application**
3. **Apache Spark jobs**
4. **Deploys to Kubernetes**

## 📈 Data Flow:

1. User submits survey via JavaScript frontend
2. Data sent to Spring Boot API via FastAPI proxy
3. Spring Boot saves to MongoDB and sends to Kafka
4. Apache Spark processes data in real-time
5. Results saved to MongoDB analytics collections
6. Logs sent to ELK Stack
7. Metrics collected by Prometheus
8. Visualizations in Grafana and Kibana

## 🐛 Troubleshooting:

\`\`\`bash
# Check logs
kubectl logs -f deployment/fastapi-web-app -n ${NAMESPACE}
kubectl logs -f deployment/spring-app -n ${NAMESPACE}
kubectl logs -f deployment/spark-master -n ${NAMESPACE}

# Check database connections
kubectl exec -it deployment/fastapi-web-app -n ${NAMESPACE} -- python -c "import psycopg2; psycopg2.connect('dbname=webdb user=webuser password=testpassword host=postgres-db-normal port=5432')"
kubectl exec -it deployment/spring-app -n ${NAMESPACE} -- curl http://localhost:8080/actuator/health

# Restart deployments
kubectl rollout restart deployment/fastapi-web-app -n ${NAMESPACE}
kubectl rollout restart deployment/spring-app -n ${NAMESPACE}
\`\`\`

## 📚 Documentation:

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ELK Stack Documentation](https://www.elastic.co/guide/index.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
README
}

generate_deploy_script(){
 cat > "${ROOT_DIR}/deploy-extended.sh" <<'BASH'
#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="davtroelkpyjs"

echo "🚀 Deploying Extended Stack: Spring Boot + Spark + MongoDB + ELK"

# 1. Deploy new databases
echo "📦 Deploying MongoDB..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/mongodb.yaml" -n "${NAMESPACE}"

echo "📦 Deploying ELK Stack..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/elasticsearch.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/logstash.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/kibana.yaml" -n "${NAMESPACE}"

# 2. Wait for databases
echo "⏳ Waiting for MongoDB..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=mongodb -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Elasticsearch..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=elasticsearch -n "${NAMESPACE}" --timeout=300s

# 3. Initialize MongoDB
echo "🔧 Initializing MongoDB..."
kubectl wait --for=condition=complete job/mongodb-init -n "${NAMESPACE}" --timeout=300s

# 4. Deploy Spark
echo "⚡ Deploying Apache Spark..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-master.yaml" -n "${NAMESPACE}"
kubectl apply -f "${PROJECT_DIR}/manifests/base/spark-worker.yaml" -n "${NAMESPACE}"

# 5. Deploy Spring Boot
echo "🌱 Deploying Spring Boot..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/spring-app-deployment.yaml" -n "${NAMESPACE}"

# 6. Wait for services
echo "⏳ Waiting for Spark Master..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=spark-master -n "${NAMESPACE}" --timeout=300s

echo "⏳ Waiting for Spring Boot..."
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=spring-app -n "${NAMESPACE}" --timeout=300s

# 7. Update FastAPI with new routes
echo "🔄 Updating FastAPI deployment..."
kubectl rollout restart deployment/fastapi-web-app -n "${NAMESPACE}"
kubectl wait --for=condition=ready pod -l app=website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar,component=fastapi -n "${NAMESPACE}" --timeout=300s

# 8. Update Ingress
echo "🌐 Updating Ingress..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/ingress-extended.yaml" -n "${NAMESPACE}"

# 9. Update monitoring
echo "📊 Updating monitoring..."
kubectl apply -f "${PROJECT_DIR}/manifests/base/monitoring-extended.yaml" -n "${NAMESPACE}"

echo ""
echo "✅ Extended stack deployment complete!"
echo ""
echo "🌐 Access points:"
echo "   Main App:        http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   New Survey:      http://app.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local/new-survey"
echo "   Spring Boot API: http://spring.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Spark UI:        http://spark.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Kibana:          http://kibana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Grafana:         http://grafana.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   PgAdmin:         http://pgadmin.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo "   Kafka UI:        http://kafka-ui.website-db-vault-kaf-redis-arg-kust-kyv-elk-apm-sprig-spar.local"
echo ""
echo "🔍 Check pods:"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "📈 Check services:"
echo "   kubectl get svc -n ${NAMESPACE}"
BASH

 chmod +x "${ROOT_DIR}/deploy-extended.sh"
}

generate_all(){
 generate_structure
 generate_fastapi_app
 generate_spring_app
 generate_spark_jobs
 generate_dockerfile
 generate_github_actions
 generate_k8s_manifests
 generate_deploy_script
 generate_readme
 echo
 echo "✅ Generation complete!"
 echo "📁 Structure:"
 echo "   📁 app/ - FastAPI application with Vault integration and Spring Boot proxy"
 echo "   📁 java-app/ - Spring Boot application with MongoDB and Kafka"
 echo "   📁 spark-jobs/ - Apache Spark analytics jobs"
 echo "   📁 elk/ - ELK Stack configurations"
 echo "   📁 manifests/base/ - ALL Kubernetes manifests"
 echo "   📄 Dockerfile - Container definition"
 echo "   📄 .github/workflows/ci-cd-extended.yaml - GitHub Actions for full stack"
 echo "   📄 deploy-extended.sh - Deployment script"
 echo "   📄 README.md - Complete documentation"
 echo
 echo "🚀 Next steps:"
 echo "1. Deploy: ./deploy-extended.sh"
 echo "2. Watch: kubectl -n ${NAMESPACE} get pods -w"
 echo "3. Access main app: http://app.${PROJECT}.local"
 echo "4. Access new survey: http://app.${PROJECT}.local/new-survey"
 echo "5. Monitor: http://grafana.${PROJECT}.local (admin/admin)"
 echo "6. View logs: http://kibana.${PROJECT}.local"
 echo "7. Manage DB: http://pgadmin.${PROJECT}.local (admin@example.com/adminpassword)"
 echo "8. View Kafka: http://kafka-ui.${PROJECT}.local"
}

case "$1" in
  generate)
    generate_all
    ;;
  *)
    echo "Usage: $0 generate"
    exit 1
    ;;
esac